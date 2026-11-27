"""Durable per-scene results and the dispatcher's small state files.

`record_result` runs before the Frigate write, so a crash between the model
call and the description update still leaves the description, the model and
the token counts on disk.
"""

import json
import logging
import time
from datetime import datetime, timezone

from temporalio import activity

from frigate_genai.s3_helpers import _s3_get, _s3_put, _s3_read_text

log = logging.getLogger("frigate-genai-sidecar")

RESULTS_PREFIX = "_state/results"
DONE_KEY = "_state/done.json"
WATERMARK_KEY = "_state/watermark.json"
SPEND_PREFIX = "_state/spend"
DONE_RETENTION_SECONDS = 8 * 24 * 3600


@activity.defn(name="record_result")
async def record_result_activity(arg: dict) -> str:
    """Persist one scene's result. Returns the S3 key written."""
    scene_id = arg["scene_id"]
    payload = {
        "scene_id": scene_id,
        "camera": arg.get("camera", ""),
        "event_ids": arg.get("event_ids") or [],
        "labels": arg.get("labels") or [],
        "priority": arg.get("priority", ""),
        "model": arg.get("model", ""),
        "description": arg.get("description", ""),
        "confidence": arg.get("confidence", ""),
        "needs_review": bool(arg.get("needs_review")),
        "retry_of": arg.get("retry_of"),
        "seconds": round(float(arg.get("seconds") or 0.0), 3),
        "prompt_tokens": int(arg.get("prompt_tokens") or 0),
        "completion_tokens": int(arg.get("completion_tokens") or 0),
        "cloud_cost_microdollars": int(arg.get("cloud_cost_microdollars") or 0),
        "recorded_at": int(time.time()),
    }
    key = f"{RESULTS_PREFIX}/{scene_id}.json"
    _s3_put(key, json.dumps(payload, sort_keys=True).encode())
    log.info("record_result: %s model=%s conf=%s", scene_id, payload["model"], payload["confidence"])
    return key


# ── Dispatcher state (pure helpers, one writer) ───────────────────────────
def load_done() -> dict[str, float]:
    """Return {event_id: end_time} of already-handled events."""
    raw = _s3_read_text(DONE_KEY)
    if not raw:
        return {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        log.warning("done index is corrupt; starting empty")
        return {}
    ids = payload.get("ids") if isinstance(payload, dict) else None
    if not isinstance(ids, dict):
        return {}
    cleaned = {}
    for key, value in ids.items():
        try:
            cleaned[str(key)] = float(value)
        except (TypeError, ValueError):
            continue
    return cleaned


def prune_done(ids: dict[str, float], now: float, retention: float = DONE_RETENTION_SECONDS) -> dict[str, float]:
    """Drop ids older than the retention window so the index stays bounded."""
    cutoff = now - retention
    return {k: v for k, v in ids.items() if v >= cutoff}


def save_done(ids: dict[str, float], now: float) -> int:
    pruned = prune_done(ids, now)
    _s3_put(DONE_KEY, json.dumps({"ids": pruned}, sort_keys=True).encode())
    return len(pruned)


def load_watermark() -> float:
    raw = _s3_read_text(WATERMARK_KEY)
    if not raw:
        return 0.0
    try:
        return float(json.loads(raw).get("end_time") or 0.0)
    except (json.JSONDecodeError, AttributeError, TypeError, ValueError):
        return 0.0


def save_watermark(end_time: float) -> None:
    _s3_put(WATERMARK_KEY, json.dumps({"end_time": end_time}).encode())


def spend_key(day: str | None = None) -> str:
    day = day or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return f"{SPEND_PREFIX}/{day}.json"


def load_spend(day: str | None = None) -> dict:
    raw = _s3_read_text(spend_key(day))
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def save_spend(counts: dict, day: str | None = None) -> None:
    payload = dict(counts)
    payload.setdefault("cloud_calls", 0)
    _s3_put(spend_key(day), json.dumps(payload, sort_keys=True).encode())


def bump(counts: dict, field: str, amount: int = 1) -> dict:
    counts[field] = int(counts.get(field) or 0) + amount
    return counts


def s3_get_json(key: str) -> dict | None:
    raw = _s3_get(key)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None
