# Plan: Extract AgentSessionWorkflow — Turn Loop as Temporal Child Workflow

## Context

The `GenAIWorkflow.run()` is 380 lines with a monolithic `for turn in range(MAX_TURNS)` loop (lines 2168–2293). This loop is invisible in the Temporal UI, un-reusable, and blocks the parent workflow's history. Extracting it into an `AgentSessionWorkflow` child workflow gives it its own Temporal history, status, and search attributes — and creates the foundation for subagent fork/join in a later plan.

## Approach

Every change is in `nixos/modules/frigate-genai-sidecar.py`. No new behavior — pure lift.

### Step 1: Add `AgentSessionWorkflow` class

After `GenAIWorkflow` (~line 2435), add:

```python
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

        # Accumulators (moved from GenAIWorkflow lines 2157-2166)
        total_cost = {"prompt": 0, "completion": 0, "cached": 0}
        turns_low = 0
        turns_high = 0
        turns_max = 0
        turns_transcode = 0
        tool_failures = 0
        trace_entries: list[dict] = []
        description = None
        confidence = None

        turn_arg = {
            "msg_path": msg_path,
            "provider_path": provider_path,
            "model": model,
            "event_id": event_id,
            "camera": camera,
            "label": label,
        }

        for turn in range(max_turns):
            turn_arg["turn_num"] = turn + 1
            turn_arg["max_turns"] = max_turns
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

            if result.get("description"):
                description = result["description"]
                confidence = result.get("confidence", "medium")
                trace_entries.append({
                    "type": "tool_call", "name": "set_description",
                    "confidence": confidence, "description": description[:200],
                })
                break

            if result.get("text_only"):
                trace_entries.append({"type": "nudge", "reason": "no_tool_call"})
                continue

            # Parallel tool dispatch (lines 2216-2286 — moved verbatim)
            handles: list[tuple[dict, dict, object]] = []
            for tc in result.get("tool_calls", []):
                te = {"type": "tool_call", "name": tc["name"], "args": tc.get("args", {})}
                if tc["name"] not in _TOOL_ACTIVITIES:
                    workflow.logger.warning("Unknown tool: %s", tc["name"])
                    te["error"] = f"Unknown tool: {tc['name']}"
                    trace_entries.append(te)
                    continue

                activity_fn, task_queue = _get_tool_queue(tc["name"], genai_queue)
                retry = _ACTIVITY_RETRY if tc["name"] in ("transcode", "upscale") else None
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
                outcomes: list[dict] = []
                for tc, te, handle in handles:
                    outcome = await handle
                    if isinstance(outcome, dict) and outcome.get("error"):
                        tool_failures += 1
                    if tc["name"] == "transcode" and isinstance(outcome, dict):
                        turns_transcode += outcome.get("frames_extracted", 0)
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
```

### Step 2: Replace turn loop in `GenAIWorkflow.run()`

Replace lines 2148–2298 (from accumulator init through `if not description` fallthrough) with child workflow call:

```python
session_result = await workflow.execute_child_workflow(
    AgentSessionWorkflow,
    arg={
        "msg_path": msg_path,
        "provider_path": input_data["provider_path"],
        "model": model,
        "event_id": event_id,
        "camera": camera,
        "label": label,
        "max_turns": MAX_TURNS,
        "max_frames": max_frames,
        "start_time": start_time,
        "end_time": end_time,
        "genai_queue": genai_queue,
    },
    id=f"{event_id}-agent-session",
    task_queue=genai_queue,
    parent_close_policy=ParentClosePolicy.TERMINATE,
)
description = session_result.get("description")
confidence = session_result.get("confidence")
total_cost = session_result.get("total_cost", {})
turns_low = session_result.get("turns_low", 0)
turns_high = session_result.get("turns_high", 0)
turns_max = session_result.get("turns_max", 0)
turns_transcode = session_result.get("turns_transcode", 0)
tool_failures = session_result.get("tool_failures", 0)
trace_entries = session_result.get("trace_entries", [])
turn = session_result.get("turns_used", 0) - 1
```

Keep everything after `if not description` (lines 2300–2434: trace formatting, upsert memo, upsert search attributes, save_agent_log, summarize, update_description, cleanup) unchanged.

### Step 3: Register `AgentSessionWorkflow` on workers

In the triggers worker (line 2654):

```python
main_worker = Worker(
    _temporal_client,
    task_queue=TASK_QUEUE,
    workflows=[GenAIWorkflow, AgentSessionWorkflow],  # ADD AgentSessionWorkflow
    activities=misc_activities,
    deployment_config=deployment_config,
)
```

In the genai-gemini worker (line 2694) and genai-ollama worker (line 2723), add `AgentSessionWorkflow` to `workflows=[]`. Child workflows execute on the parent's task queue — every worker serving that queue needs the class.

```python
gemini_worker = Worker(
    _temporal_client,
    task_queue=GEMINI_TASK_QUEUE,
    workflows=[AgentSessionWorkflow],  # ADD
    activities=[...existing...],
    ...
)
# Same for ollama_worker
```

## Critical files

- `nixos/modules/frigate-genai-sidecar.py:2052–2434` — `GenAIWorkflow.run()`: lines 2148–2298 replaced, lines 2300–2434 kept
- `nixos/modules/frigate-genai-sidecar.py:2651–2735` — worker registration: add `AgentSessionWorkflow` to all 3 non-ffmpeg workers

## Verification

```bash
# After deploy:
# 1. Build succeeds
nix build .#frigate-genai-genai-image

# 2. AgentSessionWorkflow appears as child
temporal workflow describe -w genai-<latest> --address 192.168.5.76:32682
# Expected: shows Child Workflows: 1 → AgentSessionWorkflow

# 3. Search attributes preserved
temporal workflow list --query 'ToolFailures >= 0' --address 192.168.5.76:32682
# Expected: returns completed workflows

# 4. Frigate description written
curl -s https://frigate.john2143.com/api/events/<event_id> | jq '.description'
# Expected: description present

# 5. No regression in agent behavior
kubectl logs -n default deploy/frigate-genai-triggers-v53 --tail=50 | grep 'duration='
# Expected: normal frame extraction + GenAI processing
```

## Assumptions

- Child workflows work with Pinned WorkerDeployment versioning. Temporal child workflows inherit parent version pin. If not, pass `versioning_behavior=VersioningBehavior.PINNED` explicitly.
- `ParentClosePolicy.TERMINATE` is the right default — cancels child when parent is cancelled.
