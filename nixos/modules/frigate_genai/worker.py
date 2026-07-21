"""Worker registration, async_main, HTTP server, and MQTT client for frigate-genai."""

import asyncio
import json
import logging
import os
import re
import threading
import shutil
import subprocess
import tempfile
import time
import urllib.request as _urllib_request
from concurrent.futures import ThreadPoolExecutor
from http.server import HTTPServer, BaseHTTPRequestHandler

import paho.mqtt.client as mqtt
from temporalio.client import Client
from temporalio.service import TLSConfig
from temporalio.common import (
    TypedSearchAttributes,
    SearchAttributePair,
    VersioningBehavior,
    WorkerDeploymentVersion,
)
from temporalio.worker import Worker, WorkerDeploymentConfig
from temporalio.api.enums.v1 import IndexedValueType
from temporalio.api.operatorservice.v1 import AddSearchAttributesRequest

from frigate_genai.config import (
    TASK_QUEUE,
    FFMPEG_TASK_QUEUE,
    GEMINI_TASK_QUEUE,
    OLLAMA_TASK_QUEUE,
    DEPLOYMENT_NAME,
    BUILD_ID,
    _SEARCH_CAMERA,
    _SEARCH_LABEL,
    _frigate_url,
)
from frigate_genai.s3_helpers import (
    _s3_get,
    _s3_put,
    _s3_delete,
    _s3_list,
    _s3_read_text,
    _s3_agent_prefix,
    _stats,
    load_json,
)
from frigate_genai.activities.select_model import select_model_activity
from frigate_genai.activities.lifecycle import update_description_activity, cleanup_cancelled_activity, summarize_agent_activity, save_agent_log_activity
from frigate_genai.activities.agent_state import init_agent_state_activity, init_subagent_state_activity
from frigate_genai.activities.genai_turn import run_genai_turn_activity
from frigate_genai.activities.tool_apply import apply_tool_messages_activity
from frigate_genai.activities.frame_extraction import transcode_into_parts_activity, fetch_snapshot_activity
from frigate_genai.activities.mqtt import _start_workflow_sync, _build_workflow_input, build_mqtt_client
from frigate_genai.tools.get_snapshot import tool_get_snapshot_activity
from frigate_genai.tools.show_frame import tool_show_frame_activity
from frigate_genai.tools.crop import tool_crop_activity
from frigate_genai.tools.compact import tool_compact_activity
from frigate_genai.tools.set_description import tool_set_description_activity
from frigate_genai.tools.upscale import tool_upscale_activity
from frigate_genai.tools.transcode import tool_transcode_activity
from frigate_genai.tools.find_keyframes import tool_find_keyframes_activity, tool_frame_diff_activity
from frigate_genai.tools.tag_image import tool_tag_image_activity
from frigate_genai.workflows.genai import GenAIWorkflow
from frigate_genai.workflows.agent_session import AgentSessionWorkflow
from frigate_genai.workflows.subagent import SubAgentWorkflow

log = logging.getLogger("frigate-genai-sidecar")

_temporal_client: Client | None = None
_main_event_loop: asyncio.AbstractEventLoop | None = None


# ── HTML UI ───────────────────────────────────────────────────────────

UI_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Frigate GenAI</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0f0f1a;color:#d4d4d8;font:13px system-ui,sans-serif;padding:16px}
h1{font-size:18px;font-weight:600;margin-bottom:12px;color:#fff}
.stats{display:flex;gap:20px;margin-bottom:16px;padding:10px 14px;background:#14142a;border-radius:8px;font-size:12px}
.stat{display:flex;flex-direction:column}
.stat-label{color:#666;font-size:10px;text-transform:uppercase;letter-spacing:.5px}
.stat-value{color:#d4d4d8;font-size:14px;font-weight:500}
.stat-value.ok{color:#4ade80}
.stat-value.off{color:#f87171}
table{width:100%;border-collapse:collapse}
th,td{padding:8px 10px;text-align:left;border-bottom:1px solid #1e1e32}
th{font-weight:500;color:#888;font-size:11px;text-transform:uppercase}
tr:hover{background:#1a1a2e}
img{border-radius:4px;max-height:60px}
.btn{background:#2d2d4a;color:#c8c8d0;border:1px solid #3d3d5e;padding:5px 12px;border-radius:5px;cursor:pointer;font-size:12px}
.btn:hover{background:#3d3d5e}
.btn:disabled{opacity:.4;cursor:default}
.ok{color:#4ade80}
.err{color:#f87171}
.desc{max-width:400px;font-size:11px;color:#999;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.loading{text-align:center;padding:40px;color:#666}
.toggle-wrap{display:flex;align-items:center;gap:8px;margin-bottom:16px}
.toggle{position:relative;width:40px;height:22px;background:#2d2d4a;border-radius:11px;cursor:pointer;border:1px solid #3d3d5e;transition:background .2s}
.toggle.on{background:#4ade80;border-color:#4ade80}
.toggle::after{content:'';position:absolute;width:16px;height:16px;border-radius:50%;background:#d4d4d8;top:2px;left:2px;transition:transform .2s}
.toggle.on::after{transform:translateX(18px);background:#0f0f1a}
.toggle-label{font-size:12px;color:#888}
.toggle-label.on{color:#4ade80}
</style>
</head>
<body>
<h1>Frigate GenAI Reprocess</h1>
<div class="toggle-wrap"><span id="toggle-btn" class="toggle" onclick="togglePause()"></span><span id="toggle-label" class="toggle-label">Ollama on</span></div>
<div class="toggle-wrap"><span id="genai-toggle-btn" class="toggle" onclick="toggleGenaiPause()"></span><span id="genai-toggle-label" class="toggle-label">GenAI running</span></div>
<div id="stats" class="loading" style="margin-bottom:12px">Loading stats...</div>
<div id="app" class="loading">Loading events...</div>
<script>
const SIDECAR = "";
const DESCRIBE = ["person","dog","cat","package","face","fox","deer","bear","horse","cow","raccoon","bird","motorcycle","bicycle","school_bus","boat","robot_lawnmower","umbrella","amazon","fedex","ups","usps","dhl","an_post","purolator","postnl","nzpost","postnord","gls","dpd","royal_mail","canada_post"];
async function load() {
  try {
    const r = await fetch("/api/events?limit=100");
    const events = await r.json();
    const filtered = events.filter(e => DESCRIBE.includes(e.label) && e.has_clip && e.end_time);
    if (!filtered.length) { app.innerHTML = '<p>No eligible events found.</p>'; return; }
    let html = '<table><tr><th>Snapshot</th><th>Camera</th><th>Label</th><th>Duration</th><th>Description</th><th></th><th></th></tr>';
    for (const e of filtered) {
      const dur = (e.end_time - e.start_time).toFixed(1) + "s";
      const desc = (e.data?.description || "").substring(0, 120);
      html += '<tr>';
      html += '<td><img src="/api/events/' + e.id + '/snapshot.jpg" loading="lazy"></td>';
      html += '<td>' + e.camera + '</td>';
      html += '<td>' + e.label + '</td>';
      html += '<td>' + dur + '</td>';
      html += '<td class="desc" title="' + (e.data?.description || "").replace(/"/g,"&quot;") + '">' + (desc || "—") + '</td>';
      html += '<td><a href="/agent/' + e.id + '" class="btn" target="_blank">View</a></td>';
      html += '<td><button class="btn" onclick="reprocess(\'' + e.id + '\',this)">Reprocess</button></td>';
      html += '</tr>';
    }
    html += '</table>';
    app.innerHTML = html;
  } catch(err) { app.innerHTML = '<p class="err">Failed to load: ' + err.message + '</p>'; }
}

async function reprocess(id, btn) {
  btn.textContent = "..."; btn.disabled = true;
  try {
    const r = await fetch("/reprocess/" + id, { method: "POST" });
    if (r.ok) { btn.textContent = "Sent!"; btn.classList.add("ok"); }
    else { btn.textContent = "Failed"; btn.classList.add("err"); }
  } catch(e) { btn.textContent = "Error"; btn.classList.add("err"); }
  setTimeout(() => { btn.textContent = "Reprocess"; btn.classList.remove("ok","err"); btn.disabled = false; }, 5000);
}
async function loadStats() {
  try {
    const r = await fetch("/api/stats");
    const s = await r.json();
    const mqtt = s.mqtt_connected ? '<span class="ok">OK</span>' : '<span class="off">Disconnected</span>';
    const statsEl = document.getElementById("stats");
    statsEl.className = "stats";
    statsEl.innerHTML = '<div class="stat"><span class="stat-label">MQTT</span><span class="stat-value">'+mqtt+'</span></div><div class="stat"><span class="stat-label">Processed</span><span class="stat-value">'+s.events_processed+'</span></div><div class="stat"><span class="stat-label">Last</span><span class="stat-value">'+(s.last_event||"—")+'</span></div>';
  } catch(e) { /* stats will stay as loading */ }
}
async function loadPause() {
  try {
    const r = await fetch("/api/pause");
    const d = await r.json();
    if (d.paused) { setPause(true); }
  } catch(e) {}
}

async function togglePause() {
  const r = await fetch("/api/pause", {method:"POST"});
  const d = await r.json();
  setPause(d.paused);
}

function setPause(paused) {
  const btn = document.getElementById("toggle-btn");
  const lbl = document.getElementById("toggle-label");
  btn.className = "toggle" + (paused ? "" : " on");
  lbl.textContent = paused ? "Ollama off" : "Ollama on";
  lbl.className = "toggle-label" + (paused ? "" : " on");
}

async function loadGenaiPause() {
  try {
    const r = await fetch("/api/genai-pause");
    const d = await r.json();
    setGenaiPause(d.global);
  } catch(e) {}
}
async function toggleGenaiPause() {
  const r = await fetch("/api/genai-pause", {method:"POST"});
  const d = await r.json();
  setGenaiPause(d.paused);
}
function setGenaiPause(paused) {
  const btn = document.getElementById("genai-toggle-btn");
  const lbl = document.getElementById("genai-toggle-label");
  btn.className = "toggle" + (paused ? "" : " on");
  lbl.textContent = paused ? "GenAI paused" : "GenAI running";
  lbl.className = "toggle-label" + (paused ? "" : " on");
}
loadPause();
loadGenaiPause();
loadStats();
load();
</script>
</body>
</html>"""


def _escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def _temporal_tls_config() -> TLSConfig | None:
    """Build a TLSConfig with SPIRE mTLS, or None when TLS is disabled.

    Requires SPIFFE_ENDPOINT_SOCKET and TEMPORAL_TLS_CA_PATH when TLS is
    enabled.  Fetches the X.509 SVID up to three times with five-second
    waits between attempts, constructs the full client certificate chain
    (leaf + bundle), and raises after the third failure — no plain-TLS
    fallback.
    """
    tls_enabled = os.environ.get("TEMPORAL_TLS", "").lower() in ("1", "true", "yes")
    if not tls_enabled:
        return None

    socket_path = os.environ.get("SPIFFE_ENDPOINT_SOCKET", "").replace("unix://", "")
    if not socket_path:
        raise RuntimeError("TEMPORAL_TLS enabled but SPIFFE_ENDPOINT_SOCKET is not set")

    server_ca_path = os.environ.get("TEMPORAL_TLS_CA_PATH")
    if not server_ca_path:
        raise RuntimeError("TEMPORAL_TLS enabled but TEMPORAL_TLS_CA_PATH is not set")

    last_err = None
    for attempt in range(1, 4):
        svid_dir = None
        try:
            svid_dir = tempfile.mkdtemp(prefix="svid-")
            subprocess.run([
                "spire-agent", "api", "fetch", "x509",
                "-socketPath", socket_path,
                "-write", svid_dir,
                "-timeout", "30s",
            ], check=True)
            # Concatenate leaf cert with bundle for full chain
            with open(f"{svid_dir}/svid.0.pem", "rb") as f:
                client_cert = f.read()
            with open(f"{svid_dir}/bundle.0.pem", "rb") as f:
                client_cert += f.read()
            with open(f"{svid_dir}/svid.0.key", "rb") as f:
                client_key = f.read()
            with open(server_ca_path, "rb") as f:
                server_ca = f.read()
            tls_config = TLSConfig(
                server_root_ca_cert=server_ca,
                client_cert=client_cert,
                client_private_key=client_key,
            )
            server_name = os.environ.get("TEMPORAL_TLS_SERVER_NAME")
            if server_name:
                tls_config.domain = server_name
            log.info("Fetched SPIRE X.509 SVID for mTLS (attempt %d)", attempt)
            return tls_config
        except Exception as e:
            last_err = e
            if attempt < 3:
                log.warning("SVID fetch attempt %d/3 failed (%s) — retrying in 5s", attempt, e)
                time.sleep(5)
        finally:
            if svid_dir is not None:
                shutil.rmtree(svid_dir, ignore_errors=True)

    raise RuntimeError(
        "Failed to fetch SPIRE X.509 SVID after 3 attempts: %s" % last_err
    )

async def async_main(prompts_path: str, provider_path: str, mode: str = "triggers") -> None:
    global _temporal_client, _main_event_loop

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )
    _main_event_loop = asyncio.get_running_loop()

    prompts = load_json(prompts_path)
    provider_cfg = load_json(provider_path)

    describe_labels = prompts.get("describe", [])
    log.info("GenAI provider: %s / %s", provider_cfg.get("provider"), provider_cfg.get("model"))
    log.info("Describe labels: %s", ", ".join(sorted(describe_labels)))

    temporal_address = os.environ.get("TEMPORAL_ADDRESS", "temporal-frontend.default.svc.cluster.local:7233")
    log.info("Connecting to Temporal at %s", temporal_address)

    tls_config = _temporal_tls_config()
    _temporal_client = await Client.connect(
        temporal_address,
        namespace="default",
        tls=tls_config,
    )
    _stats["temporal_connected"] = True

    try:
        await _temporal_client.operator_service.add_search_attributes(
            AddSearchAttributesRequest(
                search_attributes={
                    "Camera": IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD,
                    "Label": IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD,
                    "EventId": IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD,
                    "Duration": IndexedValueType.INDEXED_VALUE_TYPE_INT,
                    "Cost": IndexedValueType.INDEXED_VALUE_TYPE_INT,
                    "Model": IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD,
                    "Confidence": IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD,
                    "Transcode": IndexedValueType.INDEXED_VALUE_TYPE_BOOL,
                    "ToolFailures": IndexedValueType.INDEXED_VALUE_TYPE_INT,
                },
                namespace="default",
            ),
        )
        log.info("Search attributes registered: Camera, Label, EventId, Duration, Cost, Model, Confidence, Transcode, ToolFailures")
    except Exception as e:
        log.debug("Search attribute registration skipped: %s", e)

    mode_tasks = []
    misc_activities = [select_model_activity, update_description_activity, fetch_snapshot_activity, cleanup_cancelled_activity, init_agent_state_activity, init_subagent_state_activity, tool_upscale_activity]

    if mode == "triggers":
        deployment_config = WorkerDeploymentConfig(
            version=WorkerDeploymentVersion(
                deployment_name=DEPLOYMENT_NAME,
                build_id=BUILD_ID,
            ),
            use_worker_versioning=True,
            default_versioning_behavior=VersioningBehavior.PINNED,
        )
        main_worker = Worker(
            _temporal_client,
            task_queue=TASK_QUEUE,
            workflows=[GenAIWorkflow, AgentSessionWorkflow, SubAgentWorkflow],
            activities=misc_activities,
            deployment_config=deployment_config,
        )
        mode_tasks = [asyncio.create_task(main_worker.run())]
    elif mode == "ffmpeg":
        deployment_config = WorkerDeploymentConfig(
            version=WorkerDeploymentVersion(
                deployment_name=DEPLOYMENT_NAME,
                build_id=BUILD_ID,
            ),
            use_worker_versioning=True,
            default_versioning_behavior=VersioningBehavior.PINNED,
        )
        ffmpeg_worker = Worker(
            _temporal_client,
            task_queue=FFMPEG_TASK_QUEUE,
            activities=[transcode_into_parts_activity, tool_transcode_activity],
            activity_executor=ThreadPoolExecutor(max_workers=2),
            max_concurrent_activities=int(os.environ.get("TEMPORAL_MAX_FFMPEG", "2")),
            deployment_config=deployment_config,
        )
        mode_tasks = [asyncio.create_task(ffmpeg_worker.run())]
    elif mode == "genai-gemini":
        deployment_config = WorkerDeploymentConfig(
            version=WorkerDeploymentVersion(
                deployment_name=DEPLOYMENT_NAME,
                build_id=BUILD_ID,
            ),
            use_worker_versioning=True,
            default_versioning_behavior=VersioningBehavior.PINNED,
        )
        main_worker = Worker(
            _temporal_client,
            task_queue=TASK_QUEUE,
            activities=misc_activities,
            deployment_config=deployment_config,
        )
        gemini_worker = Worker(
            _temporal_client,
            task_queue=GEMINI_TASK_QUEUE,
            workflows=[AgentSessionWorkflow, SubAgentWorkflow],
            activities=[run_genai_turn_activity,
                        tool_find_keyframes_activity, tool_frame_diff_activity, tool_tag_image_activity,
                        tool_get_snapshot_activity, tool_show_frame_activity,
                        tool_crop_activity, tool_compact_activity,
                        tool_set_description_activity, apply_tool_messages_activity,
                        summarize_agent_activity,
                        save_agent_log_activity,
                        init_subagent_state_activity],
            max_concurrent_activities=int(os.environ.get("TEMPORAL_MAX_GEMINI_GENAI", "5")),
            deployment_config=deployment_config,
        )
        mode_tasks = [asyncio.create_task(w.run()) for w in [main_worker, gemini_worker]]
    elif mode == "genai-ollama":
        deployment_config = WorkerDeploymentConfig(
            version=WorkerDeploymentVersion(
                deployment_name=DEPLOYMENT_NAME,
                build_id=BUILD_ID,
            ),
            use_worker_versioning=True,
            default_versioning_behavior=VersioningBehavior.PINNED,
        )
        main_worker = Worker(
            _temporal_client,
            task_queue=TASK_QUEUE,
            activities=misc_activities,
            deployment_config=deployment_config,
        )
        ollama_worker = Worker(
            _temporal_client,
            task_queue=OLLAMA_TASK_QUEUE,
            workflows=[AgentSessionWorkflow, SubAgentWorkflow],
            activities=[run_genai_turn_activity,
                        tool_find_keyframes_activity, tool_frame_diff_activity, tool_tag_image_activity,
                        tool_get_snapshot_activity, tool_show_frame_activity,
                        tool_crop_activity, tool_compact_activity,
                        tool_set_description_activity, apply_tool_messages_activity,
                        summarize_agent_activity,
                        save_agent_log_activity,
                        init_subagent_state_activity],
            max_concurrent_activities=int(os.environ.get("TEMPORAL_MAX_OLLAMA_GENAI", "1")),
            deployment_config=deployment_config,
        )
        mode_tasks = [asyncio.create_task(w.run()) for w in [main_worker, ollama_worker]]

    # ── Health HTTP server (all modes) ──────────────────────────────────
    class _HealthHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            log.debug("HTTP health: %s", fmt % args)
        def do_GET(self):
            if self.path == "/healthz":
                if _stats["temporal_connected"]:
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"OK")
                else:
                    self.send_response(503)
                    self.end_headers()
            elif self.path == "/readyz":
                if _stats["temporal_connected"]:
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"READY")
                else:
                    self.send_response(503)
                    self.end_headers()
            elif self.path == "/metrics":
                build_id = os.environ.get("TEMPORAL_WORKER_BUILD_ID", "unknown")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(
                    f"# HELP frigate_genai_worker_info Worker deployment info\n"
                    f"# TYPE frigate_genai_worker_info gauge\n"
                    f'frigate_genai_worker_info{{version="{build_id}",healthy="{"1" if _stats["temporal_connected"] else "0"}"}} 1\n'
                    .encode()
                )
    if mode != "triggers":
        _health_port = int(os.environ.get("HTTP_PORT", "8080"))
        _health_host = os.environ.get("HTTP_HOST", "0.0.0.0")
        _health_server = HTTPServer((_health_host, _health_port), _HealthHandler)
        _health_thread = threading.Thread(target=_health_server.serve_forever, daemon=True)
        _health_thread.start()
        log.info("Health endpoint on http://%s:%d", _health_host, _health_port)

    # MQTT — starts workflows via Temporal client
    if mode == 'triggers':
        client_mqtt = build_mqtt_client(asyncio.get_running_loop())

    if mode == 'triggers':
        log.info("Frigate GenAI sidecar running, waiting for events...")

        async def _do_reprocess(event_id: str, event: dict) -> str:
            workflow_id = f"genai-{event_id}"
            try:
                handle = _temporal_client.get_workflow_handle(workflow_id)
                await handle.cancel()
                log.info("Cancelled old workflow %s for reprocess", workflow_id)
            except Exception:
                log.debug("No existing workflow %s to cancel", workflow_id)
            camera = event.get("camera", "")
            label = event.get("label", "")
            input_data = _build_workflow_input(event)
            if input_data is None:
                return f"Skipping {event_id} ({camera}/{label}): paused (global or per-label)"
            await _temporal_client.start_workflow(
                "GenAIWorkflow",
                input_data,
                id=workflow_id,
                task_queue=TASK_QUEUE,
                search_attributes=TypedSearchAttributes([
                    SearchAttributePair(_SEARCH_CAMERA, camera),
                    SearchAttributePair(_SEARCH_LABEL, label),
                ]),
                memo={"event_id": event_id, "camera": camera, "label": label,
                      "duration": int(event.get("end_time", event.get("start_time", 0)) - event.get("start_time", 0))})
            return f"Reprocessing {event_id} ({camera}/{label})"

        class ReprocessHandler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                log.debug("HTTP: %s", fmt % args)

            def _cors(self):
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")

            def do_OPTIONS(self):
                self.send_response(200)
                self._cors()
                self.end_headers()

            def do_GET(self):
                if self.path == "/":
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "text/html; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(UI_HTML.encode())
                elif self.path == "/api/stats":
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json; charset=utf-8")
                    self.end_headers()
                    if _stats["events_processed"] == 0:
                        saved = _s3_read_text("events/_stats.json")
                        if saved:
                            self.wfile.write(saved.encode())
                            return
                    self.wfile.write(json.dumps(_stats).encode())
                elif self.path == "/api/temporal":
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json; charset=utf-8")
                    self.end_headers()
                    stats = _stats
                    if _stats["events_processed"] == 0:
                        saved = _s3_read_text("events/_stats.json")
                        if saved:
                            stats = json.loads(saved)
                    self.wfile.write(json.dumps({
                        "connected": stats["temporal_connected"],
                        "task_queue": TASK_QUEUE,
                        "server": os.environ.get("TEMPORAL_ADDRESS", "192.168.5.10:32682"),
                        "events_processed": stats["events_processed"],
                    }).encode())
                elif self.path.startswith("/api/events/") and self.path.endswith("/snapshot.jpg"):
                    self._proxy("image/jpeg")
                elif self.path.startswith("/api/events"):
                    self._proxy("application/json")
                elif self.path == "/api/pause":
                    paused = _s3_get("events/_paused/ollama") is not None
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"paused": paused}).encode())
                elif self.path == "/api/genai-pause":
                    paused_global = _s3_get("events/_paused/genai") is not None
                    paused_labels = {}
                    for k in _s3_list("events/_paused/genai-"):
                        paused_labels[k[len("events/_paused/genai-"):]] = True
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({
                        "global": paused_global,
                        "labels": paused_labels,
                    }).encode())
                elif self.path.startswith("/agent/") and "/subagent/" in self.path:
                    self._serve_subagent_view()
                elif self.path.startswith("/agent/"):
                    self._serve_agent_view()
                elif self.path == "/healthz":
                    if _stats["temporal_connected"]:
                        self.send_response(200)
                        self.send_header("Content-Type", "text/plain")
                        self.end_headers()
                        self.wfile.write(b"OK")
                    else:
                        self.send_response(503)
                        self.end_headers()
                elif self.path == "/readyz":
                    if _stats["temporal_connected"]:
                        self.send_response(200)
                        self.send_header("Content-Type", "text/plain")
                        self.end_headers()
                        self.wfile.write(b"READY")
                    else:
                        self.send_response(503)
                        self.end_headers()
                elif self.path == "/metrics":
                    build_id = os.environ.get("TEMPORAL_WORKER_BUILD_ID", "unknown")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.end_headers()
                    self.wfile.write(
                        f"# HELP frigate_genai_worker_info Worker deployment info\n"
                        f"# TYPE frigate_genai_worker_info gauge\n"
                        f'frigate_genai_worker_info{{version="{build_id}",healthy="{"1" if _stats["temporal_connected"] else "0"}"}} 1\n'
                        .encode()
                    )
                else:
                    self.send_response(404)
                    self.end_headers()

            def _proxy(self, content_type):
                try:
                    resp = _urllib_request.urlopen(_frigate_url(self.path), timeout=15)
                    self.send_response(resp.status)
                    self._cors()
                    self.send_header("Content-type", content_type)
                    self.end_headers()
                    self.wfile.write(resp.read())
                except Exception as e:
                    self.send_response(502)
                    self._cors()
                    self.end_headers()
                    self.wfile.write(str(e).encode())

            def _serve_agent_view(self):
                parts = self.path.split("/")
                if len(parts) < 3:
                    self.send_response(400)
                    self.end_headers()
                    return
                event_id = parts[2]
                if len(parts) >= 5 and parts[3] == "file":
                    fname = parts[4]
                    # Read agent_dir from messages.json to get actual S3 prefix
                    msg_data = _s3_read_text(f"events/{event_id}/agent/messages.json")
                    agent_dir = f"events/{event_id}/agent/"
                    if msg_data:
                        try:
                            state = json.loads(msg_data)
                            agent_dir = state.get("agent_dir", agent_dir)
                        except Exception:
                            pass
                    # Subagent file? Check query param or path depth
                    sub_dir = parts[5] if len(parts) >= 6 else None
                    if sub_dir:
                        agent_dir = f"events/{event_id}/agent/subagent/{sub_dir}/"
                    data = _s3_get(f"{agent_dir}{fname}")
                    if data is None:
                        data = _s3_get(f"history/{event_id}/agent/{fname}")
                    if data is not None:
                        self.send_response(200)
                        self._cors()
                        self.send_header("Content-type", "image/jpeg")
                        self.end_headers()
                        self.wfile.write(data)
                    else:
                        self.send_response(404)
                        self.end_headers()
                    return
                msg_data = _s3_read_text(f"events/{event_id}/agent/messages.json")
                hist_fallback = False
                if msg_data is None:
                    msg_data = _s3_read_text(f"history/{event_id}/agent/messages.json")
                    hist_fallback = msg_data is not None
                if msg_data is None:
                    self.send_response(404)
                    self._cors()
                    self.send_header("Content-type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"Agent state not found")
                    return
                state = json.loads(msg_data)
                msgs = state.get("messages", [])
                agent_dir = state.get("agent_dir", "")
                if hist_fallback:
                    agent_dir = f"history/{event_id}/agent"
                html = ['<!DOCTYPE html><html><head><meta charset="utf-8">'
                        '<title>Agent: {}</title>'
                        '<style>*{{margin:0;padding:0;box-sizing:border-box}}'
                        'body{{background:#0f0f1a;color:#d4d4d8;font:13px system-ui;padding:16px}}'
                        'h1{{font-size:16px;margin-bottom:8px;color:#fff}}'
                        '.msg{{margin-bottom:12px;padding:10px 14px;border-radius:8px;max-width:900px}}'
                        '.msg.system{{background:#1a1a2e;border-left:3px solid #666}}'
                        '.msg.user{{background:#14283a;border-left:3px solid #4ade80}}'
                        '.msg.assistant{{background:#2a1a2e;border-left:3px solid #c084fc}}'
                        '.msg.tool{{background:#1a2e1a;border-left:3px solid #fbbf24}}'
                        '.role{{font-size:10px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px;color:#888}}'
                        'img{{max-width:400px;max-height:300px;border-radius:4px;margin:4px 4px 0 0;cursor:pointer}}'
                        'img:hover{{outline:2px solid #4ade80}}'
                        '.img-grid{{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start}}'
                        '.img-grid img{{max-height:300px;width:auto;cursor:pointer}}'
                        '.img-grid img.expanded{{max-height:none;max-width:100%}}'
                        '.res-badge{{font-size:10px;color:#888;display:block;text-align:center}}'
                        '.text{{line-height:1.5;white-space:pre-wrap}}'
                        '.tool-call{{font-size:11px;color:#c084fc;font-family:monospace}}'
                        '</style></head><body>'
                        '<h1>Agent: {}</h1>'.format(event_id, event_id)]
                for m in msgs:
                    role = m.get("role", "?")
                    html.append('<div class="msg {}"><div class="role">{}</div>'.format(role, role))
                    if role == "assistant":
                        tcs = m.get("tool_calls", [])
                        if tcs:
                            for tc in tcs:
                                name = tc.get("function", {}).get("name", "?")
                                args = tc.get("function", {}).get("arguments", "")
                                if isinstance(args, str):
                                    try: args = json.loads(args)
                                    except Exception: pass
                                html.append('<div class="tool-call">→ {}({})</div>'.format(
                                    _escape(name), _escape(json.dumps(args)[:200])))
                        content = m.get("content", "")
                        if content:
                            html.append('<div class="text">{}</div>'.format(_escape(str(content))))
                    elif role == "tool":
                        html.append('<div class="text">{}</div>'.format(_escape(str(m.get("content", "")))))
                    elif role == "user":
                        content = m.get("content", "")
                        if isinstance(content, list):
                            # FIRST PASS: Parse text parts to extract actual resolution
                            cur_res = "high"  # default
                            for part in content:
                                if isinstance(part, dict) and part.get("type") == "text":
                                    txt = part.get("text", "")
                                    res_m = re.search(r"at (\w+) resolution", txt)
                                    if res_m:
                                        cur_res = res_m.group(1)
                                        break  # Use first match
                            
                            # SECOND PASS: Render images with correct resolution badge
                            img_parts = [p for p in content if isinstance(p, dict) and p.get("type") == "image_url"]
                            has_multi = len(img_parts) > 1
                            if has_multi:
                                html.append('<div class="img-grid">')
                            for part in content:
                                if isinstance(part, dict):
                                    if part.get("type") == "image_url":
                                        url = part.get("image_url", {}).get("url", "")
                                        if url.startswith("[[") and url.endswith("]]"):
                                            fname = url[2:-2]
                                            sizes = {"low": "200", "med": "300", "high": "500", "max": "700", "tiny": "150"}
                                            w = sizes.get(cur_res, "400")
                                            src = f"/agent/{event_id}/file/{fname}"
                                            html.append('<img src="{}" loading="lazy" data-sized-width="{}">'.format(src, w))
                                            badge_text = cur_res
                                            html.append('<span class="res-badge">{}</span>'.format(_escape(badge_text)))
                                        else:
                                            html.append('<div class="text">[image: {}]</div>'.format(_escape(url[:80])))
                                    elif part.get("type") == "text":
                                        txt = part["text"]
                                        html.append('<div class="text">{}</div>'.format(_escape(txt)))
                            if has_multi:
                                html.append('</div>')
                        else:
                            html.append('<div class="text">{}</div>'.format(_escape(str(content))))
                    elif role == "system":
                        html.append('<div class="text">{}</div>'.format(_escape(str(m.get("content", "")))))
                    html.append('</div>')
                html.append('<div style="margin-top:16px;color:#666;font-size:11px">'
                            'camera: {} | start_time: {} | end_time: {} | max_frames: {}</div>'
                            .format(state.get("camera","?"), state.get("start_time","?"),
                                    state.get("end_time","?"), state.get("max_frames","?")))
                html.append('<script>'
                            'document.querySelectorAll(".msg.user img").forEach(function(i){'
                            'i.addEventListener("click",function(){'
                            'if(i.classList.contains("expanded")){'
                            'i.classList.remove("expanded");'
                            'i.style.maxWidth=i.dataset.sizedWidth+"px";'
                            'i.style.maxHeight=""'
                            '}else{'
                            'i.classList.add("expanded");'
                            'i.style.maxWidth="100%";'
                            'i.style.maxHeight="none"'
                            '}})})</script>'
                            '</body></html>')
                self.send_response(200)
                self._cors()
                self.send_header("Content-type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write("\n".join(html).encode())


            def _serve_subagent_view(self):
                parts = self.path.split("/")
                event_id = parts[2]
                sub_id = parts[4]  # s0, s1, ...
                msg_data = _s3_read_text(f"events/{event_id}/agent/subagent/{sub_id}/messages.json")
                if msg_data is None:
                    msg_data = _s3_read_text(f"history/{event_id}/agent/subagent/{sub_id}/messages.json")
                if msg_data is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                state = json.loads(msg_data)
                agent_dir = state.get("agent_dir", f"events/{event_id}/agent/subagent/{sub_id}/")
                task = state.get("task", "unknown task")
                msgs = state.get("messages", [])
                html = ['<!DOCTYPE html><html><head><meta charset="utf-8">'
                        f'<title>Subagent: {task[:60]}</title>'
                        '<style>*{{margin:0;padding:0;box-sizing:border-box}}'
                        'body{{background:#0f0f1a;color:#d4d4d8;font:13px system-ui;padding:16px}}'
                        'h1{{font-size:16px;margin-bottom:8px;color:#fff}}'
                        '.msg{{margin-bottom:12px;padding:10px 14px;border-radius:8px;max-width:900px}}'
                        '.msg.system{{background:#1a1a2e;border-left:3px solid #666}}'
                        '.msg.user{{background:#14283a;border-left:3px solid #4ade80}}'
                        '.msg.assistant{{background:#2a1a2e;border-left:3px solid #c084fc}}'
                        '.msg.tool{{background:#1a2e1a;border-left:3px solid #fbbf24}}'
                        '.role{{font-size:10px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px;color:#888}}'
                        'img{{max-width:400px;max-height:300px;border-radius:4px;margin:4px 4px 0 0;cursor:pointer}}'
                        'img:hover{{outline:2px solid #4ade80}}'
                        '.img-grid{{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start}}'
                        '.text{{white-space:pre-wrap;line-height:1.5}}'
                        '.expanded{{max-width:100%!important;max-height:none!important}}'
                        '</style></head><body>'
                        f'<div style="margin-bottom:12px"><a href="/agent/{event_id}" style="color:#4ade80;font-size:14px">'
                        f'&larr; Back to Agent {event_id}</a></div>'
                        f'<h1>Subagent: {task[:80]}</h1>']
                for m in msgs:
                    role = m.get("role", "?")
                    html.append(f'<div class="msg {role}">')
                    html.append(f'<div class="role">{role}</div>')
                    content = m.get("content", "")
                    if isinstance(content, list):
                        for part in content:
                            if isinstance(part, dict):
                                if part.get("type") == "image_url":
                                    url = part.get("image_url", {}).get("url", "")
                                    fname = url.lstrip("[[").rstrip("]]")
                                    from urllib.parse import quote
                                    html.append(f'<img src="/agent/{event_id}/file/{fname}" loading="lazy">')
                                elif part.get("type") == "text":
                                    from html import escape
                                    html.append(f'<div class="text">{escape(part.get("text",""))}</div>')
                    elif isinstance(content, str):
                        from html import escape
                        html.append(f'<div class="text">{escape(content)}</div>')
                    html.append('</div>')
                html.append(f'<div style="margin-top:16px;color:#666;font-size:11px">'
                            f'task: {task} | camera: {state.get("camera","?")} | '
                            f'start_time: {state.get("start_time","?")}</div>')
                html.append('</body></html>')
                self.send_response(200)
                self._cors()
                self.send_header("Content-type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write("\n".join(html).encode())

            def do_POST(self):
                if self.path.startswith("/reprocess/"):
                    event_id = self.path.split("/reprocess/", 1)[1]
                    try:
                        resp = _urllib_request.urlopen(_frigate_url(f"/api/events/{event_id}"), timeout=10)
                        event = json.loads(resp.read())
                        if _temporal_client is None:
                            self.send_response(503)
                            self._cors()
                            self.send_header("Content-type", "text/plain")
                            self.end_headers()
                            self.wfile.write(b"Temporal not connected")
                            return
                        msg = asyncio.run(_do_reprocess(event_id, event))
                        self.send_response(200)
                        self._cors()
                        self.send_header("Content-type", "text/plain")
                        self.end_headers()
                        self.wfile.write(msg.encode())
                        log.info("HTTP reprocess: %s", msg)
                    except Exception as e:
                        log.exception("Reprocess failed: %s", e)
                        self.send_response(500)
                        self._cors()
                        self.send_header("Content-type", "text/plain")
                        self.end_headers()
                        self.wfile.write(str(e).encode())
                elif self.path == "/api/pause":
                    existing = _s3_get("events/_paused/ollama")
                    if existing is None:
                        _s3_put("events/_paused/ollama", b"1")
                    else:
                        _s3_delete("events/_paused/ollama")

                    # Re-check paused state and send response
                    paused = _s3_get("events/_paused/ollama") is not None
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"paused": paused}).encode())
                elif self.path == "/api/genai-pause":
                    existing = _s3_get("events/_paused/genai")
                    if existing is None:
                        _s3_put("events/_paused/genai", b"1")
                    else:
                        _s3_delete("events/_paused/genai")

                    # Re-check paused state and send response
                    paused = _s3_get("events/_paused/genai") is not None
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"paused": paused}).encode())
                else:
                    self.send_response(404)
                    self.end_headers()

        http_host = os.environ.get("HTTP_HOST", "0.0.0.0")
        http_port = int(os.environ.get("HTTP_PORT", "8080"))
        http_server = HTTPServer((http_host, http_port), ReprocessHandler)
        http_thread = threading.Thread(target=http_server.serve_forever, daemon=True)
        http_thread.start()
        log.info("HTTP reprocess endpoint on http://%s:%d", http_host, http_port)

    try:
        await asyncio.gather(*mode_tasks)
    except asyncio.CancelledError:
        log.info("Workers shutting down")
        if mode == 'triggers':
            client_mqtt.disconnect()
