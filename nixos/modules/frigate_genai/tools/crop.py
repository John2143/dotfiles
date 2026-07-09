import io as _io
import logging

from PIL import Image
from temporalio import activity
from temporalio.exceptions import ApplicationError

from frigate_genai.s3_helpers import (
    _find_tc_id,
    _load_state,
    _s3_get,
    _s3_list,
    _s3_put,
)

log = logging.getLogger("frigate-genai-sidecar")


@activity.defn(name="tool_crop")
async def tool_crop_activity(arg: dict) -> dict:
    """Crop a region from a source image and save the result to agent_dir."""

    msg_path = arg["msg_path"]
    tool_args = arg.get("args", {})
    state, agent_dir = _load_state(msg_path)
    event_prefix = agent_dir.rsplit("/", 1)[0]

    tc_id = _find_tc_id(state, "crop")
    source = tool_args.get("source", "")
    outcome_messages = []

    x1 = max(0.0, min(1.0, float(tool_args.get("x1", 0))))
    y1 = max(0.0, min(1.0, float(tool_args.get("y1", 0))))
    x2 = max(0.0, min(1.0, float(tool_args.get("x2", 1))))
    y2 = max(0.0, min(1.0, float(tool_args.get("y2", 1))))

    if x1 >= x2 or y1 >= y2:
        raise ApplicationError(
            f"Invalid crop region ({x1},{y1})-({x2},{y2})", non_retryable=True)
    base_source = source
    if "@" in source:
        base_source = source.rsplit("@", 1)[0]

    # snapshot:// rejected early
    if base_source.startswith("snapshot://"):
        raise ApplicationError(
            "Cannot crop snapshot://. The snapshot is a low-res bounding box "
            "preview. Use frame://N to find the object in the recording frames.",
            non_retryable=True)


    # Resolve source list: each entry is (src_type, *args)
    source_list = []
    if base_source.startswith("frame://"):
        spec = base_source[len("frame://"):]
        if "-" in spec:
            rp = spec.split("-")
            source_list = [("frame", i) for i in range(int(rp[0]), int(rp[1]) + 1)]
        else:
            source_list = [("frame", int(spec))]
    elif base_source.startswith("transcode://"):
        parts = base_source[len("transcode://"):].split("/")
        batch = int(parts[0])
        frame_part = parts[1] if len(parts) > 1 else "0"
        if "-" in frame_part:
            rp = frame_part.split("-")
            source_list = [("transcode", batch, i) for i in range(int(rp[0]), int(rp[1]) + 1)]
        else:
            source_list = [("transcode", batch, int(frame_part))]
    elif base_source.startswith("crop://"):
        idx = int(base_source[len("crop://"):])
        source_list = [("crop", idx)]
    elif base_source.startswith("upscale://"):
        idx = int(base_source[len("upscale://"):])
        source_list = [("upscale", idx)]

    # Crop each source, collect results
    crop_results = []
    for entry in source_list:
        img_key = None
        if entry[0] == "frame":
            img_key = f"{event_prefix}/frames/frame_{entry[1]:03d}.jpg"
        elif entry[0] == "transcode":
            img_key = f"{agent_dir}/transcode_{entry[1]:03d}_{entry[2]:03d}.jpg"
        elif entry[0] == "crop":
            img_key = f"{agent_dir}/crop_{entry[1]:03d}.jpg"
        elif entry[0] == "upscale":
            img_key = f"{agent_dir}/upscale_{entry[1]:03d}.jpg"

        if not img_key:
            continue
        img_bytes = _s3_get(img_key)
        if img_bytes is None:
            continue
        try:
            img = Image.open(_io.BytesIO(img_bytes))
            w, h = img.size
            crop_box = (int(x1 * w), int(y1 * h), int(x2 * w), int(y2 * h))
            cropped = img.crop(crop_box)
            existing = _s3_list(f"{agent_dir}/crop_")
            crop_id = len(existing) + 1
            fname = f"crop_{crop_id:03d}.jpg"
            buf = _io.BytesIO()
            cropped.save(buf, "JPEG", quality=95)
            _s3_put(f"{agent_dir}/{fname}", buf.getvalue())
            crop_results.append((crop_id, fname, cropped.width, cropped.height))
        except Exception as e:
            log.exception("Failed to crop source %r", entry)

    if crop_results:
        crop_ids = [cid for cid, _, _, _ in crop_results]
        content_parts = []
        for _, fname, _, _ in crop_results:
            content_parts.append({"type": "image_url", "image_url": {"url": f"[[{fname}]]"}})
        if len(crop_results) == 1:
            _, _, cw, ch = crop_results[0]
            size_hint = ""
            if cw < 300 and ch < 300:
                size_hint = " (tiny — consider wider bounds or compact)"
            label = (
                f"Cropped ({x1:.2f},{y1:.2f})-({x2:.2f},{y2:.2f}) "
                f"→ {cw}x{ch} from {base_source}. "
                f"Stored as crop://{crop_ids[0]}." + size_hint
            )
        else:
            all_tiny = all(cw < 300 and ch < 300 for _, _, cw, ch in crop_results)
            size_hint = " (tiny — consider wider bounds or compact)" if all_tiny else ""
            label = (
                f"Cropped ({x1:.2f},{y1:.2f})-({x2:.2f},{y2:.2f}) "
                f"from {base_source} ({len(crop_results)} frames). "
                f"Stored as crop://{crop_ids[0]} through crop://{crop_ids[-1]}." + size_hint
            )
        content_parts.append({"type": "text", "text": label})
        outcome_messages.append({"role": "user", "content": content_parts})
    else:
        if tc_id:
            outcome_messages.append({
                "role": "tool", "tool_call_id": tc_id,
                "content": f"No sources could be cropped from: {source}",
            })

    return {"messages": outcome_messages,
            "crop_ids": [cid for cid, _, _, _ in crop_results] if crop_results else [],
            "source": source, "crop_region": [x1, y1, x2, y2], "count": len(crop_results)}
