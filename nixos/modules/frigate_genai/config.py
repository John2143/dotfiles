"""Configuration constants and retry policies for frigate-genai."""

import os
from datetime import timedelta

from temporalio.common import RetryPolicy, SearchAttributeKey

# ── S3 bucket ──────────────────────────────────────────────────────────
_S3_BUCKET = "frigate-genai"

# ── Temporal task queues ──────────────────────────────────────────────
TASK_QUEUE = "genai-tasks"
FFMPEG_TASK_QUEUE = "genai-tasks-ffmpeg"
# Queue name kept from the Ollama-only era so no manifest/CI rename is needed.
LLM_TASK_QUEUE = "genai-tasks-ollama"
# Drains get their own queue: two worker deployments must never both advertise
# workflow types on one queue, or a task can be routed to a deployment that
# does not implement it.
DISPATCHER_TASK_QUEUE = "genai-dispatcher"

# ── ffmpeg ────────────────────────────────────────────────────────────
# Unset, ffmpeg sizes its decode/filter/encode thread pools to the host CPU
# count (64 on `big`), not the pod's 4-CPU limit; each 4K HEVC decode then
# holds ~3-4 GiB and two concurrent transcodes OOM the 8 GiB ffmpeg pod.
# Matches resources.limits.cpu in argo workloads/frigate-genai/ffmpeg-workerdeployment.yaml.
FFMPEG_THREADS = "4"

# ── Models ────────────────────────────────────────────────────────────
# Default lives with the activity that selects a model; the strong one is
# needed by the backlog too, which must not import a workflow module.
STRONG_MODEL = "ollama/gemma4:26b"

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
# Admission ranks queued scenes with these. Keyword, not Int: priority is
# categorical (p0..p3) and the namespace's three custom Int attributes
# (Duration, Cost, ToolFailures) stay as they are.
_SEARCH_SCENE_PRIORITY = SearchAttributeKey.for_keyword("ScenePriority")
# Labels of a queued scene, comma-joined. Read back from the listing so
# admission can hold a paused label without an RPC per candidate; never
# queried.
_SEARCH_SCENE_LABELS = SearchAttributeKey.for_keyword("SceneLabels")

# ── Retry policies ────────────────────────────────────────────────────
_ACTIVITY_RETRY = RetryPolicy(
    maximum_attempts=3,
    initial_interval=timedelta(seconds=2),
    maximum_interval=timedelta(seconds=30),
    backoff_coefficient=2.0,
)

_GENAI_RETRY = RetryPolicy(
    maximum_attempts=10,
    initial_interval=timedelta(seconds=1),
    maximum_interval=timedelta(seconds=60),
    backoff_coefficient=2.0,
    non_retryable_error_types=["ValueError", "TypeError", "RuntimeError", "FileNotFoundError"],
)

_EXTRACT_RETRY = RetryPolicy(
    maximum_attempts=6,
    initial_interval=timedelta(seconds=2),
    maximum_interval=timedelta(seconds=20),
    backoff_coefficient=2.0,
)

# The description write is the one step whose failure loses the whole scene's
# work, so it keeps retrying for ~6 h: Frigate restarts, DB migrations and a
# network blip all fit inside that.
_DESCRIPTION_RETRY = RetryPolicy(
    maximum_attempts=24,
    initial_interval=timedelta(seconds=30),
    maximum_interval=timedelta(minutes=30),
    backoff_coefficient=2.0,
)

# Shorter than terminationGracePeriodSeconds (180) in argo
# workloads/frigate-genai/*-workerdeployment.yaml, so in-flight activities get
# 150 s to finish and cancellations are reported before SIGKILL.
WORKER_GRACEFUL_SHUTDOWN = timedelta(seconds=150)


def _frigate_url(path: str = "") -> str:
    """Return full Frigate URL for the given API path."""
    base = os.environ.get("FRIGATE_BASE_URL", "http://localhost:5000")
    return f"{base}{path}"
