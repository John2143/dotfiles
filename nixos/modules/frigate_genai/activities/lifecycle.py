"""Lifecycle activities: description updates and per-event cleanup."""

import json
import logging
import urllib.request

from temporalio import activity

from frigate_genai.activities.llm import _run_with_heartbeat
from frigate_genai.config import _frigate_url
from frigate_genai.s3_helpers import _s3_delete_prefix

log = logging.getLogger(__name__)


def update_event_description(event_id: str, description: str) -> bool:
    """Write description back to Frigate's event."""
    url = _frigate_url(f"/api/events/{event_id}/description")
    payload = json.dumps({"description": description}).encode()
    try:
        req = urllib.request.Request(
            url, data=payload, method="POST",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status == 200
    except Exception as e:
        log.error("Failed to update event %s: %s", event_id, e)
        return False


@activity.defn(name="update_description")
async def update_description_activity(event_id: str, description: str) -> bool:
    """Update Frigate event description via API."""
    log.info("Activity update_description: event=%s", event_id)
    ok = await _run_with_heartbeat(update_event_description, event_id, description)
    if not ok:
        raise RuntimeError(f"Failed to update description for event {event_id}")
    return True


@activity.defn(name="label_only")
async def label_only_activity(event_id: str, reason: str) -> bool:
    """Mark a skipped event with its one-line reason instead of describing it."""
    text = f"Skipped: {reason}"
    log.info("label_only: event=%s reason=%s", event_id, reason)
    ok = await _run_with_heartbeat(update_event_description, event_id, text)
    if not ok:
        raise RuntimeError(f"Failed to label event {event_id}")
    return True


@activity.defn(name="cleanup_cancelled")
async def cleanup_cancelled_activity(input_data: dict, notify_cancelled: bool = False) -> None:
    """Delete this event's frames and crop from S3, and post a notice when the
    workflow was cancelled rather than completed."""
    event_id = input_data["event_id"]
    deleted = _s3_delete_prefix(f"events/{event_id}/")
    log.info("Cleanup: event=%s removed %d objects", event_id, deleted)
    if notify_cancelled:
        await _run_with_heartbeat(update_event_description, event_id, "Cancelled")
