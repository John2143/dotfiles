"""Detector-crop activity: one crop of the detected object at full resolution.

The crop is appended to the keyframes so the model sees the object at a size
it can describe. It is an accuracy aid, not a dependency: every failure path
falls back to the centre 60% of the sharpest keyframe (or no crop).
"""

import io
import json
import logging
import urllib.request

from PIL import Image
from temporalio import activity

from frigate_genai.config import _frigate_url
from frigate_genai.s3_helpers import _s3_get, _s3_put

log = logging.getLogger("frigate-genai-sidecar")

CROP_QUALITY = 95
# Context crop: 0.6 of the box's width/height on every side (2.2x linear).
# Measured as the whole crop gain — a second, tighter crop adds nothing.
CROP_PADDING = 0.6
# Long side cap; the vision encoder downsamples anyway and a 4K crop would only
# inflate the prompt.
CROP_MAX_LONG_SIDE = 768
FALLBACK_FRACTION = 0.60
_LOG_BOXES = 50

_boxes_logged = 0


def fetch_event(event_id: str) -> dict | None:
    """GET the event from Frigate's API."""
    try:
        with urllib.request.urlopen(_frigate_url(f"/api/events/{event_id}"), timeout=15) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        log.warning("crop_detection: event fetch failed for %s: %s", event_id, e)
        return None


def normalise_box(box, width: int, height: int) -> tuple[float, float, float, float] | None:
    """Return (x1, y1, x2, y2) as fractions of the frame, or None.

    Frigate's event API returns pixel `[x_min, y_min, x_max, y_max]`; other
    paths hand back normalised `[x, y, w, h]`. Both shapes are disambiguated
    by range, and a 0-1000 grid (what the vision model itself answers with) is
    divided by 1000.
    """
    if not isinstance(box, (list, tuple)) or len(box) != 4:
        return None
    try:
        values = [float(v) for v in box]
    except (TypeError, ValueError):
        return None
    if any(v != v for v in values):  # NaN
        return None
    peak = max(values)

    if peak > 1.5:
        if peak <= 1000.0:
            values = [v / 1000.0 for v in values]
        else:
            values = [values[0] / width, values[1] / height, values[2] / width, values[3] / height]

    x1, y1, x2, y2 = values
    if x2 <= x1 or y2 <= y1:
        # Probably [x, y, w, h] in fractions.
        x2, y2 = x1 + x2, y1 + y2
    x1, y1, x2, y2 = min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)

    if not (0.0 <= x1 < x2 <= 1.0 and 0.0 <= y1 < y2 <= 1.0):
        # Clamp what is merely out of bounds; reject what is nonsense.
        x1, y1 = max(0.0, min(1.0, x1)), max(0.0, min(1.0, y1))
        x2, y2 = max(0.0, min(1.0, x2)), max(0.0, min(1.0, y2))
    if x2 - x1 < 0.02 or y2 - y1 < 0.02:
        return None
    return x1, y1, x2, y2


def _padded(box: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    x1, y1, x2, y2 = box
    dx, dy = (x2 - x1) * CROP_PADDING, (y2 - y1) * CROP_PADDING
    return (
        max(0.0, x1 - dx), max(0.0, y1 - dy),
        min(1.0, x2 + dx), min(1.0, y2 + dy),
    )


def centre_box() -> tuple[float, float, float, float]:
    margin = (1.0 - FALLBACK_FRACTION) / 2
    return margin, margin, 1.0 - margin, 1.0 - margin


def crop_bytes(raw: bytes, box: tuple[float, float, float, float]) -> bytes:
    image = Image.open(io.BytesIO(raw))
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")
    width, height = image.size
    x1, y1, x2, y2 = box
    px1, py1 = int(x1 * width), int(y1 * height)
    px2, py2 = max(px1 + 2, int(round(x2 * width))), max(py1 + 2, int(round(y2 * height)))
    cropped = image.crop((px1, py1, min(px2, width), min(py2, height)))
    long_side = max(cropped.size)
    if long_side > CROP_MAX_LONG_SIDE:
        scale = CROP_MAX_LONG_SIDE / long_side
        cropped = cropped.resize(
            (max(1, int(cropped.width * scale)), max(1, int(cropped.height * scale))),
            Image.LANCZOS,
        )
    out = io.BytesIO()
    cropped.save(out, format="JPEG", quality=CROP_QUALITY)
    return out.getvalue()


@activity.defn(name="crop_detection")
async def crop_detection_activity(arg: dict) -> str | None:
    """Profit: upload `events/{event_id}/crop.jpg`, return its key (or None)."""
    global _boxes_logged
    event_id = arg.get("event_id", "")
    frame_key = arg.get("frame_key")
    if not event_id or not frame_key:
        return None

    raw = _s3_get(frame_key)
    if not raw:
        log.warning("crop_detection: missing keyframe %s for %s", frame_key, event_id)
        return None

    try:
        width, height = Image.open(io.BytesIO(raw)).size
    except Exception as e:
        log.warning("crop_detection: unreadable keyframe %s: %s", frame_key, e)
        return None

    box = arg.get("data_box")
    if box is None:
        event = fetch_event(event_id)
        if event:
            box = (event.get("data") or {}).get("box")
    normalised = normalise_box(box, width, height)
    if normalised is None:
        log.info("crop_detection: unusable box %r for %s; using the centre %d%%",
                 box, event_id, int(FALLBACK_FRACTION * 100))
        normalised = centre_box()
    else:
        normalised = _padded(normalised)

    if _boxes_logged < _LOG_BOXES:
        _boxes_logged += 1
        log.info("crop_detection: event=%s frame=%dx%d raw_box=%r crop=%.3f,%.3f,%.3f,%.3f",
                 event_id, width, height, box, *normalised)

    try:
        data = crop_bytes(raw, normalised)
    except Exception as e:
        log.warning("crop_detection: crop failed for %s: %s", event_id, e)
        return None

    key = f"events/{event_id}/crop.jpg"
    _s3_put(key, data)
    return key
