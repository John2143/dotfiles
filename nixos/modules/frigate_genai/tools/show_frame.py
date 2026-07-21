import io as _io
import logging
from pathlib import Path
from uuid import uuid4

from PIL import Image
from temporalio import activity
from temporalio.exceptions import ApplicationError

from frigate_genai.config import _RES_LEVELS
from frigate_genai.s3_helpers import _find_tc_id, _load_state, _s3_get, _s3_put

log = logging.getLogger("frigate-genai-sidecar")


def _resolution_pixels(resolution: str, size: tuple[int, int]) -> tuple[int, int]:
    """Compute target pixel dimensions for a given resolution level."""
    w, h = size
    tw = _RES_LEVELS.get(resolution)
    if tw is None:
        return w, h
    return tw, int(tw * h / w)


def _resize_to(img: Image.Image, target_width: int) -> Image.Image:
    """Resize PIL image to target width, preserving aspect ratio."""
    if img.width <= target_width:
        return img.copy()
    ratio = target_width / img.width
    new_h = int(img.height * ratio)
    return img.resize((target_width, new_h), Image.LANCZOS)


@activity.defn(name="tool_show_frame")
async def tool_show_frame_activity(arg: dict) -> dict:
    """Load, resize, and display a frame/crop/transcode source image to the model."""
    msg_path = arg["msg_path"]
    tool_args = arg.get("args", {})
    state, agent_dir = _load_state(msg_path)
    outcome_messages = []
    frames_dir = state.get("frames_dir") or str(Path(agent_dir).parent)

    tc_id = _find_tc_id(state, "show_frame")
    source = tool_args.get("source", "snapshot://")

    # Parse resolution suffix: @low, @high, @max
    resolution = None
    base_source = source
    if "@" in source:
        base_source, res_str = source.rsplit("@", 1)
        if res_str in ("tiny", "low", "med", "high", "max"):
            resolution = res_str

    # Parse source type and frame spec
    if base_source.startswith("frame://"):
        frame_spec = base_source[len("frame://"):]
        src_type = "frame"
    elif base_source.startswith("transcode://"):
        frame_spec = base_source[len("transcode://"):]
        src_type = "transcode"
    elif base_source.startswith("crop://"):
        frame_spec = base_source[len("crop://"):]
        src_type = "crop"
    elif base_source.startswith("upscale://"):
        frame_spec = base_source[len("upscale://"):]
        src_type = "upscale"
    else:
        src_type = "snapshot"
        frame_spec = ""

    if src_type == "snapshot":
        snap_data = _s3_get(f"{frames_dir}/snapshot.jpg")
        if snap_data is not None:
            img = Image.open(_io.BytesIO(snap_data))
            fname = f"display_{uuid4().hex[:12]}.jpg"
            buf = _io.BytesIO()
            img.save(buf, "JPEG", quality=85)
            _s3_put(f"{agent_dir}/{fname}", buf.getvalue())
            ref = f"[[{fname}]]"
            outcome_messages.append({
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": ref}},
                    {"type": "text", "text": f"Detection snapshot ({img.width}x{img.height})."},
                ],
            })
        else:
            if tc_id:
                outcome_messages.append({
                    "role": "tool", "tool_call_id": tc_id,
                    "content": "No snapshot available.",
                })
    else:
        # Determine if comma-separated (N,N,N), range (N-M), or single (N)
        frames_list = []
        if "," in frame_spec:
            # Comma-separated list: frame://54,12,46,60
            parts = [x.strip() for x in frame_spec.split(",") if x.strip()]
            if parts:
                try:
                    frames_list = [int(x) for x in parts]
                except ValueError:
                    frames_list = []
        elif "-" in frame_spec:
            # Hyphenated range: frame://10-20
            try:
                f_start, f_end = int(frame_spec.split("-")[0]), int(frame_spec.split("-")[1])
                frames_list = list(range(f_start, f_end + 1))
            except (ValueError, IndexError):
                frames_list = []
        elif frame_spec:
            # Single frame: frame://54
            try:
                frames_list = [int(frame_spec)]
            except ValueError:
                frames_list = []

        # Reject negative frame numbers before transcode override
        if frames_list and any(f < 0 for f in frames_list):
            raise ApplicationError(
                f"Negative frame numbers not allowed: {source}", non_retryable=True)

        # For transcode source, frame_spec is "batch/frame_idx" or "batch/start-end"
        batch = 0
        if src_type == "transcode":
            parts = frame_spec.split("/")
            if len(parts) >= 2:
                batch = int(parts[0])
                frame_part = parts[1]
                if "," in frame_part:
                    cparts = [x.strip() for x in frame_part.split(",") if x.strip()]
                    if cparts:
                        try:
                            frames_list = [int(x) for x in cparts]
                        except ValueError:
                            frames_list = []
                elif "-" in frame_part:
                    rp = frame_part.split("-")
                    frames_list = list(range(int(rp[0]), int(rp[1]) + 1))
                else:
                    frames_list = [int(frame_part)]
            else:
                frames_list = []

        img_content = []
        if not frames_list:
            raise ApplicationError(f"Invalid frame source: {source}", non_retryable=True)
        elif len(frames_list) > 30:
            raise ApplicationError(
                f"Too many frames ({len(frames_list)}). Show at most 30 per call. Scan in batches.",
                non_retryable=True)
        else:
            # Compute default resolution from frame count
            if resolution is None:
                n_frames = len(frames_list)
                if n_frames == 1:
                    resolution = "max"
                elif n_frames <= 9:
                    resolution = "high"
                elif n_frames <= 19:
                    resolution = "med"
                else:
                    resolution = "tiny"
            img_content = []
            img_native_w = img_native_h = 0

            for fi in frames_list:
                if src_type == "frame":
                    img_data = _s3_get(f"{frames_dir}/frames/frame_{fi:03d}.jpg")
                elif src_type == "transcode":
                    img_data = _s3_get(f"{agent_dir}/transcode_{batch:03d}_{fi:03d}.jpg")
                elif src_type == "crop":
                    img_data = _s3_get(f"{agent_dir}/crop_{fi:03d}.jpg")
                elif src_type == "upscale":
                    img_data = _s3_get(f"{agent_dir}/upscale_{fi:03d}.jpg")
                else:
                    img_data = _s3_get(f"{frames_dir}/snapshot.jpg")
                if img_data is None:
                    if src_type == "transcode":
                        msg = (
                            f"Transcode batch {batch} not found. "
                            f"Call transcode(start={batch}) first to generate this batch."
                        )
                    else:
                        msg = f"Source not found: {source}"
                    if tc_id:
                        outcome_messages.append({
                            "role": "tool", "tool_call_id": tc_id, "content": msg,
                        })
                    continue
                try:
                    img = Image.open(_io.BytesIO(img_data))
                    native_w, native_h = img.size
                    if not img_native_w:
                        img_native_w, img_native_h = native_w, native_h
                    tw, th = _resolution_pixels(resolution, img.size)
                    img = _resize_to(img, tw)
                except Exception as e:
                    log.exception("Failed to load frame from source %s", source)
                    continue
                fname = f"display_{uuid4().hex[:12]}.jpg"
                buf = _io.BytesIO()
                img.save(buf, "JPEG", quality=85)
                _s3_put(f"{agent_dir}/{fname}", buf.getvalue())
                ref = f"[[{fname}]]"
                img_content.append({"type": "image_url", "image_url": {"url": ref}})
            if img_content:
                label_text = f"{len(frames_list)} frame(s) at {resolution} resolution (native {img_native_w}x{img_native_h})."
                if src_type == "transcode":
                    label_text += f" From transcode batch {batch}."
                img_content.append({"type": "text", "text": label_text})
                outcome_messages.append({"role": "user", "content": img_content})

    frames_shown = len(img_content) - 1 if img_content else 0  # subtract label text

    return {"frames_shown": frames_shown, "resolution": resolution, "messages": outcome_messages}
