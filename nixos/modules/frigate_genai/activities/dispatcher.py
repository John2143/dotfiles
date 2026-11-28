"""Dispatcher activities: pause flag, seat gate, event intake, drain bookkeeping.

All Frigate/Mimir/S3 I/O for the dispatcher lives here; the workflow stays
deterministic. Every gate failure mode (missing series, stale file, timeout)
is closed, by construction — an absent series cannot be mistaken for an open
gate the way a deleted object could.
"""

import asyncio
import json
import logging
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from temporalio import activity
from temporalio.common import (
    SearchAttributePair,
    TypedSearchAttributes,
    WorkflowIDReusePolicy,
)
from temporalio.exceptions import WorkflowAlreadyStartedError

from frigate_genai.activities.lifecycle import update_event_description
from frigate_genai.activities.records import (
    bump,
    load_done,
    load_last_scenes,
    load_spend,
    load_watermark,
    save_done,
    save_last_scenes,
    save_spend,
    save_watermark,
)
from frigate_genai.config import (
    DISPATCHER_TASK_QUEUE,
    _SEARCH_SCENE_LABELS,
    _SEARCH_SCENE_PRIORITY,
    _frigate_url,
)
from frigate_genai.intake import (
    HOUSEHOLD_ZONES,
    WILDLIFE_LABELS,
    Decision,
    Scene,
    classify,
    merge_scenes,
    parse_zone_polygon,
    still_there,
)
from frigate_genai.s3_helpers import _s3_get, _s3_list
from frigate_genai.workflows.pending import PendingSceneWorkflow, pending_ids

log = logging.getLogger("frigate-genai-sidecar")

MIMIR_URL = "http://192.168.6.23:8080/prometheus/api/v1/query"
OLLAMA_URL = "http://office.ts.2143.me:11434"
PAGE_LIMIT = 10000
GATE_STALE_SECONDS = 300
MIN_FREE_VRAM_MB = 12000
MIN_FREE_VRAM_MB_STRONG = 21500
MAX_LOADED_MODELS = 1
OLLAMA_TIMEOUT = 5
# An event still in progress has no end_time, so the watermark must not move
# past its start; beyond a day the hold would stall intake for no gain.
IN_PROGRESS_HOLD_MAX_SECONDS = 24 * 3600
# Old skips are already handled; rewriting days of Frigate history with
# "Skipped: ..." is noise, not information.
LABEL_MAX_AGE_SECONDS = 24 * 3600
LABEL_CHUNK = 50
LABEL_WORKERS = 8
ENQUEUE_HEARTBEAT_EVERY = 25


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
    """Page Frigate's event list by `start_time` from `after` to `before`.

    Frigate filters `after`/`before` on start_time and caps a page at
    PAGE_LIMIT, so a backlog needs several pages. `date_asc` plus a cursor on
    the page's newest start_time walks forward; the `seen` set drops the
    boundary event a following page returns again. A partial list is never
    returned: the caller advances a watermark from this, so an error must
    fail the activity instead of silently skipping events.
    """
    events: list[dict] = []
    seen: set[str] = set()
    cursor = after
    while True:
        query = urllib.parse.urlencode({
            "after": cursor, "before": before, "limit": PAGE_LIMIT,
            "in_progress": 0, "sort": "date_asc",
        })
        url = _frigate_url(f"/api/events?{query}")
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                page = json.loads(resp.read().decode())
        except Exception as e:
            raise RuntimeError(f"event fetch failed after {cursor:.0f}: {e}") from e
        if not isinstance(page, list):
            raise RuntimeError(f"event fetch after {cursor:.0f} returned {type(page).__name__}, not a list")

        added = 0
        for event in page:
            event_id = event.get("id")
            if not event_id or event_id in seen:
                continue
            seen.add(event_id)
            events.append(event)
            added += 1

        if len(page) < PAGE_LIMIT:
            break
        next_cursor = max((float(e.get("start_time") or 0) for e in page), default=cursor)
        if next_cursor <= cursor or added == 0:
            log.error("event paging stalled at %.0f", cursor)
            break
        cursor = next_cursor
    return events


def fetch_in_progress_starts() -> list[float]:
    """Start times of the events Frigate still considers in progress.

    Their `end_time` is null, which intake reads as zero duration and skips as
    flicker, after which the watermark would step over them for good. Raising
    on failure is deliberate: the watermark must not advance on a blind read.
    """
    url = _frigate_url("/api/events?" + urllib.parse.urlencode(
        {"in_progress": 1, "limit": 1000}))
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            page = json.loads(resp.read().decode())
    except Exception as e:
        raise RuntimeError(f"in-progress fetch failed: {e}") from e
    if not isinstance(page, list):
        raise RuntimeError(f"in-progress fetch returned {type(page).__name__}, not a list")
    starts = []
    for event in page:
        try:
            starts.append(float(event.get("start_time")))
        except (TypeError, ValueError):
            continue
    return starts


def fetch_zone_polygons() -> dict[str, dict[str, list[tuple[float, float]]]]:
    """Zone polygons for the cameras that have any, from /api/config.

    Frigate 0.18's event API does not report `entered_zones`, so the intake
    decides property membership from the detection box against these polygons.
    An empty result disables the zone-based skips (never the other way round).
    """
    try:
        with urllib.request.urlopen(_frigate_url("/api/config"), timeout=30) as resp:
            config = json.loads(resp.read().decode())
    except Exception as e:
        log.warning("zone fetch failed, zone-based skips disabled: %s", e)
        return {}

    polygons: dict[str, dict[str, list[tuple[float, float]]]] = {}
    for camera, household in HOUSEHOLD_ZONES.items():
        zones = ((config.get("cameras") or {}).get(camera) or {}).get("zones") or {}
        parsed = {}
        for name in household:
            entry = zones.get(name)
            if not entry:
                continue
            polygon = parse_zone_polygon(entry.get("coordinates", ""))
            if len(polygon) >= 3:
                parsed[name] = polygon
        if parsed:
            polygons[camera] = parsed
    return polygons


def priority_rank_from_labels(labels) -> int:
    """0 package/cat/wildlife, 1 person, 2 dog, 3 everything else."""
    labels = set(labels or ())
    if "package" in labels or "cat" in labels or labels & WILDLIFE_LABELS:
        return 0
    if "person" in labels:
        return 1
    if "dog" in labels:
        return 2
    return 3


def priority_rank(scene: Scene) -> int:
    return priority_rank_from_labels(scene.labels)


def priority_rank_from_dict(scene: dict) -> int:
    return priority_rank_from_labels((scene or {}).get("labels") or ())


def _order(scenes: list[Scene]) -> list[Scene]:
    """Priority 0 first, then oldest first."""
    return sorted(scenes, key=lambda s: (priority_rank(s), s.start))


async def start_pending(client, input_data: dict, rank: int) -> bool:
    """Queue one scene as a PendingSceneWorkflow.

    REJECT_DUPLICATE makes a re-collected scene (a crash before the done index
    was written) a no-op instead of a second description. Returns False when
    the scene is already queued.
    """
    pending_id, _ = pending_ids(input_data)
    labels = ",".join(sorted(input_data["scene"].get("labels") or []))
    try:
        await client.start_workflow(
            PendingSceneWorkflow,
            input_data,
            id=pending_id,
            task_queue=DISPATCHER_TASK_QUEUE,
            id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
            search_attributes=TypedSearchAttributes([
                SearchAttributePair(_SEARCH_SCENE_PRIORITY, f"p{rank}"),
                SearchAttributePair(_SEARCH_SCENE_LABELS, labels),
            ]),
        )
    except WorkflowAlreadyStartedError:
        return False
    return True


def _paused_labels() -> set[str]:
    """Labels whose scenes admission passes over (same read as the dashboard)."""
    prefix = "_state/paused/genai-"
    return {key[len(prefix):] for key in _s3_list(prefix) if len(key) > len(prefix)}


@activity.defn(name="collect_scenes")
async def collect_scenes_activity(arg: dict) -> dict:
    """Read new events, decide, merge, and queue every kept scene in Temporal.

    Queueing happens here rather than in the workflow: a burst after an outage
    is thousands of scenes, past Temporal's 2 MB payload limit if handed back.
    State is persisted only after every start, so a crash re-collects and
    REJECT_DUPLICATE dedupes. Nothing here depends on the pause flag or the
    gate: intake keeps running while they are closed, which is the point.
    """
    now = float(arg["now"])
    prompts_path = arg.get("prompts_path") or "/var/lib/frigate-genai-sidecar/prompts.json"
    provider_path = arg.get("provider_path") or "/var/lib/frigate-genai-sidecar/provider.json"

    watermark = load_watermark()
    after = watermark if watermark is not None else now
    done = load_done()
    events = fetch_events(after, now)
    zone_polygons = fetch_zone_polygons()
    log.info("collect_scenes: %d events since %.0f, zones for %d cameras",
             len(events), after, len(zone_polygons))

    fresh = [e for e in events if e.get("id") and e["id"] not in done]
    keep: list[dict] = []
    skipped: list[dict] = []
    for event in fresh:
        decision, reason = classify(event, zone_polygons)
        if decision is Decision.SKIP:
            skipped.append({
                "id": event["id"],
                "reason": reason,
                "start_time": float(event.get("start_time") or 0),
            })
            done[event["id"]] = float(event.get("end_time") or 0)
        else:
            keep.append(event)

    scenes = merge_scenes(keep, zone_polygons=zone_polygons)
    # Time order, so still_there compares each scene with the one before it on
    # the same camera. _order is applied only to the enqueue loop below.
    last = load_last_scenes()
    repeat = 0
    selected: list[Scene] = []
    for scene in scenes:
        if still_there(scene, last.get(scene.camera)):
            repeat += 1
            for event_id in scene.event_ids:
                done[event_id] = scene.end
            continue
        selected.append(scene)
        last[scene.camera] = scene

    client = activity.client()
    enqueued = 0
    duplicates = 0
    for scene in _order(selected):
        scene_dict = scene.to_dict()
        primary = scene_dict["primary"]
        input_data = {
            "event_id": primary["id"],
            "camera": scene.camera,
            "label": primary.get("label", ""),
            "start_time": primary.get("start_time"),
            "end_time": primary.get("end_time"),
            "data_box": primary.get("data_box"),
            "prompts_path": prompts_path,
            "provider_path": provider_path,
            "scene": scene_dict,
        }
        if await start_pending(client, input_data, priority_rank(scene)):
            enqueued += 1
        else:
            duplicates += 1
        for event_id in scene.event_ids:
            done[event_id] = scene.end
        if enqueued and enqueued % ENQUEUE_HEARTBEAT_EVERY == 0:
            activity.heartbeat(enqueued)
    activity.heartbeat(enqueued)

    labelled = 0
    label_failures = 0
    recent = [item for item in skipped if item["start_time"] >= now - LABEL_MAX_AGE_SECONDS]
    if recent:
        loop = asyncio.get_running_loop()
        with ThreadPoolExecutor(max_workers=LABEL_WORKERS) as pool:
            for start in range(0, len(recent), LABEL_CHUNK):
                chunk = recent[start:start + LABEL_CHUNK]
                results = await asyncio.gather(*[
                    loop.run_in_executor(
                        pool, update_event_description, item["id"], f"Skipped: {item['reason']}")
                    for item in chunk
                ], return_exceptions=True)
                for result in results:
                    if result is True:
                        labelled += 1
                    else:
                        label_failures += 1
                activity.heartbeat(len(recent) + enqueued)

    # A scene still in progress has no end_time; holding the watermark at its
    # start makes the next drain read it again instead of stepping over it.
    # Only events inside the window just read can hold: one that started before
    # `after` was never returned by the fetch (Frigate filters on start_time)
    # and never will be, so holding for it would pin the cursor at `after`
    # until the event ages out of the 24 h cap, re-reading everything each
    # drain for nothing.
    hold = [start for start in fetch_in_progress_starts()
            if after <= start and start >= now - IN_PROGRESS_HOLD_MAX_SECONDS]
    new_watermark = max(after, min([now] + hold))

    save_watermark(new_watermark)
    save_done(done, now)
    save_last_scenes(last)

    counts = load_spend()
    bump(counts, "events", len(fresh))
    bump(counts, "skipped", len(skipped))
    bump(counts, "still_there", repeat)
    bump(counts, "scenes", enqueued)
    bump(counts, "must_keep", sum(1 for s in selected if s.priority == Decision.MUST_KEEP.value))
    bump(counts, "label_failures", label_failures)
    save_spend(counts)

    return {
        "watermark": new_watermark,
        "events": len(fresh),
        "skipped": len(skipped),
        "labelled": labelled,
        "label_failures": label_failures,
        "still_there": repeat,
        "enqueued": enqueued,
        "duplicates": duplicates,
    }


@activity.defn(name="admit_scenes")
async def admit_scenes_activity(arg: dict) -> dict:
    """Signal waiting scenes to describe themselves, highest priority first.

    Admission is the only place a scene starts, so pausing (globally or per
    label) and the seat gate stop work without losing it. Priority is sorted
    client-side because SQL visibility has no ORDER BY on custom attributes.
    """
    max_in_flight = int(arg.get("max_in_flight") or 0)
    strong_ok = bool(arg.get("strong_ok"))
    client = activity.client()

    paused = _paused_labels()
    in_flight = (await client.count_workflows(
        'WorkflowType="GenAIWorkflow" AND ExecutionStatus="Running"')).count

    pending: list[tuple[int, object, str, str]] = []
    async for execution in client.list_workflows(
            'WorkflowType="PendingSceneWorkflow" AND ExecutionStatus="Running"'):
        attrs = execution.typed_search_attributes
        rank = attrs.get(_SEARCH_SCENE_PRIORITY) or ""
        labels = attrs.get(_SEARCH_SCENE_LABELS) or ""
        pending.append((int(rank[1:]) if rank[:1] == "p" and rank[1:].isdigit() else 3,
                        execution.start_time, execution.id, labels))
    pending.sort(key=lambda entry: (entry[0], entry[1]))

    held = 0
    runnable: list[str] = []
    for _, _, workflow_id, labels in pending:
        if {label for label in labels.split(",") if label} & paused:
            held += 1
            continue
        runnable.append(workflow_id)

    slots = max(0, max_in_flight - in_flight)
    admitted = 0
    for workflow_id in runnable[:slots]:
        try:
            await client.get_workflow_handle(workflow_id).signal("admit", strong_ok)
            admitted += 1
        except Exception as e:
            # A pending scene that closed a moment ago is expected: visibility
            # lags the completion by a few seconds.
            log.warning("admit signal to %s failed: %s", workflow_id, e)

    return {
        "admitted": admitted,
        "waiting": len(pending),
        "held_paused": held,
        "in_flight": in_flight,
    }


@activity.defn(name="enqueue_retry")
async def enqueue_retry_activity(input_data: dict) -> bool:
    """Queue a weak-output retry of the same scene on the stronger model.

    Through the backlog like any other scene, so the retry waits for the gate
    and re-extracts frames instead of skipping them — skipping wrote
    "Skipped: no recording" over the first description every time.
    """
    return await start_pending(
        activity.client(), input_data, priority_rank_from_dict(input_data["scene"]))


def _loaded_models() -> set[str] | None:
    """Model names ollama has resident; None when /api/ps cannot be read."""
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL}/api/ps", timeout=OLLAMA_TIMEOUT) as resp:
            payload = json.loads(resp.read().decode())
    except Exception as e:
        log.warning("ollama /api/ps failed, releasing nothing: %s", e)
        return None
    models = payload.get("models") if isinstance(payload, dict) else None
    names = set()
    for entry in models or []:
        name = (entry or {}).get("name") or (entry or {}).get("model") or ""
        if name:
            names.add(name)
    return names


@activity.defn(name="finish_drain")
async def finish_drain_activity(arg: dict) -> dict:
    """Record what this drain did, then release models from VRAM if idle.

    Releasing forces a reload on the next scene, so it happens only when no
    description is in flight and only for models actually resident: a drain
    every 5 minutes must not touch the GPU while the owner is working.
    """
    counts = load_spend()
    bump(counts, "started", int(arg.get("started") or 0))
    bump(counts, "retries", int(arg.get("retries") or 0))
    bump(counts, "gpu_seconds", int(arg.get("gpu_seconds") or 0))
    if arg.get("gate_reason"):
        counts["last_gate_reason"] = arg["gate_reason"]
    save_spend(counts)

    in_flight = (await activity.client().count_workflows(
        'WorkflowType="GenAIWorkflow" AND ExecutionStatus="Running"')).count
    if in_flight:
        log.info("finish_drain: %d scenes in flight, keeping models loaded", in_flight)
        return {"released": [], "in_flight": in_flight}

    loaded = _loaded_models()
    if loaded is None:
        return {"released": []}

    released = []
    for model in arg.get("release_models") or []:
        name = model.split("/", 1)[-1]
        if name not in loaded:
            continue
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
