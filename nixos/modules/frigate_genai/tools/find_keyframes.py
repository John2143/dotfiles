"""find_keyframes and frame_diff tools — deterministic pixel-difference analysis.

Algorithm: mean absolute pixel difference on mean-centered, Gaussian-blurred
grayscale 160px thumbnails, weighted 0.7 toward the data_box ROI.
Mean-centering cancels global lighting shifts; GaussianBlur(2) suppresses sensor noise.

find_keyframes: picks the N most informative frames (opinionated).
frame_diff: raw pairwise comparison data for the LLM to reason about.
"""

import io as _io_ff
import json
import logging

from PIL import Image, ImageChops, ImageFilter, ImageStat

try:
    from temporalio import activity
except ImportError:
    # No-op decorator for test environments
    class _FakeActivity:
        @staticmethod
        def defn(**kw):
            return lambda f: f
    activity = _FakeActivity()  # type: ignore[assignment]

log = logging.getLogger("frigate-genai-sidecar")


# ── pixel difference helpers ──────────────────────────────────────────────

def _prep(img: Image.Image) -> Image.Image:
    """Normalize a grayscale 160px thumbnail: Gaussian blur + mean-center to 128."""
    t = img.filter(ImageFilter.GaussianBlur(2))
    m = ImageStat.Stat(t).mean[0]
    lut = [max(0, min(255, int(i - m + 128))) for i in range(256)]
    return t.point(lut)


def _pixel_distance(a: Image.Image, b: Image.Image) -> float:
    """Mean absolute pixel difference between two prepped thumbnails (0.0-1.0)."""
    return ImageStat.Stat(ImageChops.difference(a, b)).mean[0] / 255.0


# ── shared computation ────────────────────────────────────────────────────

def _compute_differences(
    event_prefix: str,
    data_box: list[float] | None,
    max_frames: int,
) -> dict:
    """Compute frame-to-frame pixel differences for a clip.

    Handles edge cases:
    - 0 frames → empty scores
    - 1 frame  → blur_scores only, no scores
    - 2+ frames → full computation

    Saves the full curve to {agent_dir}/differences.json and returns the same dict.
    """
    agent_dir = f"{event_prefix}/agent"

    # Edge case: 0 frames — no S3 dependency needed
    if max_frames == 0:
        result: dict = {
            "scores": [],
            "blur_scores": {},
            "total_frames": 0,
            "data_box": data_box,
            "version": 1,
        }
        return result

    # S3 helpers only imported when frames exist (avoids temporalio dependency for 0-frame test)
    from frigate_genai.s3_helpers import _s3_get, _atomic_write, _s3_read_text

    # Edge case: 1 frame
    if max_frames == 1:
        # Load the single frame for blur score
        thumb = None
        try:
            raw = _s3_get(f"{event_prefix}/frames/frame_000.jpg")
            if raw:
                img = Image.open(_io_ff.BytesIO(raw))
                thumb = img.convert("L")
                tw = 160
                th = int(thumb.height * tw / thumb.width)
                thumb = thumb.resize((tw, th), Image.LANCZOS)
        except Exception:
            log.warning("Failed to load frame_000 for single-frame blur score")

        blur_scores = {}
        if thumb is not None:
            # Compute ROI if available
            try:
                tw, th = thumb.size
                if data_box and len(data_box) == 4:
                    x1 = int(data_box[0] * tw)
                    y1 = int(data_box[1] * th)
                    x2 = int((data_box[0] + data_box[2]) * tw)
                    y2 = int((data_box[1] + data_box[3]) * th)
                    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
                    half_w = (x2 - x1) * 0.75
                    half_h = (y2 - y1) * 0.75
                    x1 = max(0, min(tw - 1, int(cx - half_w)))
                    y1 = max(0, min(th - 1, int(cy - half_h)))
                    x2 = max(0, min(tw - 1, int(cx + half_w)))
                    y2 = max(0, min(th - 1, int(cy + half_h)))
                    roi = thumb.crop((x1, y1, x2, y2)) if x2 - x1 >= 4 and y2 - y1 >= 4 else thumb
                else:
                    roi = thumb
                edges = roi.filter(ImageFilter.FIND_EDGES)
                blur_scores["0"] = ImageStat.Stat(edges).var[0]
            except Exception:
                blur_scores["0"] = 0.0

        result = {
            "scores": [],
            "blur_scores": blur_scores,
            "total_frames": 1,
            "data_box": data_box,
            "version": 1,
        }
        _atomic_write(f"{agent_dir}/differences.json", result)
        return result

    # 2+ frames: full computation
    raw_thumbs = []  # raw (unblurred) thumbnails for blur scoring
    prepped = []     # prepped thumbnails for differencing
    roi_box = None

    for i in range(max_frames):
        try:
            raw = _s3_get(f"{event_prefix}/frames/frame_{i:03d}.jpg")
            if raw:
                img = Image.open(_io_ff.BytesIO(raw))
                thumb = img.convert("L")
                tw = 160
                th = int(thumb.height * tw / thumb.width)
                thumb = thumb.resize((tw, th), Image.LANCZOS)
            else:
                # Missing frame → treat as all-black
                thumb = Image.new("L", (160, 90), 0)
        except Exception:
            log.warning("Failed to load frame_%03d; using black placeholder", i)
            thumb = Image.new("L", (160, 90), 0)

        raw_thumbs.append(thumb)
        prepped.append(_prep(thumb))

        # Compute ROI box once from frame 0 dimensions
        if roi_box is None and data_box and len(data_box) == 4 and i == 0:
            try:
                tw_img, th_img = thumb.size
                x1 = int(data_box[0] * tw_img)
                y1 = int(data_box[1] * th_img)
                x2 = int((data_box[0] + data_box[2]) * tw_img)
                y2 = int((data_box[1] + data_box[3]) * th_img)
                cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
                half_w = (x2 - x1) * 0.75
                half_h = (y2 - y1) * 0.75
                rx1 = max(0, min(tw_img - 1, int(cx - half_w)))
                ry1 = max(0, min(th_img - 1, int(cy - half_h)))
                rx2 = max(0, min(tw_img - 1, int(cx + half_w)))
                ry2 = max(0, min(th_img - 1, int(cy + half_h)))
                if rx2 - rx1 >= 4 and ry2 - ry1 >= 4:
                    roi_box = (rx1, ry1, rx2, ry2)
            except Exception:
                pass

    # Compute pair scores
    scores: list[list[float]] = []
    for i in range(max_frames - 1):
        full = _pixel_distance(prepped[i], prepped[i + 1])
        if roi_box:
            roi = _pixel_distance(
                prepped[i].crop(roi_box), prepped[i + 1].crop(roi_box)
            )
            weighted = 0.3 * full + 0.7 * roi
        else:
            weighted = full
        scores.append([full, weighted])

    # Blur scores on raw (unblurred) thumbnails
    blur_scores: dict[str, float] = {}
    for i, raw_thumb in enumerate(raw_thumbs):
        try:
            crop_region = raw_thumb.crop(roi_box) if roi_box else raw_thumb
            edges = crop_region.filter(ImageFilter.FIND_EDGES)
            blur_scores[str(i)] = ImageStat.Stat(edges).var[0]
        except Exception:
            blur_scores[str(i)] = 0.0

    result = {
        "scores": scores,
        "blur_scores": blur_scores,
        "total_frames": max_frames,
        "data_box": data_box,
        "version": 1,
    }
    _atomic_write(f"{agent_dir}/differences.json", result)
    return result


# ── activities ────────────────────────────────────────────────────────────

@activity.defn(name="tool_find_keyframes")
async def tool_find_keyframes_activity(arg: dict) -> dict:
    """Find the most informative keyframes using pixel-difference analysis."""
    msg_path = arg["msg_path"]
    from frigate_genai.s3_helpers import _find_tc_id, _load_state, _s3_read_text
    event_id = arg["event_id"]
    max_frames = arg["max_frames"]
    tool_args = arg.get("args", {})

    count = min(tool_args.get("count", 5), 10)
    data_box = tool_args.get("data_box")

    state, agent_dir = _load_state(msg_path)
    event_prefix = f"events/{event_id}"

    tc_id = _find_tc_id(state, "find_keyframes")

    # Cache check
    cached_raw = _s3_read_text(f"{agent_dir}/differences.json")
    cached = json.loads(cached_raw) if cached_raw else None
    if (
        cached
        and cached.get("total_frames") == max_frames
        and cached.get("data_box") == data_box
        and cached.get("version") == 1
    ):
        diffs = cached
    else:
        diffs = _compute_differences(event_prefix, data_box, max_frames)

    scores = diffs["scores"]
    blur_scores = diffs["blur_scores"]
    total_frames = diffs["total_frames"]

    # 0 frames
    if total_frames == 0:
        return {
            "keyframes": [],
            "keyframe_scores": {},
            "blur_scores": {},
            "sharpest_frame": None,
            "crop_region": "",
            "total_frames": 0,
            "messages": [{
                "role": "tool",
                "tool_call_id": tc_id or "",
                "content": "No frames available for this event.",
            }],
        }

    # 1 frame
    if total_frames == 1:
        crop_region = _crop_region_str(data_box) if data_box else ""
        return {
            "keyframes": [0],
            "keyframe_scores": {},
            "blur_scores": blur_scores,
            "sharpest_frame": 0,
            "crop_region": crop_region,
            "total_frames": 1,
            "messages": [{
                "role": "tool",
                "tool_call_id": tc_id or "",
                "content": "Only 1 frame. Inspect it directly.",
            }],
        }

    # 2+ frames: short-circuit for motionless clips
    if len(scores) == 0 or max(s[1] for s in scores) < 0.01:
        kfs = sorted({0, total_frames - 1})
        crop_region = _crop_region_str(data_box) if data_box else ""
        # Pick sharpest among the two
        best_blur = -1.0
        sharpest = None
        for k in kfs:
            b = blur_scores.get(str(k))
            if isinstance(b, (int, float)) and b > best_blur:
                best_blur = b
                sharpest = k
        return {
            "keyframes": kfs,
            "keyframe_scores": {},
            "blur_scores": {str(k): blur_scores.get(str(k)) for k in kfs if str(k) in blur_scores},
            "sharpest_frame": sharpest,
            "crop_region": crop_region,
            "total_frames": total_frames,
            "messages": [{
                "role": "tool",
                "tool_call_id": tc_id or "",
                "content": "All frames are nearly identical — nothing moved significantly in this clip.",
            }],
        }

    # Find local maxima using weighted scores
    weighted_scores = [s[1] for s in scores]
    local_maxima: set[int] = set()
    for i in range(len(weighted_scores)):
        left = weighted_scores[i - 1] if i > 0 else -1.0
        right = weighted_scores[i + 1] if i < len(weighted_scores) - 1 else -1.0
        if weighted_scores[i] > left and weighted_scores[i] > right:
            local_maxima.add(i)

    # Keyframes are the "after" side of transitions: frame i+1 for transition i
    selected: set[int] = set()
    for lm in sorted(local_maxima):
        selected.add(lm + 1)

    # Always include first and last frames
    selected.add(0)
    if total_frames > 1:
        selected.add(total_frames - 1)

    # Fill with evenly-spaced frames if fewer than count
    if len(selected) < count and total_frames > 2:
        step = max(1, total_frames // (count - len(selected) + 1))
        for i in range(0, total_frames, step):
            if len(selected) >= count:
                break
            selected.add(i)

    # Slice to count, keeping first/last
    kfs = sorted(selected)
    if len(kfs) > count:
        # Remove from middle first, preserving 0 and last
        middle = [k for k in kfs if k not in (0, total_frames - 1)]
        middle_sorted = sorted(middle, key=lambda k: -weighted_scores[k - 1] if k > 0 and k - 1 < len(weighted_scores) else 0)
        keep = count - 2  # for first + last
        keep_middle = set(middle_sorted[:keep])
        kfs = sorted([0] + [k for k in kfs if k == 0 or k == total_frames - 1 or k in keep_middle])

    # Build keyframe scores (weighted score for transition leading to each kf)
    keyframe_scores: dict[str, float] = {}
    for kf in kfs:
        if kf > 0 and kf - 1 < len(scores):
            keyframe_scores[str(kf)] = round(scores[kf - 1][1], 4)

    # Sharpest frame among selected keyframes
    best_blur = -1.0
    sharpest_frame = None
    for kf in kfs:
        b = blur_scores.get(str(kf))
        if isinstance(b, (int, float)) and b > best_blur:
            best_blur = b
            sharpest_frame = kf

    # Filter blur_scores to selected keyframes only
    result_blur_scores = {str(k): blur_scores.get(str(k)) for k in kfs if str(k) in blur_scores}

    crop_region = _crop_region_str(data_box) if data_box else ""

    # Concise message
    top_entries = sorted(keyframe_scores.items(), key=lambda x: -x[1])[:3]
    top_str = ", ".join(f"#{f}({s:.3f})" for f, s in top_entries)
    sharp_str = ""
    if sharpest_frame is not None:
        b = blur_scores.get(str(sharpest_frame))
        sharp_str = f" Sharpest: #{sharpest_frame} (edge={b:.0f})" if isinstance(b, (int, float)) else ""
    crop_hint = f" Crop hint: {crop_region}" if crop_region else ""

    content = (
        f"{len(kfs)} keyframes from {total_frames} frames. "
        f"First=0, last={total_frames - 1}. "
        f"Top changes: {top_str}.{sharp_str}.{crop_hint}"
    )

    return {
        "keyframes": kfs,
        "keyframe_scores": keyframe_scores,
        "blur_scores": result_blur_scores,
        "sharpest_frame": sharpest_frame,
        "crop_region": crop_region,
        "total_frames": total_frames,
        "messages": [{
            "role": "tool",
            "tool_call_id": tc_id or "",
            "content": content,
        }],
    }


@activity.defn(name="tool_frame_diff")
async def tool_frame_diff_activity(arg: dict) -> dict:
    """Compare two frames using pixel-difference analysis."""
    msg_path = arg["msg_path"]
    from frigate_genai.s3_helpers import _find_tc_id, _load_state, _s3_read_text, _s3_get, _atomic_write
    event_id = arg["event_id"]
    max_frames = arg.get("max_frames", 0)
    tool_args = arg.get("args", {})

    frame_a = tool_args["frame_a"]
    frame_b = tool_args.get("frame_b")
    data_box = tool_args.get("data_box")

    state, agent_dir = _load_state(msg_path)
    event_prefix = f"events/{event_id}"

    tc_id = _find_tc_id(state, "frame_diff")

    # Guard: range check
    if frame_a < 0 or (max_frames > 0 and frame_a >= max_frames):
        return {
            "frame_a": frame_a, "frame_b": frame_b,
            "distance": None, "full_distance": None, "roi_distance": None,
            "interpretation": f"Frame {frame_a} out of range (0-{max_frames - 1}).",
            "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                           "content": f"Error: frame {frame_a} out of range (0-{max_frames - 1})."}],
        }
    if frame_b is not None and (frame_b < 0 or (max_frames > 0 and frame_b >= max_frames)):
        return {
            "frame_a": frame_a, "frame_b": frame_b,
            "distance": None, "full_distance": None, "roi_distance": None,
            "interpretation": f"Frame {frame_b} out of range (0-{max_frames - 1}).",
            "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                           "content": f"Error: frame {frame_b} out of range (0-{max_frames - 1})."}],
        }

    # Load or compute differences
    cached_raw = _s3_read_text(f"{agent_dir}/differences.json")
    cached = json.loads(cached_raw) if cached_raw else None
    if cached is None:
        if max_frames == 0:
            return {
                "frame_a": frame_a, "frame_b": frame_b,
                "distance": None, "full_distance": None, "roi_distance": None,
                "interpretation": "No frames available.",
                "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                               "content": "Error: No frames available."}],
            }
        cached = _compute_differences(event_prefix, data_box, max_frames)

    scores = cached["scores"]

    if frame_b is not None:
        # Both-frames mode
        if abs(frame_a - frame_b) == 1:
            # Adjacent: serve from cache
            idx = min(frame_a, frame_b)
            if idx < len(scores):
                full, weighted = scores[idx]
                roi_d = (weighted - 0.3 * full) / 0.7 if abs(weighted - full) > 1e-9 else None
            else:
                full, weighted = 0.0, 0.0
                roi_d = None
        else:
            # Non-adjacent: load both frames and compute directly
            try:
                raw_a = _s3_get(f"{event_prefix}/frames/frame_{frame_a:03d}.jpg")
                raw_b = _s3_get(f"{event_prefix}/frames/frame_{frame_b:03d}.jpg")
                if not raw_a:
                    return {
                        "frame_a": frame_a, "frame_b": frame_b,
                        "distance": None,
                        "interpretation": f"Frame {frame_a} not found.",
                        "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                                       "content": f"Error: Frame {frame_a} not found."}],
                    }
                if not raw_b:
                    return {
                        "frame_a": frame_a, "frame_b": frame_b,
                        "distance": None,
                        "interpretation": f"Frame {frame_b} not found.",
                        "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                                       "content": f"Error: Frame {frame_b} not found."}],
                    }

                img_a = Image.open(_io_ff.BytesIO(raw_a))
                img_b = Image.open(_io_ff.BytesIO(raw_b))
                tw = 160
                thumb_a = img_a.convert("L").resize(
                    (tw, int(img_a.height * tw / img_a.width)), Image.LANCZOS
                )
                thumb_b = img_b.convert("L").resize(
                    (tw, int(img_b.height * tw / img_b.width)), Image.LANCZOS
                )

                prep_a = _prep(thumb_a)
                prep_b = _prep(thumb_b)

                full = _pixel_distance(prep_a, prep_b)

                # ROI from arg data_box (may differ from cached)
                roi_d = None
                weighted = full
                if data_box and len(data_box) == 4:
                    tw_img, th_img = thumb_a.size
                    x1 = int(data_box[0] * tw_img)
                    y1 = int(data_box[1] * th_img)
                    x2 = int((data_box[0] + data_box[2]) * tw_img)
                    y2 = int((data_box[1] + data_box[3]) * th_img)
                    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
                    half_w = (x2 - x1) * 0.75
                    half_h = (y2 - y1) * 0.75
                    rx1 = max(0, min(tw_img - 1, int(cx - half_w)))
                    ry1 = max(0, min(th_img - 1, int(cy - half_h)))
                    rx2 = max(0, min(tw_img - 1, int(cx + half_w)))
                    ry2 = max(0, min(th_img - 1, int(cy + half_h)))
                    if rx2 - rx1 >= 4 and ry2 - ry1 >= 4:
                        roi_d = _pixel_distance(
                            prep_a.crop((rx1, ry1, rx2, ry2)),
                            prep_b.crop((rx1, ry1, rx2, ry2)),
                        )
                        weighted = 0.3 * full + 0.7 * roi_d
            except Exception as e:
                return {
                    "frame_a": frame_a, "frame_b": frame_b,
                    "distance": None,
                    "interpretation": f"Failed to compare frames: {e}",
                    "messages": [{"role": "tool", "tool_call_id": tc_id or "",
                                   "content": f"Error comparing frames {frame_a} and {frame_b}: {e}"}],
                }

    else:
        # Neighborhood mode: return weighted scores around frame_a
        lo = max(0, frame_a - 5)
        hi = min(len(scores) - 1, frame_a + 5)
        neighbors = []
        for i in range(lo, hi + 1):
            w = scores[i][1]
            neighbors.append(f"{i}->{i + 1}: {w:.3f}")
        content = "Neighborhood:\n" + "\n".join(neighbors)
        return {
            "frame_a": frame_a, "frame_b": None,
            "distance": None, "full_distance": None, "roi_distance": None,
            "neighbors": neighbors,
            "messages": [{
                "role": "tool",
                "tool_call_id": tc_id or "",
                "content": content,
            }],
        }

    # Percentile rank
    percentile_str = ""
    if scores and weighted > 0:
        strictly_less = sum(1 for s in scores if s[1] < weighted)
        pct = round(strictly_less / len(scores) * 100)
        percentile_str = f" ({pct}th percentile for this clip)"

    # Interpretation
    interp = _interpret_distance(weighted)

    content = f"{interp} — {weighted:.3f} distance{percentile_str}."

    return {
        "frame_a": frame_a,
        "frame_b": frame_b,
        "distance": round(weighted, 4),
        "full_distance": round(full, 4),
        "roi_distance": round(roi_d, 4) if roi_d is not None else None,
        "interpretation": content,
        "messages": [{
            "role": "tool",
            "tool_call_id": tc_id or "",
            "content": content,
        }],
    }


# ── helpers ───────────────────────────────────────────────────────────────

def _crop_region_str(data_box: list[float]) -> str:
    """Format data_box as a crop coordinate string."""
    return (
        f"x1={data_box[0]:.2f} y1={data_box[1]:.2f} "
        f"x2={data_box[0] + data_box[2]:.2f} y2={data_box[1] + data_box[3]:.2f}"
    )


def _interpret_distance(d: float) -> str:
    """Human-readable interpretation of a pixel-difference score."""
    if d < 0.005:
        return "Near-identical"
    if d < 0.015:
        return "Similar"
    if d < 0.04:
        return "Noticeable change"
    if d < 0.10:
        return "Significant change"
    return "Major scene change"
