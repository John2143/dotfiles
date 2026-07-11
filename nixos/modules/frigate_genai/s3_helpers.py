"""S3 abstraction layer + state management helpers for frigate-genai."""

import base64
import copy
import json
import logging
import os
import random
import time
import io as _io
from functools import lru_cache as _lru_cache
from pathlib import Path

from PIL import Image
from uuid import uuid4

from frigate_genai.config import _S3_BUCKET

log = logging.getLogger("frigate-genai-sidecar")


def _first_line(s: str) -> str:
    return s.split("\n")[0][:200]


# ── S3 abstraction layer ──────────────────────────────────────────────

@_lru_cache(maxsize=1)
def _s3_client():
    import boto3
    return boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET_KEY"],
    )


def _s3_get(key: str) -> bytes | None:
    """Download object from S3. Returns None if not found."""
    try:
        return _s3_client().get_object(Bucket=_S3_BUCKET, Key=key)["Body"].read()
    except Exception:
        return None


def _s3_put(key: str, data: bytes) -> None:
    """Upload bytes to S3."""
    _s3_client().put_object(Bucket=_S3_BUCKET, Key=key, Body=data)

def _s3_delete(key: str) -> None:
    """Delete a single object from S3."""
    _s3_client().delete_object(Bucket=_S3_BUCKET, Key=key)


def _s3_list(prefix: str) -> list[str]:
    """List keys under prefix. Returns sorted key list. Gracefully handles
    AccessDenied (some S3 backends don't allow ListObjects)."""
    import botocore as _botocore
    try:
        paginator = _s3_client().get_paginator("list_objects_v2")
        keys = []
        for page in paginator.paginate(Bucket=_S3_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                keys.append(obj["Key"])
        return sorted(keys)
    except _botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == 'AccessDenied':
            log.debug("S3 list AccessDenied for prefix %s (S3 backend lacks ListBucket permission)", prefix)
            return []
        raise


def _s3_delete_prefix(prefix: str) -> int:
    """Delete all objects under prefix. Returns count deleted."""
    keys = _s3_list(prefix)
    if keys:
        _s3_client().delete_objects(
            Bucket=_S3_BUCKET,
            Delete={"Objects": [{"Key": k} for k in keys]},
        )
    return len(keys)


def _s3_copy_key(src: str, dst: str) -> bool:
    """Copy object within S3 bucket. Returns True if successful."""
    try:
        _s3_client().copy_object(
            Bucket=_S3_BUCKET, Key=dst,
            CopySource={"Bucket": _S3_BUCKET, "Key": src},
        )
        return True
    except Exception:
        return False


def _s3_read_text(key: str) -> str | None:
    data = _s3_get(key)
    return data.decode("utf-8") if data else None


def _s3_event_prefix(event_id: str) -> str:
    return f"events/{event_id}"


def _s3_agent_prefix(event_id: str) -> str:
    return f"events/{event_id}/agent"


# ── State management ──────────────────────────────────────────────────

def _atomic_write(path: str, data: dict) -> None:
    """Write JSON to S3 (if path starts with 'events/') or disk atomically."""
    if path.startswith("events/"):
        _s3_put(path, json.dumps(data, default=str).encode())
    else:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, default=str)
        os.replace(tmp, path)


def _load_state(msg_path: str) -> tuple[dict, str]:
    """Read messages.json from S3 or local disk. Returns (state, agent_dir)."""
    if msg_path.startswith("events/"):
        data = _s3_read_text(msg_path)
        if data is None:
            raise FileNotFoundError(f"State not found at {msg_path}")
        state = json.loads(data)
    else:
        with open(msg_path) as f:
            state = json.load(f)
    return state, state["agent_dir"]


def _find_tc_id(state: dict, tool_name: str) -> str | None:
    """Find the tool_call_id in the most recent assistant message matching tool_name."""
    msgs = state.get("messages", [])
    if not msgs:
        return None
    assistant_msg = msgs[-1]
    for tc in assistant_msg.get("tool_calls", []):
        if tc.get("function", {}).get("name") == tool_name:
            return tc.get("id")
    return None


def _deserialize_messages(messages: list, agent_dir: str) -> list:
    """Convert [[filename]] refs in messages to base64 data URIs.
    Reads image bytes from S3 (if agent_dir starts with 'events/') or disk.
    Does NOT mutate — returns new list.
    """
    is_s3 = agent_dir.startswith("events/")
    result = copy.deepcopy(messages)
    for m in result:
        content = m.get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "image_url":
                    url = part.get("image_url", {}).get("url", "")
                    if url.startswith("[") and url.endswith("]]"):
                        fname = url[2:-2]
                        img_key = f"{agent_dir}/{fname}"
                        raw = _s3_get(img_key) if is_s3 else None
                        if raw is None and not is_s3:
                            p = Path(agent_dir) / fname
                            raw = p.read_bytes() if p.exists() else None
                        if raw:
                            b64 = base64.b64encode(raw).decode("ascii")
                            part["image_url"]["url"] = f"data:image/jpeg;base64,{b64}"
    return result


# ── Utilities ─────────────────────────────────────────────────────────

def load_json(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def _resolve_source_key(source: str, agent_dir: str, frames_dir: str) -> str | None:
    """Resolve a source URI to its stored S3 key. Returns None for unknown/unstored."""
    if source.startswith("frame://"):
        spec = source[len("frame://"):]
        try:
            return f"{frames_dir}/frames/frame_{int(spec):03d}.jpg"
        except ValueError:
            return None
    if source.startswith("crop://"):
        try:
            return f"{agent_dir}/crop_{int(source[len('crop://'):]):03d}.jpg"
        except ValueError:
            return None
    if source.startswith("upscale://"):
        try:
            return f"{agent_dir}/upscale_{int(source[len('upscale://'):]):03d}.jpg"
        except ValueError:
            return None
    if source.startswith("snapshot://") or source == "":
        return f"{frames_dir}/snapshot.jpg"
    return None


_stats: dict = {
    "events_processed": 0,
    "last_event": None,
    "mqtt_connected": False,
    "temporal_connected": False,
}
