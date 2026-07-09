"""Lifecycle activities: agent log saving, summarization, description updates, cleanup."""

import json
import logging
import urllib.request

from temporalio import activity

from frigate_genai.activities.genai_turn import _resolve_provider, _run_with_heartbeat
from frigate_genai.config import _frigate_url
from frigate_genai.s3_helpers import (
    _s3_agent_prefix,
    _s3_copy_key,
    _s3_delete_prefix,
    _s3_list,
    _s3_put,
    _s3_read_text,
)

log = logging.getLogger(__name__)


def load_json(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


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


@activity.defn(name="save_agent_log")
async def save_agent_log_activity(log_arg: dict) -> None:
    """Write agent trace log to S3. Activity to avoid sandbox restrictions."""
    event_id = log_arg["event_id"]
    trace_text = log_arg["trace_text"]
    try:
        _s3_put(f"events/{event_id}/agent/trace.txt", trace_text.encode())
        log.info("Agent trace saved: s3://events/%s/agent/trace.txt", event_id)
    except Exception as e:
        log.warning("Failed to write agent log: %s", e)


@activity.defn(name="summarize_agent")
async def summarize_agent_activity(stats: dict) -> str | None:
    """Summarize agentic strategy. Separate activity for Temporal audit trail."""
    from openai import OpenAI

    event_id = stats["event_id"]
    model = stats["model"]
    provider_path = stats["provider_path"]

    try:
        provider_cfg = load_json(provider_path)
    except (OSError, json.JSONDecodeError) as e:
        log.error("Failed to load provider config in summarize_agent: %s", e)
        raise RuntimeError(f"Failed to load config: {e}") from e

    client, model_name = _resolve_provider(provider_cfg, model, timeout=30.0)

    prompt = (
        f"Answer in one sentence: model {model}, "
        f"viewed {stats['turns_low']} low-res + {stats['turns_high']} high-res + "
        f"{stats.get('turns_max', 0)} max-res + {stats.get('turns_transcode', 0)} transcoded "
        f"frames in {stats['turns']} turns. "
        "What the agent found, what search pattern it used."
    )

    def _call_summarize() -> str | None:
        response = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.0,
        )
        return response.choices[0].message.content

    try:
        summary = await _run_with_heartbeat(_call_summarize)
        if summary:
            summary = f"Agent: {summary}"
            log.info("Agent summary for %s: %s", event_id, summary)
            try:
                agent_prefix = _s3_agent_prefix(event_id)
                _s3_put(f"{agent_prefix}/summary.txt", summary.encode())
                trace_key = f"{agent_prefix}/trace.txt"
                existing = _s3_read_text(trace_key)
                if existing is not None:
                    _s3_put(trace_key, (existing + f"\n\n{summary}").encode())
            except Exception as e:
                pass
            return summary
    except Exception as e:
        log.warning("Agent summary call failed for %s: %s", event_id, e)
    return None


@activity.defn(name="update_description")
async def update_description_activity(event_id: str, description: str) -> bool:
    """Update Frigate event description via API."""
    log.info("Activity update_description: event=%s", event_id)
    ok = await _run_with_heartbeat(update_event_description, event_id, description)
    if not ok:
        raise RuntimeError(f"Failed to update description for event {event_id}")
    return True


@activity.defn(name="cleanup_cancelled")
async def cleanup_cancelled_activity(input_data: dict, notify_cancelled: bool = False) -> None:
    """Clean up persisted data: archive agent artifacts to history/ prefix,
    delete everything from events/ prefix, post notice to Frigate."""
    event_id = input_data["event_id"]
    log.info("Cleanup: event=%s", event_id)

    # Archive agent artifacts to history/ before deleting
    src_prefix = f"events/{event_id}/agent/"
    dst_prefix = f"history/{event_id}/agent/"
    archived = 0
    for key in _s3_list(src_prefix):
        dst = dst_prefix + key[len(src_prefix):]
        if _s3_copy_key(key, dst):
            archived += 1
    log.info("Archived %d agent artifacts for event=%s", archived, event_id)

    # Remove all persisted data for this event from S3
    deleted = _s3_delete_prefix(f"events/{event_id}/")
    log.info("Removed %d objects for event=%s", deleted, event_id)
    if notify_cancelled:
        await _run_with_heartbeat(update_event_description, event_id, "Cancelled")
