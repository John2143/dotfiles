"""Frame extraction activities for frigate-genai.

Transcodes video into frames via ffmpeg and fetches snapshots from Frigate API.
"""

import logging
import math
import subprocess
import tempfile
import urllib.request
from pathlib import Path

from temporalio import activity
from temporalio.exceptions import ApplicationError

from frigate_genai.config import _frigate_url
from frigate_genai.s3_helpers import _s3_event_prefix, _s3_put
from frigate_genai.activities.genai_turn import _run_with_heartbeat

log = logging.getLogger("frigate-genai-sidecar")


def transcode_into_parts(
    camera: str,
    start_time: float,
    end_time: float,
    fps: int | None = 1,
) -> list[bytes]:
    """
    Extract JPEG frames from Frigate recording via HLS.
    If fps is set, decimate to that rate (default 1 fps for initial scan).
    If fps is None, extract all frames at source framerate.
    Full source quality — no scaling.

    Returns list of JPEG byte strings, chronologically ordered.
    """
    hls_url = _frigate_url(
        f"/vod/{camera}"
        f"/start/{int(start_time)}/end/{int(math.ceil(end_time))}"
        f"/index.m3u8"
    )

    duration = end_time - start_time
    fps_label = f"{fps}fps" if fps else "full framerate"
    log.info(
        "Extracting frames from %s (%.1fs clip, %s)",
        hls_url, duration, fps_label,
    )

    clip_timeout = max(30, min(300, int(duration * 15)))

    with tempfile.TemporaryDirectory(prefix="frigate-genai-") as tmp:
        cmd: list[str] = [
            "ffmpeg",
            "-y",
            "-loglevel", "error",
            "-i", hls_url,
            "-map", "0:v",
        ]
        if fps is not None:
            cmd += ["-vf", f"fps={fps}"]
        cmd += [
            "-q:v", "3",
            f"{tmp}/frame_%03d.jpg",
        ]
        try:
            result = subprocess.run(
                cmd, check=True, capture_output=True, text=True,
                timeout=clip_timeout,
            )
        except subprocess.CalledProcessError as e:
            stderr = (e.stderr or "").strip()
            if "404 Not Found" in stderr or "Connection refused" in stderr:
                log.debug("ffmpeg: recording not ready for %s", hls_url)
                return []  # transient — caller will retry
            else:
                log.error("ffmpeg failed for %s: %s", hls_url, stderr)
                raise  # fatal — do not retry
        except subprocess.TimeoutExpired:
            log.error("ffmpeg timed out after %ds for %s", clip_timeout, hls_url)
            raise  # fatal — do not retry

        frames = []
        for p in sorted(Path(tmp).glob("frame_*.jpg")):
            frames.append(p.read_bytes())

        if not frames:
            log.warning("No frames extracted")
        else:
            log.info("Extracted %d frames", len(frames))

        return frames


def fetch_snapshot(event_id: str) -> bytes | None:
    """Fetch the event snapshot (close-up of tracked object)."""
    url = _frigate_url(f"/api/events/{event_id}/snapshot.jpg")

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read()
    except Exception as e:
        log.warning("Failed to fetch snapshot for %s: %s", event_id, e)
        return None


@activity.defn(name="transcode_into_parts")
async def transcode_into_parts_activity(input_data: dict) -> tuple[str, int]:
    """Extract frames via ffmpeg (1 fps initial scan), upload to S3. Returns (event_prefix, frame_count)."""
    camera = input_data["camera"]
    start_time = input_data["start_time"]
    end_time = input_data["end_time"]
    event_id = input_data["event_id"]

    duration = end_time - start_time
    event_prefix = _s3_event_prefix(event_id)
    log.info(
        "Activity transcode_into_parts: event=%s camera=%s duration=%.1fs prefix=%s",
        event_id, camera, duration, event_prefix,
    )

    try:
        frames = await _run_with_heartbeat(
            transcode_into_parts, camera, start_time, end_time, 1,
        )
    except Exception:
        raise ApplicationError(
            f"Transcode failed (fatal) for {event_id}", non_retryable=True,
        )
    if not frames:
        raise ApplicationError(
            f"Recording not ready for {event_id}", non_retryable=False,
        )

    for i, frame_bytes in enumerate(frames):
        _s3_put(f"{event_prefix}/frames/frame_{i:03d}.jpg", frame_bytes)

    log.info("Extracted %d ffmpeg frames (1fps) to s3://%s/frames", len(frames), event_prefix)
    return event_prefix, len(frames)


@activity.defn(name="fetch_snapshot")
async def fetch_snapshot_activity(input_data: dict) -> str:
    """Fetch the snapshot from Frigate API, upload to S3. Returns event_prefix."""
    event_id = input_data["event_id"]
    event_prefix = _s3_event_prefix(event_id)
    log.info("event_prefix=%s", event_prefix)
    snapshot_bytes = await _run_with_heartbeat(fetch_snapshot, event_id)
    if snapshot_bytes:
        _s3_put(f"{event_prefix}/snapshot.jpg", snapshot_bytes)
    return event_prefix
