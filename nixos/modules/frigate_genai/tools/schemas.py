from typing import Callable

# Tool schema registry
_TOOLS: dict[str, Callable[[], dict]] = {}

def tool_schema(func: Callable[[], dict]) -> Callable[[], dict]:
    """Register a tool schema function by name extracted from its return value."""
    schema = func()
    name = schema["function"]["name"]
    _TOOLS[name] = func
    return func

def get_tool_names() -> list[str]:
    """Return list of all registered tool names."""
    return list(_TOOLS.keys())

def get_tool_schemas(names: list[str]) -> list[dict]:
    """Reconstruct full schemas from tool names."""
    return [_TOOLS[name]() for name in names]


@tool_schema
def _tool_show_frame_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "show_frame",
            "description": (
                "Display recording frames to your vision. frame://N jumps to any keyframe instantly "
                "(free, fast). frame://N-M@res scans a range at @tiny (320px), @low (640px), "
                "@med (960px), @high (1280px), or @max (full). "
                "transcode://batch/frame shows a high-res frame from a transcode batch. "
                "crop://N re-shows a crop. snapshot:// shows the low-res bounding box preview. "
                "Cost: ~200-500 tokens per frame at @tiny. Max 30 frames per call — "
                "scan in batches."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "Frame URL: frame://N, frame://N-M@res, transcode://batch/frame, crop://N, or snapshot://. Max 30 frames per call."
                    },
                },
                "required": ["source"],
            },
        },
    }


@tool_schema
def _tool_transcode_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "transcode",
            "description": (
                "Extract HD frames at full framerate from a time window starting at frame N. "
                "Default window: 1 second. Max: 10 seconds. Each second yields 5-30 frames "
                "depending on camera FPS (actual FPS reported in tool result). "
                "SLOW (~2s). Only call after scanning with show_frame() found something "
                "worth close inspection. Frames saved as transcode://N/0 through "
                "transcode://N/M. Use show_frame() or crop() to view them."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "start": {"type": "integer", "description": "Frame index to start at (0-based)."},
                    "duration": {"type": "number", "description": "Window duration in seconds (1-10, default 1)."},
                },
                "required": ["start"],
            },
        },
    }

@tool_schema
def _tool_get_snapshot_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "get_snapshot",
            "description": (
                "The Frigate detection snapshot: a low-res bounding box preview ~3s into "
                "the clip. Good for orientation — but use frame://N to find and examine "
                "the object in the actual recording frames. Cannot be cropped. Cost: ~500 tokens."
            ),
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    }


@tool_schema
def _tool_set_description_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "set_description",
            "description": (
                "Submit your final analysis. Sets the description AND confidence level. "
                "Confidence: 'high' (certain), 'medium' (probable), 'low' (guess), "
                "'nothing_found' (searched, nothing notable), 'wrong_tag' (clearly a "
                "different object than the detected label)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "description": {"type": "string", "description": "1-3 sentence description of what you observed."},
                    "confidence": {
                        "type": "string",
                        "enum": ["high", "medium", "low", "nothing_found", "wrong_tag"],
                        "description": "How confident you are in this analysis.",
                    },
                },
                "required": ["description", "confidence"],
            },
        },
    }


@tool_schema
def _tool_compact_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "compact",
            "description": (
                "FREE — clears all old images from context instantly. "
                "Your text findings and crop:// addresses survive. "
                "Use compact when: (1) repeated crops keep coming back empty/tiny, "
                "(2) you need to free space for fresh inspection, "
                "(3) context is getting full. Call early, call often — "
                "it only costs a few tokens."
            ),
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    }

@tool_schema
def _tool_upscale_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "upscale",
            "description": (
                "Upscale an image 4x with AI super-resolution to reveal fine detail "
                "(license plates, faces, text) that is too small to read at native "
                "resolution. ONLY works on small images: you MUST first crop() a tight "
                "region around the detail, then upscale that crop://N. Full frames and "
                "large images are rejected. Workflow: show_frame @max -> crop tight -> "
                "if still unreadable -> upscale the crop. "
                "Sources: crop://N (preferred), upscale://N, frame://N, snapshot:// — "
                "all subject to the size limit. "
                "The upscaled image is shown to you and stored as upscale://N."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {"type": "string",
                        "description": "Image to upscale: snapshot://, frame://N, crop://N, upscale://N"},
                    "model": {"type": "string", "enum": ["swinir-psnr", "realesrgan"],
                        "description": "swinir-psnr = accurate/faithful detail (default); realesrgan = general enhancement, more texture invention"},
                },
                "required": ["source"],
            },
        },
    }


@tool_schema
def _tool_crop_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "crop",
            "description": (
                "Deep zoom into a region at full resolution. Coordinates 0.0-1.0 normalized "
                "(each 0.01 ≈ 38px on a 3840px-wide frame). "
                "Start WIDER than you think — you can always compact and zoom in tighter. "
                "Widen bounds if the subject is partially cut off. "
                "If 3 crops in a row return tiny or empty results, call compact() "
                "to reset and retry with better coordinates. "
                "Sources: frame://N (single), frame://N-M (range), transcode://batch/frame, "
                "transcode://batch/N-M (range), crop://N, upscale://N (single only)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {"type": "string", "description": "Frame URL: frame://N, frame://N-M, transcode://batch/frame, transcode://batch/N-M, crop://N, upscale://N"},
                    "x1": {"type": "number", "description": "Left edge 0.0-1.0"},
                    "y1": {"type": "number", "description": "Top edge 0.0-1.0"},
                    "x2": {"type": "number", "description": "Right edge 0.0-1.0"},
                    "y2": {"type": "number", "description": "Bottom edge 0.0-1.0"},
                },
                "required": ["source", "x1", "y1", "x2", "y2"],
            },
        },
    }


@tool_schema
def _tool_spawn_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "spawn",
            "description": (
                "Spawn parallel subagents to investigate different regions simultaneously. "
                "Each subagent gets its own context and runs independently. Call join() to "
                "collect results when ready. Subagents can show_frame, crop, transcode, and "
                "upscale. Max 5 subagents per spawn, max depth 2."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tasks": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 5,
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "properties": {
                                "task": {"type": "string", "description": "Precise task."},
                                "image_refs": {
                                    "type": "array",
                                    "maxItems": 3,
                                    "items": {
                                        "type": "string",
                                        "pattern": "^(crop|frame)://\\d+(@\\w+)?$",
                                    },
                                    "description": "Images to pre-load. Max 3 per subagent.",
                                },
                                "max_turns": {
                                    "type": "integer",
                                    "minimum": 1,
                                    "maximum": 15,
                                    "description": "Turn budget (default 8, max 15).",
                                },
                            },
                            "required": ["task"],
                        },
                        "description": "Tasks to spawn. Each becomes a parallel subagent.",
                    },
                },
                "required": ["tasks"],
            },
        },
    }


@tool_schema
def _tool_join_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "join",
            "description": (
                "Collect results from a spawn(). BLOCKS until ALL spawned subagents "
                "call close_subagent(). Returns formatted findings from each subagent. "
                "Join each spawn_key exactly once."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "spawn_key": {"type": "string",
                        "description": "The spawn_key returned by spawn()."},
                },
                "required": ["spawn_key"],
            },
        },
    }


@tool_schema
def _tool_close_subagent_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "close_subagent",
            "description": (
                "Terminate this subagent and return findings. Call when investigation "
                "is complete. Confidence: high=certain, medium=probable, low=unclear, "
                "nothing_found=searched thoroughly."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "findings": {"type": "string",
                        "description": "Complete findings with specific details."},
                    "confidence": {"type": "string",
                        "enum": ["high","medium","low","nothing_found"]},
                    "show_images": {"type": "array", "items": {"type": "string"},
                        "description": "Optional image refs to show parent. Max 2."},
                },
                "required": ["findings", "confidence"],
            },
        },
    }

@tool_schema
def _tool_find_keyframes_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "find_keyframes",
            "description": (
                "Find the most informative keyframes using pixel-difference "
                "analysis. Returns frame indices ranked by visual change plus "
                "the sharpest frame. Free — no API cost."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of keyframes to return (1-10, default 5).",
                        "default": 5,
                        "maximum": 10,
                    },
                },
                "required": [],
            },
        },
    }


@tool_schema
def _tool_frame_diff_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "frame_diff",
            "description": (
                "Compare two frames (0=identical, 0.04+=noticeable change). "
                "Free — no API cost."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "frame_a": {
                        "type": "integer",
                        "description": "First frame index.",
                    },
                    "frame_b": {
                        "type": "integer",
                        "description": "Second frame index; if omitted returns the change curve around frame_a.",
                    },
                },
                "required": ["frame_a"],
            },
        },
    }


@tool_schema
def _tool_tag_image_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "tag_image",
            "description": (
                "Tag frames/crops as useful or not-useful. Builds a working "
                "memory index that survives compact(). Batch up to 20 sources "
                "per call. Call after inspecting key frames — prevents "
                "re-inspecting bad frames."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tags": {
                        "type": "array",
                        "description": "List of tags to apply. Max 20.",
                        "maxItems": 20,
                        "items": {
                            "type": "object",
                            "properties": {
                                "source": {
                                    "type": "string",
                                    "description": "Frame source, e.g. frame://23, crop://3, upscale://1.",
                                },
                                "useful": {
                                    "type": "boolean",
                                    "description": "Whether this frame/crop contained useful information.",
                                },
                                "description": {
                                    "type": "string",
                                    "description": "Brief description of what was found (or not found).",
                                },
                            },
                            "required": ["source", "useful"],
                        },
                    },
                },
                "required": ["tags"],
            },
        },
    }


@tool_schema
def _tool_send_ipc_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "send_ipc",
            "description": (
                "Send a message to a parent or sibling agent. Use for findings, "
                "questions, replies, or termination signals. Messages are validated "
                "by an IPC token system; only registered agents in the same run can communicate. "
                "Set wait_for_reply=True to block until the recipient responds."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "to_token": {"type": "string",
                        "description": "Recipient IPC token (from spawn results or parent)."},
                    "kind": {"type": "string",
                        "enum": ["finding", "question", "reply", "terminate"],
                        "description": "Message kind: finding (report), question (ask), reply (answer), terminate (end)."},
                    "content": {"type": "string",
                        "description": "Message body (1-8192 bytes)."},
                    "confidence": {"type": "string",
                        "enum": ["high", "medium", "low", "nothing_found"],
                        "description": "Confidence for finding/reply kinds."},
                    "reply_to": {"type": "string",
                        "description": "Message ID being replied to (required for reply kind)."},
                    "wait_for_reply": {"type": "boolean",
                        "description": "Block until recipient sends a reply."},
                    "timeout_seconds": {"type": "integer",
                        "minimum": 1, "maximum": 300, "default": 30,
                        "description": "Max wait time for wait_for_reply."},
                },
                "required": ["to_token", "kind", "content"],
                "additionalProperties": False,
            },
        },
    }


@tool_schema
def _tool_wait_ipc_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "wait_ipc",
            "description": (
                "Wait for incoming IPC messages. Without a message_id, returns up to 20 "
                "unread messages from any registered agent. With a message_id, waits for "
                "a specific reply. Returns 'timeout: no messages received' if nothing arrives."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "message_id": {"type": "string",
                        "description": "Optional: wait for a reply to this specific message."},
                    "timeout_seconds": {"type": "integer",
                        "minimum": 1, "maximum": 300, "default": 30,
                        "description": "Max wait time."},
                },
                "additionalProperties": False,
            },
        },
    }