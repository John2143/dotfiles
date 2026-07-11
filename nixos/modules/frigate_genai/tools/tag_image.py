"""tag_image tool — batched image tagging for per-event working memory."""

import json
import logging

try:
    from temporalio import activity
except ImportError:
    class _FakeActivity:
        @staticmethod
        def defn(**kw):
            return lambda f: f
    activity = _FakeActivity()  # type: ignore[assignment]

log = logging.getLogger("frigate-genai-sidecar")


@activity.defn(name="tool_tag_image")
async def tool_tag_image_activity(arg: dict) -> dict:
    """Tag frames/crops as useful or not-useful. Builds a working memory index.

    Tags persist at {agent_dir}/tags.json and survive compact() calls.
    """
    msg_path = arg["msg_path"]
    tool_args = arg.get("args", {})
    from frigate_genai.s3_helpers import _atomic_write, _find_tc_id, _load_state, _s3_read_text

    tags = tool_args.get("tags", [])
    if not isinstance(tags, list) or len(tags) > 20:
        tags = tags[:20] if isinstance(tags, list) else []

    state, agent_dir = _load_state(msg_path)
    tc_id = _find_tc_id(state, "tag_image")

    tags_path = f"{agent_dir.rstrip('/')}/tags.json"

    # Read existing tags
    raw = _s3_read_text(tags_path)
    existing = json.loads(raw) if raw else {}

    # Apply new tags (overwrite on duplicate source)
    for tag in tags:
        source = tag.get("source", "")
        if not source:
            continue
        existing[source] = {
            "useful": bool(tag.get("useful", False)),
            "description": tag.get("description") or "",
        }

    # Count
    useful_count = sum(1 for v in existing.values() if v.get("useful"))
    not_useful_count = sum(1 for v in existing.values() if not v.get("useful"))

    if tags:
        _atomic_write(tags_path, existing)

    return {
        "tagged": len(tags),
        "total_tagged": len(existing),
        "useful_count": useful_count,
        "not_useful_count": not_useful_count,
        "messages": [{
            "role": "tool",
            "tool_call_id": tc_id or "",
            "content": (
                f"Tagged {len(tags)} frame(s). "
                f"{useful_count} useful, {not_useful_count} not-useful "
                f"out of {len(existing)} total."
            ),
        }],
    }
