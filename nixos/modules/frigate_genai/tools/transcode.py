"""Tool activity: transcode — extract frames from Frigate recordings via ffmpeg."""

import logging
import os
import subprocess
import tempfile
from pathlib import Path

from temporalio import activity

from frigate_genai.s3_helpers import _find_tc_id, _load_state, _s3_put
from frigate_genai.config import _frigate_url

log = logging.getLogger("frigate-genai-sidecar")

def _transcode_frames(
    camera: str,
    start_time: float,
    end_time: float,
    start_offset: float,
    duration: float = 1.0,
    fps: int | None = None,
) -> list[bytes]:
    """On-demand ffmpeg: extract frames at source resolution from a sub-range.

    Args:
        camera: Frigate camera name.
        start_time: Event start time (absolute epoch).
        end_time: Event end time (absolute epoch). Unused; kept for API compatibility.
        start_offset: Seconds into the clip to start extraction.
        duration: Duration to extract (default 1s, min 1s, max 10s).
        fps: Frame rate to decimate to. None = full source framerate.
    """
    import math as _math

    duration = max(1.0, min(10.0, duration))
    abs_start = start_time + start_offset
    # Pad end to ensure we capture frames that straddle the boundary
    abs_end_ceil = abs_start + duration + 1.0

    input_path = _frigate_url(
        f"/vod/{camera}"
        f"/start/{int(abs_start)}/end/{int(_math.ceil(abs_end_ceil))}"
        f"/index.m3u8"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        out_pattern = os.path.join(tmpdir, "frame_%d.jpg")
        cmd = [
            "ffmpeg",
            "-y",
            "-v", "error",
            "-ss", "0.000",
            "-i", input_path,
            "-map", "0:v",
            "-t", f"{duration:.3f}",
        ]
        if fps is not None:
            cmd += ["-vf", f"fps={fps}"]
        cmd += [
            "-q:v", "3",
            out_pattern,
        ]
        try:
            subprocess.run(cmd, capture_output=True,
                           timeout=max(30, min(300, int(duration * 15))), check=True)
        except subprocess.CalledProcessError as e:
            stderr = (e.stderr or b"").decode("utf-8", errors="replace")
            if "404 Not Found" in stderr or "Connection refused" in stderr:
                log.info("ffmpeg: recording not ready for %s", input_path)
            else:
                log.error("ffmpeg failed: camera=%s start=%.1f dur=%.1f stderr=%s",
                          camera, abs_start, duration, stderr)
            raise
        except subprocess.TimeoutExpired:
            log.error("transcode timed out: camera=%s start=%.1f dur=%.1f",
                      camera, abs_start, duration)
            raise
        frame_paths = sorted(Path(tmpdir).glob("frame_*.jpg"))
        return [p.read_bytes() for p in frame_paths]


@activity.defn(name="tool_transcode")
def tool_transcode_activity(arg: dict) -> dict:
    """Extract frames via ffmpeg (CPU-heavy, sync in thread pool), save to agent_dir."""

    msg_path = arg["msg_path"]
    tool_args = arg.get("args", {})
    event_id = arg.get("event_id", "")

    state, agent_dir = _load_state(msg_path)
    outcome_messages = []

    tc_id = _find_tc_id(state, "transcode")
    batch_start = tool_args.get("start", 0)
    max_frames = arg.get("max_frames", state.get("max_frames", 0))
    clip_duration = (arg.get("end_time", state.get("end_time", 0))
                     - arg.get("start_time", state.get("start_time", 0)))

    # Map frame index to time offset within the clip
    start_offset = clip_duration * (batch_start / max(1, max_frames))
    duration = max(1.0, min(10.0, float(tool_args.get("duration", 1.0))))

    frames = _transcode_frames(
        arg.get("camera", state.get("camera", "")),
        arg.get("start_time", state.get("start_time", 0)),
        arg.get("end_time", state.get("end_time", 0)),
        start_offset, duration, fps=None,
    )
    for i, f in enumerate(frames):
        _s3_put(f'{agent_dir}/transcode_{batch_start:03d}_{i:03d}.jpg', f)

    n_frames = len(frames)
    fps_effective = n_frames / duration if duration > 0 else 0
    end_offset = start_offset + duration
    if tc_id:
        outcome_messages.append({
            "role": "tool", "tool_call_id": tc_id,
            "content": (
                f"Transcoded {n_frames} HD frames at {fps_effective:.1f} fps "
                f"from {start_offset:.2f}s to {end_offset:.2f}s of the clip "
                f"(frame {batch_start}, {duration:.1f}s window). "
                f"Available: transcode://{batch_start}/0 through "
                f"transcode://{batch_start}/{n_frames - 1}. "
                f"You have NOT viewed these frames yet. Call show_frame() to inspect them. "
                f"Scan a range at @low first (e.g. show_frame('transcode://{batch_start}/0-5@low')) "
                f"— many low-res views cost less than one HD view. Then zoom in on specific frames "
                f"at @high or @max, and crop() for detail. "
                f"Do NOT call set_description() until you have inspected at least some frames."
            ),
        })
    log.info("tool_transcode: event=%s frames=%d [%d] dur=%.1fs fps=%.1f",
             event_id, n_frames, batch_start, duration, fps_effective)
    return {"frames_extracted": n_frames, "batch_start": batch_start,
            "batch_end": batch_start + n_frames - 1,
            "fps": round(fps_effective, 1),
            "start_offset": round(start_offset, 2),
            "end_offset": round(end_offset, 2),
            "duration_secs": duration,
            "messages": outcome_messages}
