#!/usr/bin/env python3
"""Temporal Job Analyzer — batch analysis of GenAIWorkflow executions.

Queries the Temporal Web UI API (unauthenticated) to collect the latest N
GenAIWorkflow executions, fetches their full histories, categorizes failures,
and writes CSV + JSON summary output.

Dependencies: stdlib only (urllib + asyncio). No pip install required.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import csv
import gzip
import json
import re
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any


# ── Constants ──────────────────────────────────────────────────────────

TEMPORAL_BASE = "https://temporal.ts.2143.me"
API_BASE = f"{TEMPORAL_BASE}/api/v1/namespaces/default"
LIST_URL = f"{API_BASE}/workflows"
DEFAULT_LIMIT = 2000
PAGE_SIZE = 100
FETCH_CONCURRENCY = 5
PAGE_DELAY = 0.2  # seconds between pages
MAX_HISTORY_BYTES = 50 * 1024 * 1024  # 50MB
CHECKPOINT_STALE_SECONDS = 3600  # 1 hour


# ── Payload decoding ───────────────────────────────────────────────────

def decode_payload(obj: Any) -> Any:
    """Recursively decode Temporal base64-encoded payloads in-place."""
    if isinstance(obj, dict):
        if "metadata" in obj and "data" in obj:
            # It's a Temporal Payload
            encoding_b64 = obj.get("metadata", {}).get("encoding", "")
            try:
                encoding = base64.b64decode(encoding_b64).decode("utf-8")
            except Exception:
                encoding = ""
            raw_data = obj.get("data", "")
            if encoding == "json/plain" and raw_data:
                try:
                    decoded = json.loads(
                        base64.b64decode(raw_data).decode("utf-8")
                    )
                    return decode_payload(decoded)
                except Exception:
                    return raw_data
            elif raw_data:
                try:
                    return base64.b64decode(raw_data).decode("utf-8")
                except Exception:
                    return raw_data
            return obj
        # Recurse into dict
        return {k: decode_payload(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [decode_payload(item) for item in obj]
    return obj


def decode_search_attributes(attributes: dict | None) -> dict[str, Any]:
    """Decode Temporal search attribute indexedFields into a flat dict."""
    if not attributes:
        return {}
    indexed = attributes.get("indexedFields", {})
    if not indexed:
        return {}
    # indexedFields is a flat {key: payload} dict
    return {k: decode_payload(v) for k, v in indexed.items()}


# ── HTTP helpers ───────────────────────────────────────────────────────

async def http_get_json(url: str, timeout: int = 30) -> Any:
    """Fetch JSON from a URL (async via to_thread)."""
    loop = asyncio.get_running_loop()

    def _fetch() -> bytes:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            content = resp.read()
            if len(content) > MAX_HISTORY_BYTES:
                raise ValueError(
                    f"Response too large: {len(content)} bytes from {url}"
                )
            return content

    content = await loop.run_in_executor(None, _fetch)
    return json.loads(content)


async def http_get_json_safe(url: str, timeout: int = 30) -> Any | None:
    """Fetch JSON, returning None on any error."""
    try:
        return await http_get_json(url, timeout=timeout)
    except Exception:
        return None


# ── Data model ─────────────────────────────────────────────────────────

@dataclass
class WorkflowSummary:
    workflow_id: str
    run_id: str
    workflow_type: str
    status: str
    start_time: str
    close_time: str
    task_queue: str
    history_length: int
    search_attributes: dict[str, Any] = field(default_factory=dict)
    parent_workflow_id: str | None = None
    parent_run_id: str | None = None


@dataclass
class FailureRow:
    root_workflow_id: str
    root_run_id: str
    failing_wf_id: str
    failing_wf_type: str
    activity_type: str
    category: str
    top_message: str
    root_cause_message: str
    retry_state: str
    camera: str
    label: str
    model: str
    build_id: str
    start_time: str
    duration_seconds: float


@dataclass
class ActivityAttempt:
    workflow_id: str
    run_id: str
    activity_id: str
    activity_type: str
    task_queue: str
    attempt: int
    scheduled_time: str
    started_time: str
    completed_time: str
    retry_state: str
    failure_message: str


@dataclass
class WorkflowAnalysis:
    workflow_id: str
    run_id: str
    workflow_type: str
    status: str
    start_time: str
    close_time: str
    task_queue: str
    history_length: int
    search_attributes: dict[str, Any] = field(default_factory=dict)
    parent_workflow_id: str | None = None
    parent_run_id: str | None = None
    root_workflow_id: str = ""
    root_run_id: str = ""
    events: list[dict] = field(default_factory=list)
    failure_chain: dict | None = None
    activity_attempts: list[ActivityAttempt] = field(default_factory=list)
    child_workflows: list[dict] = field(default_factory=list)
    input_data: dict | None = None
    result_data: dict | None = None
    duration_seconds: float = 0.0


# ── Collection ─────────────────────────────────────────────────────────

def _parse_workflow_summary(entry: dict) -> WorkflowSummary:
    """Extract WorkflowSummary from a list API entry."""
    wf = entry.get("execution", {})
    wf_type = entry.get("type", {}).get("name", "Unknown")
    status = entry.get("status", "STATUS_UNSPECIFIED")
    sa = decode_search_attributes(entry.get("searchAttributes"))
    close_time = entry.get("closeTime", "")
    start_time = entry.get("startTime", "")
    parent = entry.get("parentExecution") or {}
    return WorkflowSummary(
        workflow_id=wf.get("workflowId", ""),
        run_id=wf.get("runId", ""),
        workflow_type=wf_type,
        status=status,
        start_time=start_time,
        close_time=close_time,
        task_queue=entry.get("taskQueue", ""),
        history_length=int(entry.get("historyLength", 0)),
        search_attributes=sa,
        parent_workflow_id=parent.get("workflowId"),
        parent_run_id=parent.get("runId"),
    )


async def collect_workflows(
    limit: int,
    checkpoint_path: Path | None = None,
    resume: bool = True,
) -> list[WorkflowSummary]:
    """Paginate through the Temporal list API to collect root GenAIWorkflow executions."""
    roots: list[WorkflowSummary] = []
    children_lookup: dict[str, list[WorkflowSummary]] = {}
    next_token = ""
    total_scanned = 0
    next_token_str = ""

    # Checkpoint resume
    if resume and checkpoint_path and checkpoint_path.exists():
        try:
            ck = json.loads(checkpoint_path.read_text())
            age = time.time() - ck.get("last_updated_ts", 0)
            if age < CHECKPOINT_STALE_SECONDS:
                next_token_str = ck.get("nextPageToken", "")
                roots = [
                    WorkflowSummary(**r)
                    for r in ck.get("collected_roots", [])
                ]
                total_scanned = ck.get("total_scanned", 0)
                print(
                    f"[resume] Checkpoint found: {len(roots)} workflows collected, "
                    f"{total_scanned} total scanned, resuming from page token",
                    file=sys.stderr,
                )
            else:
                print(
                    "[resume] Checkpoint is stale (>1h old), starting fresh",
                    file=sys.stderr,
                )
                checkpoint_path.unlink(missing_ok=True)
        except Exception as e:
            print(f"[resume] Failed to load checkpoint: {e}, starting fresh", file=sys.stderr)
            if checkpoint_path:
                checkpoint_path.unlink(missing_ok=True)

    page_num = 0
    roots_by_id: dict[str, WorkflowSummary] = {}
    # Restore lookup state from existing roots
    for r in roots:
        roots_by_id[r.workflow_id] = r

    def _save_checkpoint():
        if checkpoint_path:
            ck = {
                "nextPageToken": next_token_str,
                "collected_roots": [
                    {
                        "workflow_id": r.workflow_id,
                        "run_id": r.run_id,
                        "workflow_type": r.workflow_type,
                        "status": r.status,
                        "start_time": r.start_time,
                        "close_time": r.close_time,
                        "task_queue": r.task_queue,
                        "history_length": r.history_length,
                        "search_attributes": r.search_attributes,
                        "parent_workflow_id": r.parent_workflow_id,
                        "parent_run_id": r.parent_run_id,
                    }
                    for r in roots
                ],
                "total_scanned": total_scanned,
                "last_updated_ts": time.time(),
            }
            checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
            checkpoint_path.write_text(json.dumps(ck))

    _save_checkpoint()

    while len(roots) < limit:
        page_num += 1
        url = f"{LIST_URL}?pageSize={PAGE_SIZE}"
        if next_token_str:
            url += f"&nextPageToken={urllib.parse.quote(next_token_str, safe='')}"
        data = await http_get_json(url)
        raw_executions = data.get("executions", [])
        next_token_str = data.get("nextPageToken", "")
        total_scanned += len(raw_executions)

        genai_count = sum(
            1 for e in raw_executions
            if e.get("type", {}).get("name") == "GenAIWorkflow"
        )

        for entry in raw_executions:
            wf_type = entry.get("type", {}).get("name", "")
            wf = entry.get("execution", {})
            wf_id = wf.get("workflowId", "")

            summary = _parse_workflow_summary(entry)

            if wf_type == "GenAIWorkflow":
                if len(roots) >= limit:
                    break
                if wf_id not in roots_by_id:
                    roots.append(summary)
                    roots_by_id[wf_id] = summary

            # Track children for collected roots
            parent_id = summary.parent_workflow_id
            if parent_id and parent_id in roots_by_id:
                if parent_id not in children_lookup:
                    children_lookup[parent_id] = []
                children_lookup[parent_id].append(summary)

        if len(roots) % 50 == 0 or page_num == 1:
            print(
                f"[{len(roots)}/{limit}] Page {page_num}: "
                f"({total_scanned} total scanned, {genai_count} GenAIWorkflow on this page, "
                f"{len(roots)} kept so far)",
                file=sys.stderr,
            )

        _save_checkpoint()

        if not next_token_str or len(roots) >= limit:
            break

        # Contingency: no GenAIWorkflow in first 5000 entries
        if total_scanned >= 5000 and len(roots) == 0:
            print(
                "ERROR: No GenAIWorkflow executions found in the latest 5,000 records "
                "— check namespace or retention.",
                file=sys.stderr,
            )
            sys.exit(1)

        await asyncio.sleep(PAGE_DELAY)

    # Delete checkpoint on successful completion
    if checkpoint_path and checkpoint_path.exists():
        checkpoint_path.unlink()

    return roots


# ── History fetching ───────────────────────────────────────────────────

def _extract_failure_chain(events: list[dict]) -> dict | None:
    """Extract the failure chain from history events."""
    for event in events:
        attrs = None
        if "workflowExecutionFailedEventAttributes" in event:
            attrs = event["workflowExecutionFailedEventAttributes"]
        elif "childWorkflowExecutionFailedEventAttributes" in event:
            attrs = event["childWorkflowExecutionFailedEventAttributes"]
        elif "activityTaskFailedEventAttributes" in event:
            attrs = event["activityTaskFailedEventAttributes"]
        if attrs and "failure" in attrs:
            return attrs["failure"]
    return None


def _walk_failure(failure: dict | None) -> tuple[str, str, str]:
    """Walk the failure chain and return (top_message, root_cause_message, retry_state)."""
    if not failure:
        return "", "", ""
    top_msg = failure.get("message", "")[:500]
    retry_state = ""
    # Find root cause (deepest cause with a message)
    root_msg = top_msg
    current = failure.get("cause")
    while current:
        msg = current.get("message", "")
        rs = current.get("retryState", "")
        if rs:
            retry_state = rs
        if msg:
            root_msg = msg[:500]
        current = current.get("cause")
    return top_msg, root_msg, retry_state


def _extract_activity_attempts(
    events: list[dict],
) -> list[ActivityAttempt]:
    """Extract all activity task attempts from history."""
    attempts: list[ActivityAttempt] = []
    # Map activity_scheduled_event_id -> scheduled event
    scheduled: dict[int, dict] = {}
    started: dict[int, dict] = {}

    for ev in events:
        ev_type = ev.get("eventType", "")
        if ev_type.startswith("EVENT_TYPE_"):
            ev_type = ev_type[len("EVENT_TYPE_"):]
        if ev_type == "ACTIVITY_TASK_SCHEDULED":
            sid = str(ev.get("eventId", ""))
            scheduled[sid] = ev
        elif ev_type == "ACTIVITY_TASK_STARTED":
            attrs = ev.get("activityTaskStartedEventAttributes", {})
            sid = str(attrs.get("scheduledEventId", ""))
            started[sid] = ev

    for ev in events:
        ev_type = ev.get("eventType", "")
        if ev_type.startswith("EVENT_TYPE_"):
            ev_type = ev_type[len("EVENT_TYPE_"):]
        if ev_type == "ACTIVITY_TASK_COMPLETED":
            attrs = ev.get("activityTaskCompletedEventAttributes", {})
            sid = str(attrs.get("scheduledEventId", ""))
            sched = scheduled.get(sid, {})
            start = started.get(sid, {})
            attempts.append(ActivityAttempt(
                workflow_id="",
                run_id="",
                activity_id=str(sched.get("activityTaskScheduledEventAttributes", {}).get("activityId", "")),
                activity_type=sched.get("activityTaskScheduledEventAttributes", {}).get(
                    "activityType", {}
                ).get("name", "Unknown"),
                task_queue=sched.get("activityTaskScheduledEventAttributes", {}).get(
                    "taskQueue", {}
                ).get("name", ""),
                attempt=1,
                scheduled_time=ev.get("eventTime", ""),
                started_time=start.get("eventTime", ""),
                completed_time=ev.get("eventTime", ""),
                retry_state="",
                failure_message="",
            ))
        elif ev_type in ("ACTIVITY_TASK_FAILED", "ACTIVITY_TASK_TIMED_OUT"):
            attrs_key = (
                "activityTaskFailedEventAttributes"
                if ev_type == "ACTIVITY_TASK_FAILED"
                else "activityTaskTimedOutEventAttributes"
            )
            attrs = ev.get(attrs_key, {})
            sid = str(attrs.get("scheduledEventId", ""))
            sched = scheduled.get(sid, {})
            start_ev = started.get(sid, {})
            failure = attrs.get("failure", {})
            _, root_msg, retry = _walk_failure(failure)
            attempts.append(ActivityAttempt(
                workflow_id="",
                run_id="",
                activity_id=str(sched.get("activityTaskScheduledEventAttributes", {}).get("activityId", "")),
                activity_type=sched.get("activityTaskScheduledEventAttributes", {}).get(
                    "activityType", {}
                ).get("name", "Unknown"),
                task_queue=sched.get("activityTaskScheduledEventAttributes", {}).get(
                    "taskQueue", {}
                ).get("name", ""),
                attempt=int(attrs.get("attempt", 1)),
                scheduled_time=sched.get("eventTime", ""),
                started_time=start_ev.get("eventTime", ""),
                completed_time=ev.get("eventTime", ""),
                retry_state=attrs.get("retryState", retry),
                failure_message=root_msg,
            ))
    return attempts


def _extract_child_workflows(events: list[dict]) -> list[dict]:
    """Extract child workflow info from history events."""
    children: list[dict] = []
    for ev in events:
        if "childWorkflowExecutionStartedEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionStartedEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            wf_type = attrs.get("workflowType", {}).get("name", "")
            children.append({
                "child_wf_id": wf.get("workflowId", ""),
                "child_run_id": wf.get("runId", ""),
                "child_type": wf_type,
                "status": "STARTED",
            })
        elif "childWorkflowExecutionCompletedEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionCompletedEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            for c in children:
                if c["child_wf_id"] == wf.get("workflowId", ""):
                    c["status"] = "COMPLETED"
                    # Decode result if present
                    result = attrs.get("result")
                    if result:
                        c["result"] = decode_payload(result)
                    break
        elif "childWorkflowExecutionFailedEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionFailedEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            for c in children:
                if c["child_wf_id"] == wf.get("workflowId", ""):
                    c["status"] = "FAILED"
                    break
        elif "childWorkflowExecutionTerminatedEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionTerminatedEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            for c in children:
                if c["child_wf_id"] == wf.get("workflowId", ""):
                    c["status"] = "TERMINATED"
                    break
        elif "childWorkflowExecutionTimedOutEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionTimedOutEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            for c in children:
                if c["child_wf_id"] == wf.get("workflowId", ""):
                    c["status"] = "TIMED_OUT"
                    break
        elif "childWorkflowExecutionCanceledEventAttributes" in ev:
            attrs = ev["childWorkflowExecutionCanceledEventAttributes"]
            wf = attrs.get("workflowExecution", {})
            for c in children:
                if c["child_wf_id"] == wf.get("workflowId", ""):
                    c["status"] = "CANCELED"
                    break
    return children

def _parse_duration(start: str, close: str) -> float:
    """Parse ISO 8601 timestamps and compute duration in seconds."""
    if not start or not close:
        return 0.0
    try:
        s = datetime.fromisoformat(start.replace("Z", "+00:00"))
        e = datetime.fromisoformat(close.replace("Z", "+00:00"))
        return (e - s).total_seconds()
    except Exception:
        return 0.0


async def fetch_single_history(
    wf_id: str, run_id: str, cache_dir: Path, no_cache: bool
) -> tuple[WorkflowAnalysis | None, list[dict], dict | None]:
    """Fetch history + metadata for one workflow. Returns (analysis, raw_events, metadata)."""
    cache_key = f"{wf_id}__{run_id}"
    cache_file = cache_dir / f"{cache_key}.json"

    # Check cache
    if not no_cache and cache_file.exists():
        try:
            cached = json.loads(cache_file.read_text())
            history = cached.get("history", {}).get("history", {}).get("events", [])
            metadata = cached.get("metadata", {})
            decoded_history = decode_payload(history)
            decoded_meta = decode_payload(metadata)
            return None, decoded_history, decoded_meta  # caller builds analysis
        except Exception:
            cache_file.unlink(missing_ok=True)

    # Fetch from API
    history_resp = await http_get_json_safe(
        f"{API_BASE}/workflows/{wf_id}/history?execution.runId={run_id}"
    )
    metadata_resp = await http_get_json_safe(
        f"{API_BASE}/workflows/{wf_id}?execution.runId={run_id}"
    )

    if history_resp is None:
        print(f"  [warn] 404/error fetching history for {wf_id}", file=sys.stderr)
        return None, [], None

    # Cache raw response
    if not no_cache:
        cache_file.write_text(json.dumps({
            "history": history_resp,
            "metadata": metadata_resp or {},
        }))

    events = decode_payload(history_resp.get("history", {}).get("events", []))
    metadata = decode_payload(metadata_resp) if metadata_resp else {}
    return None, events, metadata


async def fetch_histories(
    summaries: list[WorkflowSummary],
    cache_dir: Path,
    no_cache: bool = False,
) -> list[WorkflowAnalysis]:
    """Fetch full history for each workflow summary. Returns list of WorkflowAnalysis."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    sem = asyncio.Semaphore(FETCH_CONCURRENCY)
    analyses: list[WorkflowAnalysis] = []
    completed = 0
    total = len(summaries)

    async def _fetch_one(s: WorkflowSummary) -> WorkflowAnalysis | None:
        nonlocal completed
        async with sem:
            _, events, meta = await fetch_single_history(
                s.workflow_id, s.run_id, cache_dir, no_cache
            )
            completed += 1
            if completed % 100 == 0:
                print(f"[{completed}/{total}] Histories fetched...", file=sys.stderr)
            if not events:
                return None  # skipped/failed
            return _build_analysis(s, events, meta)

    tasks = [_fetch_one(s) for s in summaries]
    results = await asyncio.gather(*tasks)
    analyses = [r for r in results if r is not None]

    return analyses


def _build_analysis(
    summary: WorkflowSummary,
    events: list[dict],
    metadata: dict | None,
) -> WorkflowAnalysis:
    """Build a WorkflowAnalysis from summary, events, and metadata."""
    sa = summary.search_attributes
    duration = _parse_duration(summary.start_time, summary.close_time)

    # Extract failure chain
    failure_chain = _extract_failure_chain(events)

    # Extract activity attempts
    activity_attempts = _extract_activity_attempts(events)

    # Extract child workflows
    child_workflows = _extract_child_workflows(events)

    # Extract input/result from metadata
    input_data = decode_payload(metadata.get("workflowExecutionInfo", {}).get("execution", {}).get("input")) if metadata else None
    result_data = decode_payload(metadata.get("workflowExecutionInfo", {}).get("execution", {}).get("result")) if metadata else None

    # Also try getting input from the first WorkflowExecutionStarted event
    if input_data is None:
        for ev in events:
            if "workflowExecutionStartedEventAttributes" in ev:
                inp = ev["workflowExecutionStartedEventAttributes"].get("input")
                if inp:
                    input_data = decode_payload(inp)
                break

    return WorkflowAnalysis(
        workflow_id=summary.workflow_id,
        run_id=summary.run_id,
        workflow_type=summary.workflow_type,
        status=summary.status,
        start_time=summary.start_time,
        close_time=summary.close_time,
        task_queue=summary.task_queue,
        history_length=summary.history_length,
        search_attributes=sa,
        parent_workflow_id=summary.parent_workflow_id,
        parent_run_id=summary.parent_run_id,
        root_workflow_id=summary.workflow_id,
        root_run_id=summary.run_id,
        events=events,
        failure_chain=failure_chain,
        activity_attempts=activity_attempts,
        child_workflows=child_workflows,
        input_data=input_data,
        result_data=result_data,
        duration_seconds=duration,
    )


# ── Failure categorization ─────────────────────────────────────────────

CATEGORY_RULES: list[tuple[str, str]] = [
    # (category, match pattern against lowercased concatenated message)
    ("provider_rate_limit", "429|ratelimiterror|resource_exhausted|prepayment credits are depleted"),
    ("provider_auth_billing", "401|403|billing|api key not valid"),
    ("provider_server_error", "500|502|503|bad gateway|internalservererror"),
    ("provider_network_error", "connectionerror|connecttimeout|remotedisconnected|nameresolutionerror"),
    ("recording_not_ready", "recording not ready"),
    ("transcode_failure", "transcode failed"),
    ("frigate_api_error", "failed to update|update_description"),
    ("activity_timeout", "activity task timed out"),
    ("ollama_unavailable", "no available server"),
    ("workflow_task_failure", ""),  # special case: search attribute check
    ("non_retryable_error", ""),    # special case: retry state check
    ("tool_failure", "invalid crop|invalid frame source|too many frames|cannot crop"),
    ("s3_error", "accessdenied|nosuchkey"),
]


def _get_first_activity_type(failure_row_data: dict) -> str:
    """Get the activity type from various locations in the failure chain."""
    return failure_row_data.get("_activity_type", "")


def categorize_failure(
    analysis: WorkflowAnalysis,
    root_wf_id: str = "",
    root_run_id: str = "",
    child_wf_id: str | None = None,
    child_wf_type: str | None = None,
) -> FailureRow | None:
    """Categorize a failure from a WorkflowAnalysis."""
    if analysis.status == "WORKFLOW_EXECUTION_STATUS_CANCELED":
        sa = analysis.search_attributes
        return FailureRow(
            root_workflow_id=root_wf_id or analysis.workflow_id,
            root_run_id=root_run_id or analysis.run_id,
            failing_wf_id=child_wf_id or analysis.workflow_id,
            failing_wf_type=child_wf_type or analysis.workflow_type,
            activity_type="",
            category="cancelled",
            top_message="Cancelled",
            root_cause_message="",
            retry_state="",
            camera=str(sa.get("Camera", "")),
            label=str(sa.get("Label", "")),
            model=str(sa.get("Model", "")),
            build_id=str(sa.get("BuildIds", "")),
            start_time=analysis.start_time,
            duration_seconds=analysis.duration_seconds,
        )

    if analysis.status == "WORKFLOW_EXECUTION_STATUS_TERMINATED" and not analysis.failure_chain:
        sa = analysis.search_attributes
        return FailureRow(
            root_workflow_id=root_wf_id or analysis.workflow_id,
            root_run_id=root_run_id or analysis.run_id,
            failing_wf_id=child_wf_id or analysis.workflow_id,
            failing_wf_type=child_wf_type or analysis.workflow_type,
            activity_type="",
            category="terminated",
            top_message="Terminated",
            root_cause_message="",
            retry_state="",
            camera=str(sa.get("Camera", "")),
            label=str(sa.get("Label", "")),
            model=str(sa.get("Model", "")),
            build_id=str(sa.get("BuildIds", "")),
            start_time=analysis.start_time,
            duration_seconds=analysis.duration_seconds,
        )

    if not analysis.failure_chain:
        return None

    top_msg, root_msg, retry_state = _walk_failure(analysis.failure_chain)
    combined = f"{top_msg} | {root_msg}".lower()

    # Check workflow_task_failure via search attributes
    sa = analysis.search_attributes
    temporal_problems = str(sa.get("TemporalReportedProblems", ""))
    if "workflowtaskfailed" in temporal_problems.lower():
        return FailureRow(
            root_workflow_id=root_wf_id or analysis.workflow_id,
            root_run_id=root_run_id or analysis.run_id,
            failing_wf_id=child_wf_id or analysis.workflow_id,
            failing_wf_type=child_wf_type or analysis.workflow_type,
            activity_type="",
            category="workflow_task_failure",
            top_message=top_msg,
            root_cause_message=root_msg,
            retry_state=retry_state,
            camera=str(sa.get("Camera", "")),
            label=str(sa.get("Label", "")),
            model=str(sa.get("Model", "")),
            build_id=str(sa.get("BuildIds", "")),
            start_time=analysis.start_time,
            duration_seconds=analysis.duration_seconds,
        )

    # Ordered category rules
    for category, pattern in CATEGORY_RULES:
        if not pattern:
            continue  # special cases handled above
        if re.search(pattern, combined):
            # transcode_failure has an extra condition
            if category == "transcode_failure":
                # Check if any failed activity is transcode_into_parts
                has_transcode = any(
                    a.activity_type == "transcode_into_parts" and a.failure_message
                    for a in analysis.activity_attempts
                )
                if not has_transcode:
                    continue
            return FailureRow(
                root_workflow_id=root_wf_id or analysis.workflow_id,
                root_run_id=root_run_id or analysis.run_id,
                failing_wf_id=child_wf_id or analysis.workflow_id,
                failing_wf_type=child_wf_type or analysis.workflow_type,
                activity_type=_find_failing_activity(analysis),
                category=category,
                top_message=top_msg,
                root_cause_message=root_msg,
                retry_state=retry_state,
                camera=str(sa.get("Camera", "")),
                label=str(sa.get("Label", "")),
                model=str(sa.get("Model", "")),
                build_id=str(sa.get("BuildIds", "")),
                start_time=analysis.start_time,
                duration_seconds=analysis.duration_seconds,
            )

    # Check non_retryable_error (only after all other categories have been checked)
    if (not retry_state or retry_state == "RETRY_STATE_RETRY_POLICY_NOT_SET"):
        fc = analysis.failure_chain
        has_app_failure = False
        if fc:
            app_info = fc.get("applicationFailureInfo")
            if app_info:
                has_app_failure = True
            else:
                cause = fc.get("cause")
                while cause:
                    if cause.get("applicationFailureInfo"):
                        has_app_failure = True
                        break
                    cause = cause.get("cause")
        if has_app_failure:
            return FailureRow(
                root_workflow_id=root_wf_id or analysis.workflow_id,
                root_run_id=root_run_id or analysis.run_id,
                failing_wf_id=child_wf_id or analysis.workflow_id,
                failing_wf_type=child_wf_type or analysis.workflow_type,
                activity_type=_find_failing_activity(analysis),
                category="non_retryable_error",
                top_message=top_msg,
                root_cause_message=root_msg,
                retry_state=retry_state,
                camera=str(sa.get("Camera", "")),
                label=str(sa.get("Label", "")),
                model=str(sa.get("Model", "")),
                build_id=str(sa.get("BuildIds", "")),
                start_time=analysis.start_time,
                duration_seconds=analysis.duration_seconds,
            )
    # Unknown
    return FailureRow(
        root_workflow_id=root_wf_id or analysis.workflow_id,
        root_run_id=root_run_id or analysis.run_id,
        failing_wf_id=child_wf_id or analysis.workflow_id,
        failing_wf_type=child_wf_type or analysis.workflow_type,
        activity_type=_find_failing_activity(analysis),
        category="unknown",
        top_message=top_msg,
        root_cause_message=root_msg,
        retry_state=retry_state,
        camera=str(sa.get("Camera", "")),
        label=str(sa.get("Label", "")),
        model=str(sa.get("Model", "")),
        build_id=str(sa.get("BuildIds", "")),
        start_time=analysis.start_time,
        duration_seconds=analysis.duration_seconds,
    )


def _find_failing_activity(analysis: WorkflowAnalysis) -> str:
    """Find the activity type of the failed activity, or child workflow type."""
    for a in analysis.activity_attempts:
        if a.failure_message:
            return a.activity_type
    # Fallback 1: look in events for ActivityTaskFailed or ActivityTaskTimedOut
    for ev in analysis.events:
        et = ev.get("eventType", "").replace("EVENT_TYPE_", "")
        if et in ("ACTIVITY_TASK_FAILED", "ACTIVITY_TASK_TIMED_OUT"):
            attrs_key = (
                "activityTaskFailedEventAttributes"
                if et == "ACTIVITY_TASK_FAILED"
                else "activityTaskTimedOutEventAttributes"
            )
            attrs = ev.get(attrs_key, {})
            sid = attrs.get("scheduledEventId")
            if sid:
                for se in analysis.events:
                    if str(se.get("eventId", "")) == str(sid):
                        return se.get("activityTaskScheduledEventAttributes", {}).get(
                            "activityType", {}
                        ).get("name", "")
                break
    # Fallback 2: look for child workflow failure events
    for ev in analysis.events:
        et = ev.get("eventType", "").replace("EVENT_TYPE_", "")
        if et == "CHILD_WORKFLOW_EXECUTION_FAILED":
            attrs = ev.get("childWorkflowExecutionFailedEventAttributes", {})
            wf_type = attrs.get("workflowType", {}).get("name", "")
            if wf_type:
                return f"child:{wf_type}"
            break
    return ""


def categorize_failures(
    analyses: list[WorkflowAnalysis],
    child_analyses: dict[str, list[WorkflowAnalysis]] | None = None,
) -> list[FailureRow]:
    """Categorize failures across all analyses including child workflows."""
    failures: list[FailureRow] = []

    for analysis in analyses:
        row = categorize_failure(analysis)
        if row:
            failures.append(row)

        # Also categorize child workflow failures
        for child in analysis.child_workflows:
            if child.get("status") == "FAILED":
                # If we have child analyses, use them; otherwise create from child info
                child_id = child.get("child_wf_id", "")
                child_type = child.get("child_type", "")
                if child_analyses and child_id in child_analyses:
                    for ca in child_analyses[child_id]:
                        row = categorize_failure(
                            ca,
                            root_wf_id=analysis.workflow_id,
                            root_run_id=analysis.run_id,
                            child_wf_id=child_id,
                            child_wf_type=child_type,
                        )
                        if row:
                            failures.append(row)
                else:
                    # Create a minimal analysis from child event data
                    # Look for the child failure event in parent's history
                    for ev in analysis.events:
                        attrs = ev.get("childWorkflowExecutionFailedEventAttributes", {})
                        wf = attrs.get("workflowExecution", {})
                        if wf.get("workflowId") == child_id and attrs.get("failure"):
                            fake_analysis = WorkflowAnalysis(
                                workflow_id=child_id,
                                run_id=wf.get("runId", ""),
                                workflow_type=child_type,
                                status="WORKFLOW_EXECUTION_STATUS_FAILED",
                                start_time=analysis.start_time,
                                close_time=analysis.close_time,
                                task_queue="",
                                history_length=0,
                                search_attributes=analysis.search_attributes,
                                failure_chain=attrs["failure"],
                                duration_seconds=analysis.duration_seconds,
                            )
                            row = categorize_failure(
                                fake_analysis,
                                root_wf_id=analysis.workflow_id,
                                root_run_id=analysis.run_id,
                                child_wf_id=child_id,
                                child_wf_type=child_type,
                            )
                            if row:
                                failures.append(row)
                            break

    return failures


# ── Output ─────────────────────────────────────────────────────────────

def _sa(sa: dict[str, Any], key: str, default: str = "") -> str:
    """Safe search attribute getter, handling Temporal payload wrapping."""
    val = sa.get(key, default)
    if isinstance(val, dict):
        # Might be a raw payload that wasn't decoded; extract data
        data = val.get("data", "")
        if data:
            try:
                decoded = base64.b64decode(data).decode("utf-8")
                try:
                    return str(json.loads(decoded))
                except json.JSONDecodeError:
                    return decoded
            except Exception:
                return str(val)
        return str(val)
    return str(val) if val else default


def write_csvs(
    analyses: list[WorkflowAnalysis],
    failures: list[FailureRow],
    child_analyses: list[WorkflowAnalysis] | None,
    output_dir: Path,
) -> None:
    """Write all CSV output files."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # temporal_workflows.csv
    wf_path = output_dir / "temporal_workflows.csv"
    with open(wf_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "workflow_id", "run_id", "status", "start_time", "close_time",
            "duration_seconds", "camera", "label", "model", "task_queue",
            "build_id", "worker_deployment", "history_length",
            "state_transitions", "tool_failures", "transcode", "confidence",
            "cost", "has_failure", "failure_category", "failure_message",
        ])
        for a in analyses:
            sa = a.search_attributes
            has_failure = a.status in (
                "WORKFLOW_EXECUTION_STATUS_FAILED",
                "WORKFLOW_EXECUTION_STATUS_TERMINATED",
            )
            failure_category = ""
            failure_message = ""
            for fr in failures:
                if fr.root_workflow_id == a.workflow_id:
                    failure_category = fr.category
                    failure_message = fr.root_cause_message or fr.top_message
                    break
            # Compute state transitions count
            state_transitions = sum(
                1 for ev in a.events
                if ev.get("eventType", "").replace("EVENT_TYPE_", "").startswith("WORKFLOW_TASK")
            )
            writer.writerow([
                a.workflow_id,
                a.run_id,
                a.status,
                a.start_time,
                a.close_time,
                f"{a.duration_seconds:.1f}",
                _sa(sa, "Camera"),
                _sa(sa, "Label"),
                _sa(sa, "Model"),
                a.task_queue,
                _sa(sa, "BuildIds"),
                _sa(sa, "TemporalWorkerDeployment"),
                a.history_length,
                state_transitions,
                _sa(sa, "ToolFailures"),
                _sa(sa, "Transcode"),
                _sa(sa, "Confidence"),
                _sa(sa, "Cost"),
                str(has_failure),
                failure_category,
                failure_message,
            ])

    # temporal_failures.csv
    fail_path = output_dir / "temporal_failures.csv"
    with open(fail_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "root_workflow_id", "root_run_id", "failing_workflow_id",
            "failing_workflow_type", "activity_type", "category",
            "top_message", "root_cause_message", "retry_state",
            "camera", "label", "model", "build_id",
            "start_time", "duration_seconds",
        ])
        for fr in failures:
            writer.writerow([
                fr.root_workflow_id,
                fr.root_run_id,
                fr.failing_wf_id,
                fr.failing_wf_type,
                fr.activity_type,
                fr.category,
                fr.top_message,
                fr.root_cause_message,
                fr.retry_state,
                fr.camera,
                fr.label,
                fr.model,
                fr.build_id,
                fr.start_time,
                f"{fr.duration_seconds:.1f}",
            ])

    # temporal_activity_attempts.csv
    act_path = output_dir / "temporal_activity_attempts.csv"
    all_activities: list[ActivityAttempt] = []
    for a in analyses:
        for aa in a.activity_attempts:
            aa.workflow_id = a.workflow_id
            aa.run_id = a.run_id
            all_activities.append(aa)
    if child_analyses:
        for ca in child_analyses:
            for aa in ca.activity_attempts:
                aa.workflow_id = ca.workflow_id
                aa.run_id = ca.run_id
                all_activities.append(aa)

    with open(act_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "workflow_id", "run_id", "activity_id", "activity_type",
            "task_queue", "attempt", "scheduled_time", "started_time",
            "completed_time", "retry_state", "failure_message",
        ])
        for aa in all_activities:
            writer.writerow([
                aa.workflow_id,
                aa.run_id,
                aa.activity_id,
                aa.activity_type,
                aa.task_queue,
                aa.attempt,
                aa.scheduled_time,
                aa.started_time,
                aa.completed_time,
                aa.retry_state,
                aa.failure_message,
            ])

    # temporal_categories.json
    summary_path = output_dir / "temporal_categories.json"
    categories: dict[str, int] = {}
    by_camera: dict[str, dict[str, int]] = {}
    by_model: dict[str, dict[str, int]] = {}
    by_build_id: dict[str, dict[str, int]] = {}

    for a in analyses:
        sa = a.search_attributes
        camera = _sa(sa, "Camera") or "unknown"
        model = _sa(sa, "Model") or "unknown"
        bid = _sa(sa, "BuildIds") or "unknown"

        if camera not in by_camera:
            by_camera[camera] = {"total": 0, "failed": 0}
        by_camera[camera]["total"] += 1
        if a.status == "WORKFLOW_EXECUTION_STATUS_FAILED":
            by_camera[camera]["failed"] += 1

        if model not in by_model:
            by_model[model] = {"total": 0, "failed": 0}
        by_model[model]["total"] += 1
        if a.status == "WORKFLOW_EXECUTION_STATUS_FAILED":
            by_model[model]["failed"] += 1

        if bid not in by_build_id:
            by_build_id[bid] = {"total": 0, "failed": 0}
        by_build_id[bid]["total"] += 1
        if a.status == "WORKFLOW_EXECUTION_STATUS_FAILED":
            by_build_id[bid]["failed"] += 1

    for fr in failures:
        cat = fr.category
        categories[cat] = categories.get(cat, 0) + 1

    summary = {
        "total_workflows": len(analyses),
        "total_with_failures": sum(
            1 for a in analyses
            if a.status in (
                "WORKFLOW_EXECUTION_STATUS_FAILED",
                "WORKFLOW_EXECUTION_STATUS_TERMINATED",
            )
        ),
        "categories": dict(sorted(categories.items(), key=lambda x: -x[1])),
        "by_camera": by_camera,
        "by_model": by_model,
        "by_build_id": by_build_id,
    }
    summary_path.write_text(json.dumps(summary, indent=2))

    # temporal_raw_history.jsonl.gz
    raw_path = output_dir / "temporal_raw_history.jsonl.gz"
    with gzip.open(raw_path, "wt", encoding="utf-8") as f:
        for a in analyses:
            f.write(json.dumps({
                "workflow_id": a.workflow_id,
                "run_id": a.run_id,
                "workflow_type": a.workflow_type,
                "status": a.status,
                "start_time": a.start_time,
                "close_time": a.close_time,
                "events": a.events,
                "input": a.input_data,
                "result": a.result_data,
            }) + "\n")


def print_summary(
    analyses: list[WorkflowAnalysis],
    failures: list[FailureRow],
) -> None:
    """Print a human-readable summary to stdout."""
    total = len(analyses)
    completed = sum(1 for a in analyses if a.status == "WORKFLOW_EXECUTION_STATUS_COMPLETED")
    failed = sum(1 for a in analyses if a.status == "WORKFLOW_EXECUTION_STATUS_FAILED")
    terminated = sum(1 for a in analyses if a.status == "WORKFLOW_EXECUTION_STATUS_TERMINATED")
    cancelled = sum(1 for a in analyses if a.status == "WORKFLOW_EXECUTION_STATUS_CANCELED")
    other = total - completed - failed - terminated - cancelled

    # Count categories
    cat_counts: dict[str, int] = {}
    for fr in failures:
        cat = fr.category
        cat_counts[cat] = cat_counts.get(cat, 0) + 1

    print()
    print("=== Temporal Job Analysis ===")
    print(f"Total root workflows: {total}")
    if completed:
        print(f"  Completed:   {completed:>5} ({completed/total*100:.1f}%)")
    if failed:
        print(f"  Failed:      {failed:>5} ({failed/total*100:.1f}%)")
    if terminated:
        print(f"  Terminated:  {terminated:>5} ({terminated/total*100:.1f}%)")
    if cancelled:
        print(f"  Cancelled:   {cancelled:>5} ({cancelled/total*100:.1f}%)")
    if other:
        print(f"  Other:       {other:>5} ({other/total*100:.1f}%)")

    if cat_counts:
        print()
        print("Failure categories:")
        total_failures = sum(cat_counts.values())
        for cat, count in sorted(cat_counts.items(), key=lambda x: -x[1]):
            print(f"  {cat:<30} {count:>5} ({count/total_failures*100:.1f}%)")
    print()


# ── Main ───────────────────────────────────────────────────────────────

async def main() -> None:
    parser = argparse.ArgumentParser(
        description="Temporal GenAIWorkflow Job Analyzer"
    )
    parser.add_argument(
        "--limit", type=int, default=DEFAULT_LIMIT,
        help=f"Number of root GenAIWorkflow executions to collect (default: {DEFAULT_LIMIT})",
    )
    parser.add_argument(
        "--cache-dir", type=str, default="./temporal_cache",
        help="Directory for per-workflow history cache files (default: ./temporal_cache/)",
    )
    parser.add_argument(
        "--output-dir", type=str, default=".",
        help="Directory for CSV/JSON output files (default: .)",
    )
    parser.add_argument(
        "--include-children", action="store_true",
        help="Include child workflows in the workflows CSV (not just in failures)",
    )
    parser.add_argument(
        "--no-cache", action="store_true",
        help="Skip cache; re-fetch everything",
    )
    parser.add_argument(
        "--no-resume", action="store_true",
        help="Ignore checkpoint.json and start collection from scratch",
    )

    args = parser.parse_args()

    cache_dir = Path(args.cache_dir)
    output_dir = Path(args.output_dir)
    checkpoint_path = cache_dir / "checkpoint.json"

    start_time = time.time()

    # Step 1: Collect workflows
    print(f"Collecting up to {args.limit} GenAIWorkflow executions...", file=sys.stderr)
    root_summaries = await collect_workflows(
        limit=args.limit,
        checkpoint_path=checkpoint_path,
        resume=not args.no_resume,
    )
    print(
        f"Collected {len(root_summaries)} GenAIWorkflow executions.",
        file=sys.stderr,
    )

    # Step 2: Fetch histories
    print(f"Fetching histories for {len(root_summaries)} workflows...", file=sys.stderr)
    root_analyses = await fetch_histories(
        root_summaries, cache_dir, no_cache=args.no_cache
    )

    # If include-children, also fetch child workflow histories
    child_analyses: list[WorkflowAnalysis] | None = None
    if args.include_children:
        child_summaries: list[WorkflowSummary] = []
        for ra in root_analyses:
            for cw in ra.child_workflows:
                child_summaries.append(WorkflowSummary(
                    workflow_id=cw["child_wf_id"],
                    run_id=cw["child_run_id"],
                    workflow_type=cw["child_type"],
                    status=cw.get("status", ""),
                    start_time=ra.start_time,
                    close_time=ra.close_time,
                    task_queue="",
                    history_length=0,
                    search_attributes=ra.search_attributes,
                    parent_workflow_id=ra.workflow_id,
                    parent_run_id=ra.run_id,
                ))
        if child_summaries:
            print(
                f"Fetching histories for {len(child_summaries)} child workflows...",
                file=sys.stderr,
            )
            child_analyses = await fetch_histories(
                child_summaries, cache_dir, no_cache=args.no_cache
            )

    # Step 3: Categorize failures
    print("Categorizing failures...", file=sys.stderr)
    failures = categorize_failures(root_analyses)

    # Step 4: Write output
    print("Writing output files...", file=sys.stderr)
    write_csvs(root_analyses, failures, child_analyses, output_dir)

    # Step 5: Print summary
    print_summary(root_analyses, failures)

    elapsed = time.time() - start_time
    print(f"CSVs written to: {output_dir.resolve()}/", file=sys.stderr)
    print(f"Total time: {elapsed:.1f}s", file=sys.stderr)


if __name__ == "__main__":
    asyncio.run(main())
