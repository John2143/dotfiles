"""Dispatcher activities: pause flag, seat gate, event intake, drain bookkeeping.

All Frigate/Mimir/S3 I/O for the dispatcher lives here; the workflow stays
deterministic. Every gate failure mode (missing series, stale file, timeout)
is closed, by construction — an absent series cannot be mistaken for an open
gate the way a deleted object could.
"""

import json
import logging
import time
import urllib.parse
import urllib.request

from temporalio import activity

from frigate_genai.activities.records import (
    bump,
    load_done,
    load_spend,
    load_watermark,
    save_done,
    save_spend,
    save_watermark,
)
from frigate_genai.config import _frigate_url
from frigate_genai.intake import Decision, Scene, classify, merge_scenes, still_there
from frigate_genai.s3_helpers import _s3_get

log = logging.getLogger("frigate-genai-sidecar")

MIMIR_URL = "http://192.168.6.23:8080/prometheus/api/v1/query"
OLLAMA_URL = "http://office.ts.2143.me:11434"
PAGE_LIMIT = 10000
GATE_STALE_SECONDS = 300
MIN_FREE_VRAM_MB = 12000
MIN_FREE_VRAM_MB_STRONG = 21500
MAX_LOADED_MODELS = 1
OLLAMA_TIMEOUT = 5


def _query(expr: str, timeout: float = 10.0) -> float | None:
    """Run one PromQL instant query against Mimir; None on any failure."""
    url = MIMIR_URL + "?" + urllib.parse.urlencode({"query": expr})
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode())
    except Exception as e:
        log.warning("gate query %r failed: %s", expr, e)
        return None
    if payload.get("status") != "success":
        log.warning("gate query %r returned %s", expr, payload.get("status"))
        return None
    results = (payload.get("data") or {}).get("result") or []
    if not results:
        return None
    try:
        return float(results[0]["value"][1])
    except (KeyError, IndexError, TypeError, ValueError):
        return None


def gate_status() -> dict:
    """Decide whether the workstation is free for batch inference."""
    opened = _query("frigate_genai_gate_open")
    mtime = _query('node_textfile_mtime_seconds{file=~".*frigate_genai_gate.*"}')
    free_vram = _query("frigate_genai_free_vram_mb")
    loaded = _query("frigate_genai_loaded_models")

    status = {
        "open": False,
        "free_vram_mb": int(free_vram or 0),
        "loaded_models": int(loaded or 0),
        "reason": "",
        "strong_ok": False,
    }
    if opened is None or mtime is None or free_vram is None or loaded is None:
        status["reason"] = "gate series missing"
        return status
    age = time.time() - mtime
    if age > GATE_STALE_SECONDS:
        status["reason"] = f"gate file stale ({int(age)}s)"
        return status
    if opened != 1:
        status["reason"] = "seated or overridden closed"
        return status
    if free_vram < MIN_FREE_VRAM_MB:
        status["reason"] = f"free_vram {int(free_vram)}MiB < {MIN_FREE_VRAM_MB}"
        return status
    if loaded > MAX_LOADED_MODELS:
        status["reason"] = f"{int(loaded)} models resident"
        return status
    status["open"] = True
    status["strong_ok"] = free_vram >= MIN_FREE_VRAM_MB_STRONG and loaded <= MAX_LOADED_MODELS
    return status


@activity.defn(name="gate_status")
async def gate_status_activity() -> dict:
    return gate_status()


@activity.defn(name="genai_paused")
async def genai_paused_activity() -> bool:
    return _s3_get("_state/paused/genai") is not None


def fetch_events(after: float, before: float) -> list[dict]:
    """Page Frigate's event list from `after` to `before`."""
    events: list[dict] = []
    cursor = after
    while True:
        query = urllib.parse.urlencode({
            "after": cursor, "before": before, "limit": PAGE_LIMIT,
        })
        url = _frigate_url(f"/api/events?{query}")
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                page = json.loads(resp.read().decode())
        except Exception as e:
            log.error("event fetch failed after %.0f: %s", cursor, e)
            break
        if not isinstance(page, list) or not page:
            break
        events.extend(page)
        if len(page) < PAGE_LIMIT:
            break
        cursor = max(float(e.get("end_time") or 0) for e in page)
    return events


def _order(scenes: list[Scene]) -> list[Scene]:
    """P1 package/cat/wildlife, P2 person, P3 dog, P4 everything else."""
    def rank(scene: Scene) -> tuple[int, float]:
        labels = scene.labels
        if labels & {"package"} or labels & {"cat"} or labels & {
                "bird", "deer", "horse", "bear", "cow", "fox", "raccoon"}:
            return 0, scene.start
        if "person" in labels:
            return 1, scene.start
        if "dog" in labels:
            return 2, scene.start
        return 3, scene.start
    return sorted(scenes, key=rank)


@activity.defn(name="collect_scenes")
async def collect_scenes_activity(now: float) -> dict:
    """Read new events, decide, merge, and hand back the scenes to describe.

    Also persists the watermark, the done index and the skip counters, so a
    crash after this point does not re-describe the same events.
    """
    watermark = load_watermark()
    done = load_done()
    events = fetch_events(watermark, now)
    log.info("collect_scenes: %d events since %.0f", len(events), watermark)

    fresh = [e for e in events if e.get("id") and e["id"] not in done]
    keep: list[dict] = []
    labelled: list[dict] = []
    skipped = 0
    for event in fresh:
        decision, reason = classify(event)
        if decision is Decision.SKIP:
            labelled.append({"id": event["id"], "reason": reason})
            done[event["id"]] = float(event.get("end_time") or 0)
            skipped += 1
        else:
            keep.append(event)

    scenes = merge_scenes(keep)
    last_described: Scene | None = None
    repeat = 0
    selected: list[Scene] = []
    for scene in _order(scenes):
        if still_there(scene, last_described):
            repeat += 1
            for event_id in scene.event_ids:
                done[event_id] = scene.end
            continue
        selected.append(scene)
        last_described = scene

    new_watermark = max([watermark] + [float(e.get("end_time") or 0) for e in events]) if events else now
    save_watermark(new_watermark)
    save_done(done, now)

    counts = load_spend()
    bump(counts, "events", len(fresh))
    bump(counts, "skipped", skipped)
    bump(counts, "still_there", repeat)
    bump(counts, "scenes", len(selected))
    bump(counts, "must_keep", sum(1 for s in selected if s.priority == Decision.MUST_KEEP.value))
    save_spend(counts)

    return {
        "watermark": new_watermark,
        "scenes": [s.to_dict() for s in selected],
        "labelled": labelled,
    }


@activity.defn(name="finish_drain")
async def finish_drain_activity(arg: dict) -> dict:
    """Record what this drain did and release both models from VRAM."""
    counts = load_spend()
    bump(counts, "started", int(arg.get("started") or 0))
    bump(counts, "retries", int(arg.get("retries") or 0))
    bump(counts, "gpu_seconds", int(arg.get("gpu_seconds") or 0))
    if arg.get("gate_reason"):
        counts["last_gate_reason"] = arg["gate_reason"]
    save_spend(counts)

    released = []
    for model in arg.get("release_models") or []:
        name = model.split("/", 1)[-1]
        body = json.dumps({"model": name, "keep_alive": 0}).encode()
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/generate", data=body, method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
                resp.read()
            released.append(name)
        except Exception as e:
            log.warning("keep_alive release failed for %s: %s", name, e)
    return {"released": released}
