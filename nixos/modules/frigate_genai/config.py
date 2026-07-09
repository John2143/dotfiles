"""Configuration constants and retry policies for frigate-genai."""

import os
from datetime import timedelta

from temporalio.common import RetryPolicy, SearchAttributeKey

# ── S3 bucket ──────────────────────────────────────────────────────────
_S3_BUCKET = "frigate-genai"

# ── Agent loop constants ──────────────────────────────────────────────
MAX_TURNS = 100

# ── Temporal task queues ──────────────────────────────────────────────
TASK_QUEUE = "genai-tasks"
FFMPEG_TASK_QUEUE = "genai-tasks-ffmpeg"
GEMINI_TASK_QUEUE = "genai-tasks-gemini"
OLLAMA_TASK_QUEUE = "genai-tasks-ollama"

# ── Worker deployment identity ────────────────────────────────────────
DEPLOYMENT_NAME = os.environ.get("TEMPORAL_DEPLOYMENT_NAME", "local-dev")
BUILD_ID = os.environ.get("TEMPORAL_WORKER_BUILD_ID", "local-dev")

# ── Temporal search attributes ────────────────────────────────────────
_SEARCH_CAMERA = SearchAttributeKey.for_keyword("Camera")
_SEARCH_LABEL = SearchAttributeKey.for_keyword("Label")
_SEARCH_EVENT_ID = SearchAttributeKey.for_keyword("EventId")
_SEARCH_DURATION = SearchAttributeKey.for_int("Duration")
_SEARCH_COST = SearchAttributeKey.for_int("Cost")
_SEARCH_MODEL = SearchAttributeKey.for_keyword("Model")
_SEARCH_CONFIDENCE = SearchAttributeKey.for_keyword("Confidence")
_SEARCH_TRANSCODE = SearchAttributeKey.for_bool("Transcode")
_SEARCH_TOOL_FAILURES = SearchAttributeKey.for_int("ToolFailures")

# ── Retry policies ────────────────────────────────────────────────────
_ACTIVITY_RETRY = RetryPolicy(
    maximum_attempts=3,
    initial_interval=timedelta(seconds=2),
    maximum_interval=timedelta(seconds=30),
    backoff_coefficient=2.0,
)

_GENAI_RETRY = RetryPolicy(
    maximum_attempts=20,
    initial_interval=timedelta(seconds=1),
    maximum_interval=timedelta(seconds=60),
    backoff_coefficient=2.0,
    non_retryable_error_types=["ValueError", "TypeError", "RuntimeError"],
)

_EXTRACT_RETRY = RetryPolicy(
    maximum_attempts=6,
    initial_interval=timedelta(seconds=2),
    maximum_interval=timedelta(seconds=20),
    backoff_coefficient=2.0,
)

# ── Image resolution presets ──────────────────────────────────────────
_RES_LEVELS = {
    "tiny": 320,
    "low": 640,
    "med": 960,
    "high": 1280,
    "max": None,  # special-cased: return original size
}


def _frigate_url(path: str = "") -> str:
    """Return full Frigate URL for the given API path."""
    base = os.environ.get("FRIGATE_BASE_URL", "http://localhost:5000")
    return f"{base}{path}"
