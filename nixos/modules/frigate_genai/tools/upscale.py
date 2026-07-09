"""Upscale tool activity: 4x image upscaling via office GPU API."""

import asyncio
import io as _io
import logging
import os
import urllib.request
from pathlib import Path

from PIL import Image
from temporalio import activity

from frigate_genai.s3_helpers import (
    _find_tc_id,
    _load_state,
    _resolve_source_key,
    _s3_get,
    _s3_list,
    _s3_put,
)

log = logging.getLogger("frigate-genai-sidecar")




@activity.defn(name="tool_upscale")
async def tool_upscale_activity(arg: dict) -> dict:
    """Upscale an image 4x via the office GPU API. Shows result inline + stores as upscale://N."""
    tool_args = arg.get("args", {})
    source = tool_args.get("source", "snapshot://")
    model = tool_args.get("model", "swinir-psnr")
    if model not in ("swinir-psnr", "realesrgan"):
        model = "swinir-psnr"
    msg_path = arg["msg_path"]
    state, agent_dir = _load_state(msg_path)
    frames_dir = str(Path(agent_dir).parent)
    tc_id = _find_tc_id(state, "upscale")
    outcome_messages = []

    s3_key = _resolve_source_key(source, agent_dir, frames_dir)
    image_bytes = _s3_get(s3_key) if s3_key else None
    if image_bytes is None:
        if tc_id:
            outcome_messages.append({
                "role": "tool", "tool_call_id": tc_id,
                "content": f"Source not found or unsupported: {source}",
            })
        return {"source": source, "error": "source_not_found", "messages": outcome_messages}

    # Crop-first gate: reject inputs too large to be a "tight crop".
    max_input_px = int(os.environ.get("UPSCALE_MAX_INPUT_PX", "768"))
    src_img = Image.open(_io.BytesIO(image_bytes))
    if max(src_img.size) > max_input_px:
        if tc_id:
            outcome_messages.append({
                "role": "tool", "tool_call_id": tc_id,
                "content": (
                    f"{source} is {src_img.width}x{src_img.height} — too large to upscale "
                    f"(limit {max_input_px}px). First crop() a TIGHT region around the "
                    f"specific detail (plate, face, text), then upscale that crop://N."
                ),
            })
        return {"source": source, "error": "too_large", "messages": outcome_messages}

    # POST multipart to upscale API
    upscale_url = os.environ.get("UPSCALE_API_URL", "http://office.ts.2143.me:7870")
    boundary = "----UpscaleBoundary"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="image.jpg"\r\n'
        f"Content-Type: image/jpeg\r\n\r\n"
    ).encode() + image_bytes + f"\r\n--{boundary}\r\n".encode()
    body += (
        f'Content-Disposition: form-data; name="model"\r\n\r\n{model}\r\n'
        f"--{boundary}--\r\n"
    ).encode()
    req = urllib.request.Request(
        f"{upscale_url}/upscale", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    def _call_api() -> bytes:
        with urllib.request.urlopen(req, timeout=50) as resp:
            if resp.status != 200:
                raise RuntimeError(f"HTTP {resp.status}: {resp.read()[:200]!r}")
            return resp.read()

    result_bytes = None
    last_err = None
    for attempt, delay in ((1, 2), (2, 5), (3, 0)):
        try:
            result_bytes = await asyncio.to_thread(_call_api)
            break
        except Exception as e:
            last_err = e
            if delay:
                await asyncio.sleep(delay)

    if result_bytes is None:
        # Self-report — NEVER raise: an ActivityError would kill the whole workflow.
        log.warning("Upscale API failed for %s: %s", source, last_err)
        if tc_id:
            outcome_messages.append({
                "role": "tool", "tool_call_id": tc_id,
                "content": (
                    f"Upscale service unavailable ({last_err}). "
                    f"Continue the analysis without upscaling — use crop/@max instead."
                ),
            })
        return {"source": source, "error": "api_unavailable", "messages": outcome_messages}

    # Normalize to JPEG + get dims
    img = Image.open(_io.BytesIO(result_bytes)).convert("RGB")
    buf = _io.BytesIO()
    img.save(buf, "JPEG", quality=92)
    jpeg_bytes = buf.getvalue()

    # Store as upscale://N
    up_idx = len([k for k in _s3_list(agent_dir + "/")
                  if k.rsplit("/", 1)[-1].startswith("upscale_")]) + 1
    fname = f"upscale_{up_idx:03d}.jpg"
    _s3_put(f"{agent_dir}/{fname}", jpeg_bytes)

    # Show inline to the model
    outcome_messages.append({
        "role": "user",
        "content": [
            {"type": "image_url", "image_url": {"url": f"[[{fname}]]"}},
            {"type": "text", "text":
                f"Upscaled {source} 4x with {model} → {img.width}x{img.height}. "
                f"Stored as upscale://{up_idx}."},
        ],
    })
    return {"source": source, "model": model, "upscale_id": up_idx,
            "width": img.width, "height": img.height, "messages": outcome_messages}
