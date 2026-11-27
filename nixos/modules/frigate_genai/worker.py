"""Worker registration, async_main, HTTP server, and MQTT client for frigate-genai."""

import asyncio
import json
import logging
import os
import hmac
import threading
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.request as _urllib_request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler

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
    DISPATCHER_TASK_QUEUE,
    FFMPEG_TASK_QUEUE,
    LLM_TASK_QUEUE,
    DEPLOYMENT_NAME,
    BUILD_ID,
    _SEARCH_CAMERA,
    _SEARCH_LABEL,
    _SEARCH_EVENT_ID,
    WORKER_GRACEFUL_SHUTDOWN,
    _frigate_url,
)
from frigate_genai.s3_helpers import (
    _s3_get,
    _s3_put,
    _s3_delete,
    _s3_list,
    _s3_read_text,
    _stats,
    load_json,
)
from frigate_genai.activities.select_model import select_model_activity
from frigate_genai.activities.lifecycle import (
    cleanup_cancelled_activity,
    label_only_activity,
    update_description_activity,
)
from frigate_genai.activities.records import record_result_activity
from frigate_genai.activities.describe import run_describe_scene
from frigate_genai.activities.frames import crop_detection_activity
from frigate_genai.activities.dispatcher import (
    collect_scenes_activity,
    finish_drain_activity,
    gate_status_activity,
    genai_paused_activity,
)
from frigate_genai.activities.llm import warm_openai_client
from frigate_genai.activities.frame_extraction import transcode_into_parts_activity, fetch_snapshot_activity
from frigate_genai.activities.mqtt import _start_workflow_sync, _build_workflow_input, build_mqtt_client
from frigate_genai.tools.find_keyframes import pick_keyframes_activity
from frigate_genai.workflows.genai import GenAIWorkflow
from frigate_genai.workflows.drain import DrainWorkflow

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
.toggle.unknown{background:#b45309;border-color:#b45309;cursor:default}
.toggle.unknown::after{transform:translateX(9px)}
.toggle-label.unknown{color:#fbbf24}
</style>
</head>
<body>
<h1>Frigate GenAI Reprocess</h1>
<div class="toggle-wrap"><span id="toggle-btn" class="toggle unknown" onclick="togglePause()"></span><span id="toggle-label" class="toggle-label unknown">Ollama …</span></div>
<div class="toggle-wrap"><span id="genai-toggle-btn" class="toggle unknown" onclick="toggleGenaiPause()"></span><span id="genai-toggle-label" class="toggle-label unknown">GenAI …</span></div>
<div style="margin-bottom:12px">
  <label for="model-input" style="color:#888;font-size:12px;margin-right:6px">Model:</label>
  <input id="model-input" list="model-list" placeholder="auto" style="background:#1a1a2e;color:#c8c8d0;border:1px solid #3d3d5e;padding:4px 8px;border-radius:4px;font-size:12px;width:200px">
  <datalist id="model-list"></datalist>
</div>
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
      const id = esc(e.id);
      html += '<tr>';
      html += '<td><img src="/api/events/' + encodeURIComponent(e.id) + '/snapshot.jpg" loading="lazy"></td>';
      html += '<td>' + esc(e.camera) + '</td>';
      html += '<td>' + esc(e.label) + '</td>';
      html += '<td>' + esc(dur) + '</td>';
      html += '<td class="desc" title="' + esc(e.data?.description || "") + '">' + (desc ? esc(desc) : "—") + '</td>';
      html += '<td><button class="btn" onclick="reprocess(\'' + id + '\',this)">Reprocess</button></td>';
      html += '<td><button class="btn" onclick="reprocessWithModel(\'' + id + '\',this)">Reprocess w/ model</button></td>';
      html += '</tr>';
    }
    html += '</table>';
    app.innerHTML = html;
  } catch(err) { app.innerHTML = '<p class="err">Failed to load: ' + esc(err.message) + '</p>'; }
}

function esc(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
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
async function reprocessWithModel(id, btn) {
  const model = document.getElementById("model-input").value.trim();
  if (!model) { btn.textContent = "No model"; btn.classList.add("err"); setTimeout(() => {btn.textContent="Reprocess w/ model"; btn.classList.remove("err");}, 2000); return; }
  btn.textContent = "..."; btn.disabled = true;
  try {
    const r = await fetch("/reprocess/" + id + "?model=" + encodeURIComponent(model), { method: "POST" });
    if (r.ok) { btn.textContent = "Sent!"; btn.classList.add("ok"); }
    else { btn.textContent = "Failed"; btn.classList.add("err"); }
  } catch(e) { btn.textContent = "Error"; btn.classList.add("err"); }
  setTimeout(() => { btn.textContent = "Reprocess w/ model"; btn.classList.remove("ok","err"); btn.disabled = false; }, 5000);
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
    setPause(!!d.paused);
  } catch(e) {} /* backend unreachable → keep undefined state */
}

async function togglePause() {
  const btn = document.getElementById("toggle-btn");
  if (btn.classList.contains("unknown")) return;
  const r = await fetch("/api/pause", {method:"POST"});
  const d = await r.json();
  setPause(!!d.paused);
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
    setGenaiPause(!!d.global);
  } catch(e) {} /* backend unreachable → keep undefined state */
}
async function toggleGenaiPause() {
  const btn = document.getElementById("genai-toggle-btn");
  if (btn.classList.contains("unknown")) return;
  const r = await fetch("/api/genai-pause", {method:"POST"});
  const d = await r.json();
  setGenaiPause(!!d.paused);
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


def _provider_models() -> list[str]:
    """Return the configured model list from the baked provider.json."""
    try:
        return load_json("/var/lib/frigate-genai-sidecar/provider.json").get("model", [])
    except Exception:
        return []


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


def _install_stop_signal_handlers(loop: asyncio.AbstractEventLoop) -> asyncio.Event:
    """Return an Event set on SIGTERM/SIGINT. As container PID 1, python
    ignores SIGTERM unless a handler is installed, so pods sat out the full
    termination grace period and were SIGKILLed mid-activity."""
    stop = asyncio.Event()

    def _on_signal(signame: str) -> None:
        log.info("Received %s; shutting down (graceful timeout %s)", signame, WORKER_GRACEFUL_SHUTDOWN)
        stop.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _on_signal, sig.name)
    return stop


async def _run_until_stopped(workers: list[Worker], stop: asyncio.Event) -> None:
    """Run workers until one exits or `stop` is set, then gracefully shut down
    the ones still running. Re-raises the first worker error so a crashed
    worker still exits the process non-zero (container restart)."""
    run_tasks = [asyncio.create_task(w.run()) for w in workers]
    stop_task = asyncio.create_task(stop.wait())
    await asyncio.wait([*run_tasks, stop_task], return_when=asyncio.FIRST_COMPLETED)
    stop_task.cancel()
    # Only shut down workers whose run() is still going: Worker.shutdown()
    # waits for run() to finish normally and would hang on one that raised.
    await asyncio.gather(*(w.shutdown() for w, t in zip(workers, run_tasks) if not t.done()))
    results = await asyncio.gather(*run_tasks, return_exceptions=True)
    errors = [r for r in results if isinstance(r, BaseException)]
    if errors:
        raise errors[0]
    log.info("Workers shut down")


DRAIN_INTERVAL_SECONDS = 300
WORKFLOW_EXECUTION_TIMEOUT = timedelta(minutes=25)


async def _start_drain(prompts_path: str, provider_path: str) -> None:
    """Start a drain unless one is already running.

    One fixed workflow id with ALLOW_DUPLICATE gives exactly one live drain:
    the start fails while a run is open and succeeds once it closes.
    """
    from temporalio.common import WorkflowIDReusePolicy

    client = _temporal_client
    if client is None:
        log.warning("dispatcher: Temporal client not ready, skipping drain")
        return
    try:
        await client.start_workflow(
            DrainWorkflow,
            {"prompts_path": prompts_path, "provider_path": provider_path},
            id="drain-current",
            task_queue=DISPATCHER_TASK_QUEUE,
            id_reuse_policy=WorkflowIDReusePolicy.ALLOW_DUPLICATE,
            execution_timeout=WORKFLOW_EXECUTION_TIMEOUT,
        )
        log.info("dispatcher: drain started")
    except Exception as e:
        if "already started" in str(e).lower() or "already running" in str(e).lower():
            log.debug("dispatcher: drain already running")
        else:
            log.warning("dispatcher: drain start failed: %s", e)


async def _dispatcher_loop(prompts_path: str, provider_path: str) -> None:
    while True:
        try:
            await _start_drain(prompts_path, provider_path)
        except Exception:
            log.exception("dispatcher: drain start raised")
        await asyncio.sleep(DRAIN_INTERVAL_SECONDS)


async def async_main(prompts_path: str, provider_path: str, mode: str = "triggers") -> None:
    global _temporal_client, _main_event_loop

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )
    _main_event_loop = asyncio.get_running_loop()
    if mode in ("genai-ollama", "dispatcher"):
        # Only the LLM workers import openai; it adds ~50-70 MB RSS, which
        # OOM-killed the 128Mi mqtt-listener when every mode warmed it.
        log.info("OpenAI client warmed (schemas_complete=%s)", warm_openai_client())
    stop = _install_stop_signal_handlers(_main_event_loop)

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

    workers: list[Worker] = []

    def _deployment_config() -> WorkerDeploymentConfig:
        return WorkerDeploymentConfig(
            version=WorkerDeploymentVersion(
                deployment_name=DEPLOYMENT_NAME,
                build_id=BUILD_ID,
            ),
            use_worker_versioning=True,
            default_versioning_behavior=VersioningBehavior.PINNED,
        )

    # Activities GenAIWorkflow runs on its own (genai-tasks) queue.
    core_activities = [
        select_model_activity,
        update_description_activity,
        fetch_snapshot_activity,
        cleanup_cancelled_activity,
        record_result_activity,
    ]

    if mode == "triggers":
        workers = [Worker(
            _temporal_client,
            task_queue=TASK_QUEUE,
            workflows=[GenAIWorkflow],
            activities=core_activities,
            deployment_config=_deployment_config(),
            graceful_shutdown_timeout=WORKER_GRACEFUL_SHUTDOWN,
        )]
    elif mode == "ffmpeg":
        workers = [Worker(
            _temporal_client,
            task_queue=FFMPEG_TASK_QUEUE,
            activities=[transcode_into_parts_activity],
            activity_executor=ThreadPoolExecutor(max_workers=2),
            max_concurrent_activities=int(os.environ.get("TEMPORAL_MAX_FFMPEG", "2")),
            deployment_config=_deployment_config(),
            graceful_shutdown_timeout=WORKER_GRACEFUL_SHUTDOWN,
        )]
    elif mode == "genai-ollama":
        workers = [Worker(
            _temporal_client,
            task_queue=LLM_TASK_QUEUE,
            activities=[run_describe_scene, pick_keyframes_activity, crop_detection_activity],
            max_concurrent_activities=int(os.environ.get("TEMPORAL_MAX_OLLAMA_GENAI", "1")),
            deployment_config=_deployment_config(),
            graceful_shutdown_timeout=WORKER_GRACEFUL_SHUTDOWN,
        )]
    elif mode == "dispatcher":
        workers = [Worker(
            _temporal_client,
            task_queue=DISPATCHER_TASK_QUEUE,
            workflows=[DrainWorkflow],
            activities=[
                collect_scenes_activity,
                gate_status_activity,
                genai_paused_activity,
                finish_drain_activity,
                label_only_activity,
            ],
            deployment_config=_deployment_config(),
            graceful_shutdown_timeout=WORKER_GRACEFUL_SHUTDOWN,
        )]
    elif mode == "mqtt-listener":
        # No Temporal worker — MQTT client starts workflows via async_main.
        # Health HTTP handled by the mode != "dashboard" branch below.
        workers = []  # MQTT runs on its own thread, not via asyncio
    elif mode == "dashboard":
        # No Temporal worker, no MQTT. HTTP dashboard started below.
        workers = []

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
    if mode != "dashboard":  # dashboard has its own ReprocessHandler with healthz
        _health_port = int(os.environ.get("HTTP_PORT", "8080"))
        _health_host = os.environ.get("HTTP_HOST", "0.0.0.0")
        _health_server = HTTPServer((_health_host, _health_port), _HealthHandler)
        _health_thread = threading.Thread(target=_health_server.serve_forever, daemon=True)
        _health_thread.start()
        log.info("Health endpoint on http://%s:%d", _health_host, _health_port)

    # MQTT — starts workflows via Temporal client
    if mode == 'mqtt-listener':
        client_mqtt = build_mqtt_client(asyncio.get_running_loop())

    if mode == "dispatcher":
        asyncio.create_task(_dispatcher_loop(prompts_path, provider_path))
        log.info("Dispatcher loop started (drain every %ds)", DRAIN_INTERVAL_SECONDS)

    if mode == "dashboard":
        log.info("Dashboard server running, waiting for requests...")

        async def _do_reprocess(event_id: str, event: dict, model: str | None = None) -> str:
            # Cancel every running GenAIWorkflow for this event (drain-started
            # and previous -re- runs) and wait for them to close, so the new
            # run is the sole writer of the event's description and its
            # cleanup (delete of events/<event_id>/) cannot race us.
            handles = []
            try:
                async for wf in _temporal_client.list_workflows(
                    query=f'EventId = "{event_id}" and ExecutionStatus = "Running"'
                ):
                    handles.append(_temporal_client.get_workflow_handle(wf.id, run_id=wf.run_id))
            except Exception as e:
                log.warning("Failed to list running workflows for %s: %s", event_id, e)
            for handle in handles:
                try:
                    await handle.cancel()
                except Exception:
                    pass
            deadline = time.monotonic() + 60
            while handles and time.monotonic() < deadline:
                closed = True
                for h in handles:
                    try:
                        desc = await h.describe()
                        if "RUNNING" in str(desc.status):
                            closed = False
                            break
                    except Exception:
                        pass  # handle not found -> workflow closed
                if closed:
                    break
                await asyncio.sleep(2)
            camera = event.get("camera", "")
            label = event.get("label", "")
            input_data = _build_workflow_input(event, bypass_pause=True)
            if input_data is None:
                return f"Skipping {event_id} ({camera}/{label}): paused (global or per-label)"
            if model:
                input_data["model"] = model
            # Unique ID: the new run never races the cancelled run's close for
            # the same workflow ID (which previously surfaced as
            # "Workflow execution already started").
            workflow_id = f"genai-{event_id}-re-{int(time.time() * 1000)}"
            await _temporal_client.start_workflow(
                "GenAIWorkflow",
                input_data,
                id=workflow_id,
                task_queue=TASK_QUEUE,
                search_attributes=TypedSearchAttributes([
                    SearchAttributePair(_SEARCH_CAMERA, camera),
                    SearchAttributePair(_SEARCH_LABEL, label),
                    SearchAttributePair(_SEARCH_EVENT_ID, event_id),
                ]),
                memo={"event_id": event_id, "camera": camera, "label": label,
                      "duration": int(event.get("end_time", event.get("start_time", 0)) - event.get("start_time", 0)),
                      "model": model or ""})
            return f"Reprocessing {event_id} ({camera}/{label})" + (f" with {model}" if model else "")

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
                    models = _provider_models()
                    options = "".join(f'<option value="{_escape(m)}">' for m in models)
                    html = UI_HTML.replace('<datalist id="model-list"></datalist>',
                                            f'<datalist id="model-list">{options}</datalist>')
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "text/html; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(html.encode())
                elif self.path == "/api/stats":
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json; charset=utf-8")
                    self.end_headers()
                    if _stats["events_processed"] == 0:
                        saved = _s3_read_text("_state/stats.json")
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
                        saved = _s3_read_text("_state/stats.json")
                        if saved:
                            stats = json.loads(saved)
                    self.wfile.write(json.dumps({
                        "connected": stats["temporal_connected"],
                        "task_queue": TASK_QUEUE,
                        "server": os.environ.get("TEMPORAL_ADDRESS", "192.168.6.20:7233"),
                        "events_processed": stats["events_processed"],
                    }).encode())
                elif self.path.startswith("/api/events/") and self.path.endswith("/snapshot.jpg"):
                    self._proxy("image/jpeg")
                elif self.path.startswith("/api/events"):
                    self._proxy("application/json")
                elif self.path == "/api/pause":
                    paused = _s3_get("_state/paused/ollama") is not None
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"paused": paused}).encode())
                elif self.path == "/api/genai-pause":
                    paused_global = _s3_get("_state/paused/genai") is not None
                    paused_labels = {}
                    for k in _s3_list("_state/paused/genai-"):
                        paused_labels[k[len("_state/paused/genai-"):]] = True
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({
                        "global": paused_global,
                        "labels": paused_labels,
                    }).encode())
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

            def _authorized(self) -> bool:
                """Bearer-token gate for every mutating endpoint.

                503 when no token is configured, so an unconfigured deployment
                cannot be mutated at all rather than being mutated freely.
                """
                token = os.environ.get("GENAI_ADMIN_TOKEN", "")
                if not token:
                    self.send_response(503)
                    self._cors()
                    self.send_header("Content-type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"Mutations disabled: GENAI_ADMIN_TOKEN is not set")
                    return False
                header = self.headers.get("Authorization", "")
                if not hmac.compare_digest(header, f"Bearer {token}"):
                    self.send_response(401)
                    self._cors()
                    self.send_header("WWW-Authenticate", 'Bearer realm="frigate-genai"')
                    self.send_header("Content-type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"Unauthorized")
                    return False
                return True

            def do_POST(self):
                if not self._authorized():
                    return
                if self.path.startswith("/reprocess/"):
                    path_with_query = self.path.split("/reprocess/", 1)[1]
                    event_id = path_with_query.split("?", 1)[0]
                    query = urllib.parse.urlsplit(self.path).query
                    model = urllib.parse.parse_qs(query).get("model", [None])[0]
                    model = model or None  # empty string → None (auto)
                    if model is not None and model not in _provider_models():
                        self.send_response(400)
                        self._cors()
                        self.send_header("Content-type", "text/plain")
                        self.end_headers()
                        avail = ", ".join(_provider_models())
                        self.wfile.write(f"Model '{model}' not in configured list: [{avail}]".encode())
                        return
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
                        msg = asyncio.run(_do_reprocess(event_id, event, model))
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
                    existing = _s3_get("_state/paused/ollama")
                    if existing is None:
                        _s3_put("_state/paused/ollama", b"1")
                    else:
                        _s3_delete("_state/paused/ollama")

                    # Re-check paused state and send response
                    paused = _s3_get("_state/paused/ollama") is not None
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"paused": paused}).encode())
                elif self.path == "/api/genai-pause":
                    existing = _s3_get("_state/paused/genai")
                    if existing is None:
                        _s3_put("_state/paused/genai", b"1")
                    else:
                        _s3_delete("_state/paused/genai")

                    # Re-check paused state and send response
                    paused = _s3_get("_state/paused/genai") is not None
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
        http_server = ThreadingHTTPServer((http_host, http_port), ReprocessHandler)
        http_thread = threading.Thread(target=http_server.serve_forever, daemon=True)
        http_thread.start()
        log.info("HTTP reprocess endpoint on http://%s:%d", http_host, http_port)

    await _run_until_stopped(workers, stop)
    if mode == "mqtt-listener":
        client_mqtt.disconnect()
