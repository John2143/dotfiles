import logging

from temporalio import activity

from frigate_genai.s3_helpers import _atomic_write, _load_state

logger = logging.getLogger(__name__)


@activity.defn(name="apply_tool_messages")
async def apply_tool_messages_activity(arg: dict) -> dict:
    """Batch-apply tool messages to state after parallel collection.

    Loads messages.json, appends all messages from all outcomes sequentially,
    and writes the updated state back.
    """
    msg_path = arg["msg_path"]
    outcomes = arg["outcomes"]
    state, _agent_dir = _load_state(msg_path)

    applied = 0
    for outcome in outcomes:
        # Handle compact's image stripping (mutates loaded state in-place)
        strip_idx = outcome.get("strip_images_before")
        if strip_idx is not None:
            for mi in range(strip_idx):
                if state["messages"][mi].get("role") == "user":
                    content = state["messages"][mi].get("content")
                    if isinstance(content, list):
                        state["messages"][mi]["content"] = [
                            p for p in content
                            if isinstance(p, dict) and p.get("type") != "image_url"
                        ]
        for msg in outcome.get("messages", []):
            state["messages"].append(msg)
            applied += 1

    _atomic_write(msg_path, state)
    return {"messages_applied": applied}
