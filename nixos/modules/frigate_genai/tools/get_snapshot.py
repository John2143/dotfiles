import io as _io
import logging
from pathlib import Path

from PIL import Image
from temporalio import activity

from frigate_genai.s3_helpers import (
    _find_tc_id,
    _load_state,
    _s3_get,
    _s3_put,
)

log = logging.getLogger("frigate-genai-sidecar")


@activity.defn(name="tool_get_snapshot")
async def tool_get_snapshot_activity(arg: dict) -> dict:
    """Copy snapshot.jpg into agent_dir and append image reference to messages."""

    msg_path = arg["msg_path"]
    state, agent_dir = _load_state(msg_path)
    frames_dir = str(Path(agent_dir).parent)

    outcome_messages = []
    tc_id = _find_tc_id(state, "get_snapshot")
    snapshot_key = f"{frames_dir}/snapshot.jpg"
    snapshot_data = _s3_get(snapshot_key)
    if snapshot_data is not None:
        fname = "snapshot.jpg"
        _s3_put(f"{agent_dir}/{fname}", snapshot_data)
        img = Image.open(_io.BytesIO(snapshot_data))
        ref = f"[[{fname}]]"
        img_content = [{"type": "image_url", "image_url": {"url": ref}}]
        img_content.append({"type": "text", "text": f"Detection snapshot ({img.width}x{img.height})."})
        outcome_messages.append({"role": "user", "content": img_content})
    else:
        if tc_id:
            outcome_messages.append({
                "role": "tool", "tool_call_id": tc_id,
                "content": "No snapshot available.",
            })
    return {"snapshot_available": snapshot_data is not None, "messages": outcome_messages}
