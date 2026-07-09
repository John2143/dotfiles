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
                        "items": {
                            "type": "object",
                            "properties": {
                                "task": {"type": "string", "description": "Precise task."},
                                "image_refs": {"type": "array", "items": {"type": "string"},
                                    "description": "Images to pre-load. Max 3 per subagent."},
                                "max_turns": {"type": "integer",
                                    "description": "Turn budget (default 8, max 15)."},
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