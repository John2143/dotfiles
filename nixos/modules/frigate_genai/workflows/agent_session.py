"""AgentSessionWorkflow -- self-contained agent turn loop as Temporal child workflow."""

from datetime import timedelta

from temporalio import workflow
from temporalio.exceptions import ApplicationError

from frigate_genai.config import _GENAI_RETRY, _ACTIVITY_RETRY
from frigate_genai.activities.genai_turn import run_genai_turn_activity
from frigate_genai.activities.tool_apply import apply_tool_messages_activity
from frigate_genai.tools import _TOOL_ACTIVITIES, _get_tool_queue
from frigate_genai.tools.schemas import (
    _tool_find_keyframes_schema, _tool_frame_diff_schema, _tool_tag_image_schema,
    _tool_get_snapshot_schema, _tool_show_frame_schema, _tool_crop_schema,
    _tool_transcode_schema, _tool_compact_schema, _tool_set_description_schema,
    _tool_upscale_schema, _tool_spawn_schema, _tool_join_schema,
    _tool_close_subagent_schema,
)


# ── helpers ──────────────────────────────────────────────────────────────────

def _resolve_image_refs(refs: list[str], agent_dir: str, frames_dir: str = "") -> tuple[list[str], list[str]]:
    """Convert image refs (crop://N, frame://N) to S3 keys under agent_dir.
    Returns (resolved_keys, error_refs). Never raises.
    Supports crop://<non-negative int> and frame://<non-negative int>.
    Strips @<suffix> before parsing. Silently ignores unknown schemes.
    When frames_dir is provided, it is used for frame:// key resolution instead
    of deriving from agent_dir (important for nested subagents).
    """
    base = agent_dir.rstrip("/")
    parent = "/".join(base.split("/")[:-1]) + "/"
    keys = []
    errors = []
    for ref in refs:
        if ref.startswith("crop://"):
            idx_str = ref[len("crop://"):].split("@")[0]
            try:
                idx = int(idx_str)
                k = f"{base}/crop_{idx:03d}.jpg"
                keys.append(k)
            except ValueError:
                errors.append(ref)
        elif ref.startswith("frame://"):
            idx_str = ref[len("frame://"):].split("@")[0]
            try:
                idx = int(idx_str)
                if frames_dir:
                    k = f"{frames_dir}/frames/frame_{idx:03d}.jpg"
                else:
                    k = f"{parent}frames/frame_{idx:03d}.jpg"
                keys.append(k)
            except ValueError:
                errors.append(ref)
    return keys, errors


def _format_spawn_findings(findings: list[dict]) -> str:
    """Format subagent findings into a parent-readable message with synthesis."""
    successes = [f for f in findings if not f.get("error")]
    failures = [f for f in findings if f.get("error")]

    lines = []
    lines.append(f"JOIN RESULTS: {len(successes)} of {len(findings)} subagents completed successfully.")

    high = [f for f in successes if f.get("confidence") == "high"]
    if high:
        lines.append(f"\nHIGH confidence findings ({len(high)}):")
        for i, f in enumerate(high):
            lines.append(f"  [{i+1}] {f.get('findings', '')[:200]}")

    medium = [f for f in successes if f.get("confidence") == "medium"]
    if medium:
        lines.append(f"\nMEDIUM confidence findings ({len(medium)}):")
        for i, f in enumerate(medium):
            lines.append(f"  [{i+1}] {f.get('findings', '')[:200]}")

    low = [f for f in successes if f.get("confidence") not in ("high", "medium")]
    if low:
        lines.append(f"\nUNSURE / NOTHING FOUND ({len(low)}):")
        for i, f in enumerate(low):
            lines.append(f"  [{i+1}] [{f.get('confidence','?')}] {f.get('findings', '')[:200]}")

    if failures:
        lines.append(f"\nFAILED subagents ({len(failures)}):")
        for i, f in enumerate(failures):
            lines.append(f"  [{i+1}] {f['error'][:200]}")

    lines.append(
        f"\nExamine high-confidence findings first. If multiple subagents disagree, "
        f"re-investigate the disputed region yourself. Use spawn/join again if needed."
    )
    return "\n".join(lines)

def _get_tools_for_depth(depth: int, max_depth: int) -> list[dict]:
    """Return tool schemas available at given depth. Root gets set_description + spawn + join.
    Subagents get close_subagent instead of set_description. Deepest agents lose spawn/join."""
    base = [
        _tool_find_keyframes_schema(), _tool_frame_diff_schema(), _tool_tag_image_schema(),
        _tool_show_frame_schema(), _tool_crop_schema(), _tool_transcode_schema(),
        _tool_upscale_schema(),
    ]
    if depth == 0:
        return base + [
            _tool_get_snapshot_schema(), _tool_compact_schema(),
            _tool_set_description_schema(),
            _tool_spawn_schema(), _tool_join_schema(),
        ]
    elif depth < max_depth:
        return base + [
            _tool_close_subagent_schema(),
            _tool_spawn_schema(), _tool_join_schema(),
        ]
    else:
        return base + [
            _tool_close_subagent_schema(),
        ]

# ── workflow ─────────────────────────────────────────────────────────────────

@workflow.defn
class AgentSessionWorkflow:
    """Self-contained agent turn loop. Reads/writes messages.json via activities.
    Can be run as child workflow of GenAIWorkflow or recursively."""

    @workflow.run
    async def run(self, session_input: dict) -> dict:
        msg_path = session_input["msg_path"]
        provider_path = session_input["provider_path"]
        model = session_input["model"]
        event_id = session_input["event_id"]
        camera = session_input["camera"]
        label = session_input["label"]
        max_turns = session_input["max_turns"]
        max_frames = session_input["max_frames"]
        start_time = session_input["start_time"]
        end_time = session_input["end_time"]
        genai_queue = session_input["genai_queue"]
        prompts_path = session_input.get("prompts_path", "")
        depth = session_input.get("depth", 0)
        max_depth = session_input.get("max_depth", 2)

        turn_arg = {
            "msg_path": msg_path,
            "provider_path": provider_path,
            "model": model,
            "event_id": event_id,
            "camera": camera,
            "label": label,
        }

        total_cost = {"prompt": 0, "completion": 0, "cached": 0}
        turns_low = 0
        turns_high = 0
        turns_max = 0
        turns_transcode = 0
        tool_failures = 0
        # Spawn/join tracking
        spawn_handles: dict[str, list[tuple[dict, object]]] = {}
        total_subagents = 0
        _spawn_count = 0
        MAX_CONCURRENT_SPAWNS = 5
        MAX_TOTAL_SUBAGENTS = 20
        trace_entries: list[dict] = []
        description = None
        confidence = None

        for turn in range(max_turns):
            turn_arg["turn_num"] = turn + 1
            turn_arg["max_turns"] = max_turns
            turn_arg["tools"] = _get_tools_for_depth(depth, max_depth)
            result = await workflow.execute_activity(
                run_genai_turn_activity,
                arg=turn_arg,
                task_queue=genai_queue,
                start_to_close_timeout=timedelta(seconds=300),
                heartbeat_timeout=timedelta(seconds=15),
                retry_policy=_GENAI_RETRY,
            )

            pt = result.get("prompt_tokens", 0)
            ct = result.get("completion_tokens", 0)
            cached = result.get("cached_tokens", 0)
            total_cost["prompt"] += pt
            total_cost["completion"] += ct
            total_cost["cached"] += cached
            trace_entries.append({
                "type": "turn", "turn": turn + 1,
                "prompt_tokens": pt, "completion_tokens": ct,
                "cached": cached > 0,
            })
            workflow.set_current_details(
                f"Turn {turn+1}/{max_turns} | "
                f"tokens: {total_cost['prompt']}+{total_cost['completion']} "
                f"(cached: {total_cost['cached']}) | "
                f"tools: {len(trace_entries)}"
            )

            if result.get("description"):
                description = result["description"]
                confidence = result.get("confidence", "medium")
                trace_entries.append({
                    "type": "tool_call", "name": "set_description",
                    "confidence": confidence,
                    "description": description[:200],
                })
                break

            if result.get("text_only"):
                trace_entries.append({"type": "nudge", "reason": "no_tool_call"})
                continue

            # Parallel tool dispatch
            handles: list[tuple[dict, dict, object]] = []
            outcomes: list[dict] = []
            for tc in result.get("tool_calls", []):
                # ── spawn handling ────────────────────────────────────────────
                if tc["name"] == "spawn":
                    tasks = tc["args"].get("tasks", [])
                    if total_subagents + len(tasks) > MAX_TOTAL_SUBAGENTS:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Subagent limit ({MAX_TOTAL_SUBAGENTS}) reached. Conclude."}]})
                        continue
                    if len(tasks) > MAX_CONCURRENT_SPAWNS:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Max {MAX_CONCURRENT_SPAWNS} subagents per spawn(). Got {len(tasks)}."}]})
                        continue
                    if depth >= max_depth:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Already at max depth ({max_depth}). Cannot spawn further."}]})
                        continue

                    from frigate_genai.workflows.subagent import SubAgentWorkflow
                    _spawn_count += 1
                    spawn_key = f"spawn_{_spawn_count:08x}"
                    spawn_handles[spawn_key] = []
                    sd = session_input.get("subagent_dir", session_input.get("parent_agent_dir",
                         f"events/{event_id}/agent/"))

                    # ── Validate tasks ─────────────────────────────────────────
                    from frigate_genai.models import SpawnTask
                    validated_tasks = []
                    validation_errors = []
                    for i, task in enumerate(tasks):
                        try:
                            st = SpawnTask.model_validate(task)
                            validated_tasks.append(st)
                        except Exception as e:
                            validation_errors.append(f"  task[{i}]: {e}")
                    if validation_errors:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": "Spawn task validation failed:\n" + "\n".join(validation_errors)}]})
                        continue

                    # ── Resolve image refs ──────────────────────────────────────
                    all_errors: list[str] = []
                    for i, st in enumerate(validated_tasks):
                        _, errs = _resolve_image_refs(st.image_refs, sd, frames_dir=f"events/{event_id}")
                        if errs:
                            all_errors.append(f"  task[{i}]: invalid refs: {errs}")
                    if all_errors:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": "Spawn image_refs resolution failed:\n" + "\n".join(all_errors)}]})
                        continue

                    # ── Start child workflows ───────────────────────────────────
                    for i, st in enumerate(validated_tasks):
                        sub_sd = f"{sd}subagent/s{total_subagents + i}/"
                        s3_keys, _ = _resolve_image_refs(st.image_refs, sd, frames_dir=f"events/{event_id}")
                        sub_input = {
                            "event_id": event_id, "camera": camera, "label": label,
                            "task": st.task, "image_refs": st.image_refs,
                            "image_s3_keys": s3_keys,
                            "parent_agent_dir": sd, "subagent_dir": sub_sd,
                            "frames_dir": f"events/{event_id}",
                            "provider_path": provider_path, "model": model,
                        }
                        handle = workflow.start_child_workflow(
                            SubAgentWorkflow, arg=sub_input,
                            id=f"{event_id}-{sd.rstrip('/').split('/')[-1]}-{spawn_key}-{i}",
                            task_queue=genai_queue,
                        )
                        spawn_handles[spawn_key].append((tc, handle))
                    total_subagents += len(validated_tasks)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": f"Spawned {len(validated_tasks)} subagents. Key: {spawn_key}. "
                                   f"Call join(spawn_key='{spawn_key}') to collect results."}]})
                    continue

                # ── join handling ─────────────────────────────────────────────
                if tc["name"] == "join":
                    spawn_key = tc["args"]["spawn_key"]
                    if spawn_key not in spawn_handles:
                        outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                            "content": f"Unknown spawn_key: {spawn_key}"}]})
                        continue
                    findings = []
                    for _, handle in spawn_handles[spawn_key]:
                        try:
                            sub_result = await handle
                            findings.append(dict(sub_result))
                        except Exception as e:
                            findings.append({"error": str(e), "task": "unknown"})
                    fmt = _format_spawn_findings(findings)
                    outcomes.append({"messages": [{"role": "tool", "tool_call_id": tc["id"],
                        "content": fmt}]})
                    del spawn_handles[spawn_key]
                    continue

                # ── normal tool dispatch ──────────────────────────────────────
                te = {"type": "tool_call", "name": tc["name"], "args": tc.get("args", {})}
                if tc["name"] not in _TOOL_ACTIVITIES:
                    workflow.logger.warning("Unknown tool: %s", tc["name"])
                    te["error"] = f"Unknown tool: {tc['name']}"
                    trace_entries.append(te)
                    continue

                activity_fn, task_queue = _get_tool_queue(tc["name"], genai_queue)
                retry = _ACTIVITY_RETRY
                if tc["name"] == "transcode":
                    timeout = timedelta(seconds=60)
                elif tc["name"] == "upscale":
                    timeout = timedelta(seconds=180)
                else:
                    timeout = timedelta(seconds=30)

                handle = workflow.start_activity(
                    activity_fn,
                    arg={
                        "msg_path": msg_path,
                        "args": tc.get("args", {}),
                        "event_id": event_id,
                        "max_frames": max_frames,
                        "camera": camera,
                        "start_time": start_time,
                        "end_time": end_time,
                        "provider_path": provider_path,
                        "model": model,
                    },
                    task_queue=task_queue,
                    start_to_close_timeout=timeout,
                    retry_policy=retry,
                )
                handles.append((tc, te, handle))

            if handles:
                for tc, te, handle in handles:
                    try:
                        outcome = await handle
                    except Exception as e:
                        if isinstance(e, ApplicationError) and getattr(e, 'non_retryable', False):
                            workflow.logger.info("Tool %s rejected input (non-retryable): %s", tc["name"], str(e)[:120])
                        else:
                            workflow.logger.warning("Tool %s failed: %s", tc["name"], e)
                        te["error"] = str(e)[:200]
                        outcome = {
                            "messages": [
                                {"role": "tool", "tool_call_id": tc["id"],
                                 "content": f"Error: {e}"}
                            ],
                            "error": str(e)[:200],
                        }
                    # The workflow owns the exact call ID being answered. Activities
                    # may inspect stale state after another tool result is appended,
                    # so their name-based lookup cannot safely pair a response.
                    if isinstance(outcome, dict):
                        for message in outcome.get("messages", []):
                            if message.get("role") == "tool":
                                message["tool_call_id"] = tc["id"]
                    if isinstance(outcome, dict) and outcome.get("error"):
                        tool_failures += 1
                    if tc["name"] == "transcode" and isinstance(outcome, dict):
                        n = outcome.get("frames_extracted", 0)
                        turns_transcode += n
                    if isinstance(outcome, dict):
                        te.update(outcome)
                    if tc["name"] == "show_frame" and isinstance(outcome, dict):
                        res = outcome.get("resolution")
                        n_frames = outcome.get("frames_shown", 0)
                        if res in ("tiny", "low"):
                            turns_low += n_frames
                        elif res == "med":
                            turns_high += n_frames
                        elif res in ("high", "max"):
                            turns_max += n_frames
                    trace_entries.append(te)
                    outcomes.append(outcome)

            if outcomes:
                await workflow.execute_activity(
                    apply_tool_messages_activity,
                    arg={"msg_path": msg_path, "outcomes": outcomes},
                    task_queue=genai_queue,
                    start_to_close_timeout=timedelta(seconds=10),
                    retry_policy=_ACTIVITY_RETRY,
                )

            workflow.set_current_details(
                f"Turn {turn+1}/{max_turns} | "
                f"tokens: {total_cost['prompt']}+{total_cost['completion']} "
                f"(cached: {total_cost['cached']}) | "
                f"tools: {len(trace_entries)}"
            )

        if not description:
            description = f"Agentic failed: max turns ({max_turns}) exceeded without set_description"
            confidence = "low"
            workflow.logger.warning("Agent: max turns exceeded for %s", event_id)

        return {
            "description": description,
            "confidence": confidence,
            "total_cost": total_cost,
            "turns_used": turn + 1,
            "turns_low": turns_low,
            "turns_high": turns_high,
            "turns_max": turns_max,
            "turns_transcode": turns_transcode,
            "tool_failures": tool_failures,
            "trace_entries": trace_entries,
        }
