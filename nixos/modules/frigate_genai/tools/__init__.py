"""Tool registry — maps tool names to (activity_fn, task_queue pattern).

Every tool activity is registered here so AgentSessionWorkflow can dispatch
tool calls to the correct activity function and task queue.
"""

from frigate_genai.tools.find_keyframes import tool_find_keyframes_activity, tool_frame_diff_activity
from frigate_genai.tools.tag_image import tool_tag_image_activity
from frigate_genai.tools.get_snapshot import tool_get_snapshot_activity
from frigate_genai.tools.show_frame import tool_show_frame_activity
from frigate_genai.tools.transcode import tool_transcode_activity
from frigate_genai.tools.crop import tool_crop_activity
from frigate_genai.tools.compact import tool_compact_activity
from frigate_genai.tools.set_description import tool_set_description_activity
from frigate_genai.tools.upscale import tool_upscale_activity
from frigate_genai.config import TASK_QUEUE, FFMPEG_TASK_QUEUE

_TOOL_ACTIVITIES: dict[str, object] = {
    "find_keyframes": tool_find_keyframes_activity,
    "frame_diff": tool_frame_diff_activity,
    "tag_image": tool_tag_image_activity,
    "get_snapshot": tool_get_snapshot_activity,
    "show_frame": tool_show_frame_activity,
    "transcode": tool_transcode_activity,
    "crop": tool_crop_activity,
    "compact": tool_compact_activity,
    "set_description": tool_set_description_activity,
    "upscale": tool_upscale_activity,
}


def _get_tool_queue(tool_name: str, genai_queue: str) -> tuple[object, str]:
    """Return (activity_fn, task_queue) for a tool call.
    Transcode always routes to ffmpeg; everything else follows the genai model."""
    activity_fn = _TOOL_ACTIVITIES[tool_name]
    if tool_name == "transcode":
        return activity_fn, FFMPEG_TASK_QUEUE
    if tool_name == "upscale":
        return activity_fn, TASK_QUEUE
    return activity_fn, genai_queue
