# Plan: Agent Spawn/Join — SubAgentWorkflow + close_subagent

## Context

Plan 1 extracted the turn loop into `AgentSessionWorkflow`. Plan 2 modularized into a Python package with Pydantic contracts. This plan adds the ability for an agent to `spawn()` parallel subagents, `join()` their results, and subagents to `close_subagent()` to return findings. No symmetric `fork()` (clone-then-diverge) — Unix teaches us `spawn` with explicit task+context is the practical pattern.

## Approach

### New Concepts

- **`spawn(tasks[])`** — tool call that launches N `SubAgentWorkflow` children in parallel. Each subagent gets its own task, context frames, and S3 state directory. Non-blocking: returns immediately with a `spawn_key`.
- **`join(spawn_key)`** — blocks until all subagents from the spawn call `close_subagent()`. Collects all findings into a formatted message in the parent's conversation.
- **`close_subagent(findings, confidence)`** — subagent tool call that terminates the subagent and returns findings to the spawner. Replaces `set_description` for subagents. The parent's `join()` unblocks when all subagents have closed.
- **`spawn_key`** — unique identifier for a spawn batch. Format: `"spawn://" + 8 hex chars`. Used in `join()`.

### Data Models

File: `nixos/modules/frigate-genai/models.py`

```python
class SpawnArgs(BaseModel):
    """Nested inside ToolCallArg.args for spawn() tool calls."""
    tasks: list[SpawnTask]

class SpawnTask(BaseModel):
    task: str                          # e.g. "Read license plate on crop://3"
    image_refs: list[str]              # ["crop://3@max", "frame://45@high"]
    max_turns: int = 8

class SubAgentInput(BaseModel):
    """Input to SubAgentWorkflow. Built by spawn handler."""
    event_id: str; camera: str; label: str
    task: str; image_refs: list[str]
    image_s3_keys: list[str] = []      # Resolved S3 keys for init
    parent_agent_dir: str              # "events/{eid}/agent/"
    subagent_dir: str                  # "events/{eid}/agent/subagent/s0/"
    provider_path: str; model: str
    genai_queue: str; prompts_path: str
    start_time: float; end_time: float
    depth: int = 1; max_depth: int = 2
    max_turns: int = 8

class SubAgentOutput(BaseModel):
    """Returned when subagent calls close_subagent()."""
    findings: Optional[str] = None
    confidence: Optional[str] = None
    turns_used: int = 0
    total_cost: dict[str, int]
    key_images: list[dict] = []        # [{"ref": "crop://2", "s3_key": "...", "label": "plate"}]
    tool_failures: int = 0
    subagent_id: str; task: str

class CloseSubagentArgs(BaseModel):
    findings: str
    confidence: str                    # "high"|"medium"|"low"|"nothing_found"
    show_images: list[str] = []

class JoinArgs(BaseModel):
    spawn_key: str                     # "spawn://abc12345"
```

### Step 1: Add tool schemas

File: `nixos/modules/frigate-genai/tools/schemas.py`

```python
def _tool_spawn_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "spawn",
            "description": (
                "Spawn parallel subagents to investigate different regions simultaneously. "
                "Each subagent gets its own context and runs independently. Call join() to "
                "collect results when ready. Subagents can show_frame, crop, transcode, and "
                "upscale. Max 5 subagents per spawn, max depth 2."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tasks": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "task": {"type": "string", "description": "Precise task."},
                                "image_refs": {"type": "array", "items": {"type": "string"},
                                    "description": "Images to pre-load. Max 3 per subagent."},
                                "max_turns": {"type": "integer",
                                    "description": "Turn budget (default 8, max 15)."},
                            },
                            "required": ["task"],
                        },
                        "description": "Tasks to spawn. Each becomes a parallel subagent.",
                    },
                },
                "required": ["tasks"],
            },
        },
    }

def _tool_join_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "join",
            "description": (
                "Collect results from a spawn(). BLOCKS until ALL spawned subagents "
                "call close_subagent(). Returns formatted findings from each subagent. "
                "Join each spawn_key exactly once."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "spawn_key": {"type": "string",
                        "description": "The spawn_key returned by spawn()."},
                },
                "required": ["spawn_key"],
            },
        },
    }

def _tool_close_subagent_schema() -> dict:
    return {
        "type": "function",
        "function": {
            "name": "close_subagent",
            "description": (
                "Terminate this subagent and return findings. Call when investigation "
                "is complete. Confidence: high=certain, medium=probable, low=unclear, "
                "nothing_found=searched thoroughly."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "findings": {"type": "string",
                        "description": "Complete findings with specific details."},
                    "confidence": {"type": "string",
                        "enum": ["high","medium","low","nothing_found"]},
                    "show_images": {"type": "array", "items": {"type": "string"},
                        "description": "Optional image refs to show parent. Max 2."},
                },
                "required": ["findings", "confidence"],
            },
        },
    }
```

### Step 2: Add `init_subagent_state_activity`

File: `nixos/modules/frigate-genai/activities/agent_state.py`

```python
@activity.defn(name="init_subagent_state")
async def init_subagent_state_activity(init_arg: dict) -> dict:
    """Initialize subagent: copy parent images, compose task-focused prompt,
    seed messages, write messages.json."""
    task = init_arg["task"]
    camera = init_arg["camera"]
    label = init_arg["label"]
    subagent_dir = init_arg["subagent_dir"]

    # Copy parent images to subagent directory
    display_files = []
    for i, s3_key in enumerate(init_arg.get("image_s3_keys", [])):
        raw = _s3_get(s3_key)
        if raw:
            dname = f"display_{i+1:03d}.jpg"
            _s3_put(f"{subagent_dir}{dname}", raw)
            display_files.append(dname)

    # Build focused system prompt
    prompts = load_json(init_arg["prompts_path"])
    label_hint = prompts.get("label", {}).get(label, "")
    system_prompt = (
        "You are a focused analysis subagent. Your task was delegated. "
        "Use show_frame, crop, transcode, and upscale to examine evidence. "
        f"Task: {task}\n"
        + (f"{label_hint}\n" if label_hint else "")
        + f"Max turns: {init_arg['max_turns']}. Work efficiently.\n"
        "Call close_subagent(findings, confidence) when done."
    )

    # Seed messages
    content_parts = []
    for dname in display_files:
        content_parts.append({"type": "image_url", "image_url": {"url": f"[[{dname}]]"}})
    content_parts.append({"type": "text", "text": f"Task: {task}\n\nInvestigate and call close_subagent() when complete."})

    init_messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": content_parts},
    ]

    msg_path = f"{subagent_dir}messages.json"
    state = {
        "messages": init_messages,
        "agent_dir": subagent_dir,
        "camera": camera,
        "start_time": init_arg.get("start_time", 0),
        "end_time": init_arg.get("end_time", 0),
        "max_frames": 0,
        "data_box": None,
        "trace": [],
        "stats": {},
        "task": task,
        "subagent_id": subagent_dir.rstrip("/").split("/")[-1],
        "key_images": [],
    }
    _atomic_write(msg_path, state)
    return {"msg_path": msg_path}
```

### Step 3: Create `SubAgentWorkflow`

File: `nixos/modules/frigate-genai/workflows/subagent.py`

```python
@workflow.defn
class SubAgentWorkflow:
    """Subagent lifecycle: init state → run turn loop → return findings."""

    @workflow.run
    async def run(self, sub_input: dict) -> dict:
        # 1. Initialize subagent state
        init = await workflow.execute_activity(
            init_subagent_state_activity,
            arg=sub_input,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=_ACTIVITY_RETRY,
        )

        # 2. Delegate to AgentSessionWorkflow
        session = await workflow.execute_child_workflow(
            AgentSessionWorkflow,
            arg={
                "msg_path": init["msg_path"],
                "provider_path": sub_input["provider_path"],
                "model": sub_input["model"],
                "event_id": sub_input["event_id"],
                "camera": sub_input["camera"],
                "label": sub_input["label"],
                "max_turns": sub_input["max_turns"],
                "max_frames": 0,
                "start_time": sub_input["start_time"],
                "end_time": sub_input["end_time"],
                "genai_queue": sub_input["genai_queue"],
            },
            id=f"{sub_input['event_id']}-sub-{sub_input.get('subagent_dir','').rstrip('/').split('/')[-1]}",
            task_queue=sub_input["genai_queue"],
            parent_close_policy=ParentClosePolicy.TERMINATE,
        )

        # 3. Return findings to spawner
        return {
            "findings": session.get("description"),
            "confidence": session.get("confidence"),
            "turns_used": session.get("turns_used", 0),
            "total_cost": session.get("total_cost", {}),
            "key_images": session.get("key_images", []),
            "tool_failures": session.get("tool_failures", 0),
            "subagent_id": sub_input.get("subagent_dir", "").rstrip("/").split("/")[-1],
            "task": sub_input.get("task", ""),
        }
```

### Step 4: Handle `close_subagent` in `run_genai_turn_activity`

File: `nixos/modules/frigate-genai/activities/genai_turn.py`

Add `close_subagent` parsing alongside existing `set_description` parsing. When a tool call named `close_subagent` is detected:

```python
if tc.function.name == "close_subagent":
    args = json.loads(tc.function.arguments)
    result["description"] = args.get("findings", "")
    result["confidence"] = args.get("confidence", "medium")
    result["key_images"] = args.get("show_images", [])
    result["close_subagent"] = True  # Signal to AgentSessionWorkflow
    # Don't add to tool_calls — it's not an activity, it's a loop exit
    continue  # Skip adding to tool_calls list
```

Guard: if `close_subagent` is called alongside other tools, strip it and inject a tool message ("review results before closing").

### Step 5: Add spawn/join interception in `AgentSessionWorkflow`

File: `nixos/modules/frigate-genai/workflows/agent_session.py`

In the tool dispatch phase, before normal tool dispatch:

```python
spawn_handles: dict[str, list[tuple[dict, object]]] = {}  # spawn_key → [(tc, handle), ...]

for tc in result.get("tool_calls", []):
    if tc["name"] == "spawn":
        tasks = tc["args"].get("tasks", [])
        if len(tasks) > MAX_CONCURRENT_SPAWNS:
            outcomes.append(_spawn_error(tc, f"max {MAX_CONCURRENT_SPAWNS} subagents"))
            continue

        spawn_key = f"spawn://{uuid4().hex[:8]}"
        spawn_handles[spawn_key] = []

        for i, task in enumerate(tasks):
            sub_dir = f"{parent_agent_dir}subagent/s{len(spawn_handles)}/"
            sub_input = SubAgentInput(
                event_id=event_id, camera=camera, label=label,
                task=task["task"],
                image_refs=task.get("image_refs", []),
                image_s3_keys=_resolve_image_refs(task.get("image_refs", []), parent_agent_dir),
                parent_agent_dir=parent_agent_dir,
                subagent_dir=sub_dir,
                provider_path=provider_path, model=model,
                genai_queue=genai_queue, prompts_path=prompts_path,
                start_time=start_time, end_time=end_time,
                depth=1, max_depth=MAX_SUBAGENT_DEPTH,
                max_turns=task.get("max_turns", MAX_SUBAGENT_TURNS),
            )
            handle = workflow.start_child_workflow(
                SubAgentWorkflow, arg=sub_input.model_dump(exclude_none=True),
                id=f"{event_id}-{spawn_key}-{i}",
                task_queue=genai_queue,
            )
            spawn_handles[spawn_key].append((tc, handle))

        # Return spawn_key to parent
        outcomes.append({
            "messages": [{"role": "tool", "tool_call_id": tc["id"],
                "content": f"Spawned {len(tasks)} subagents. Key: {spawn_key}. "
                           f"Call join(spawn_key='{spawn_key}') to collect results."}],
            "spawn_key": spawn_key,
        })
        continue

    if tc["name"] == "join":
        spawn_key = tc["args"]["spawn_key"]
        if spawn_key not in spawn_handles:
            outcomes.append(_spawn_error(tc, f"Unknown spawn_key: {spawn_key}"))
            continue

        # Block until all subagents complete
        findings = []
        for tc_orig, handle in spawn_handles[spawn_key]:
            try:
                sub_result = await handle
                findings.append(sub_result)
            except Exception as e:
                findings.append({"error": str(e), "task": "unknown"})

        # Format subagent findings for parent
        outcomes.append(_format_spawn_findings(findings, spawn_key))
        del spawn_handles[spawn_key]
        continue

    # Normal tool dispatch via _TOOL_ACTIVITIES (unchanged)
```

### Step 6: Add tool gating by depth

In `AgentSessionWorkflow`, the tools list passed to `run_genai_turn_activity` filters by depth:

```python
def _get_tools_for_depth(depth: int, max_depth: int) -> list[dict]:
    base = ALL_TOOL_SCHEMAS  # All 7 existing tools
    if depth == 0:
        return base + [SPAWN_SCHEMA, JOIN_SCHEMA]
    elif depth < max_depth - 1:
        # Subagent: no set_description, no compact, no get_snapshot
        # Uses close_subagent instead. Can spawn sub-sub-agents.
        return [s for s in base if s["function"]["name"]
                not in ("set_description", "compact", "get_snapshot")] \
               + [CLOSE_SUBAGENT_SCHEMA, SPAWN_SCHEMA, JOIN_SCHEMA]
    else:
        # Deepest: no spawn, no join
        return [s for s in base if s["function"]["name"]
                not in ("set_description", "compact", "get_snapshot")] \
               + [CLOSE_SUBAGENT_SCHEMA]
```

### Step 7: Register `SubAgentWorkflow` on workers

File: `nixos/modules/frigate-genai/worker.py`

All three non-ffmpeg workers:

```python
workflows=[GenAIWorkflow, AgentSessionWorkflow, SubAgentWorkflow]
```

### Step 8: Spawn prompt guidance

Add to `init_agent_state_activity` system prompt (root agent only):

```
SPAWN/JOIN — PARALLEL SUBAGENTS:
You can spawn() parallel subagents to investigate different regions simultaneously.
Each subagent gets its own context and runs independently. Use spawn when:
- Multiple distinct regions need inspection (plates, faces, text)
- Different time windows need scanning
- Detail extraction that would consume many turns
Rules:
- spawn() returns a spawn_key immediately. Subagents run in background.
- call join(spawn_key) to collect results. BLOCKS until all complete.
- join() returns formatted findings from each subagent.
- Max 5 subagents per spawn.
- Only spawn() when you have specific tasks — don't spawn for trivial checks.
```

## Critical files

- `nixos/modules/frigate-genai/models.py` — new: SpawnArgs, SubAgentInput, SubAgentOutput, CloseSubagentArgs, JoinArgs
- `nixos/modules/frigate-genai/tools/schemas.py` — new: spawn, join, close_subagent schemas
- `nixos/modules/frigate-genai/activities/agent_state.py` — new: init_subagent_state_activity
- `nixos/modules/frigate-genai/activities/genai_turn.py` — modify: close_subagent parsing
- `nixos/modules/frigate-genai/workflows/agent_session.py` — modify: spawn/join interception, tool gating
- `nixos/modules/frigate-genai/workflows/subagent.py` — new: SubAgentWorkflow
- `nixos/modules/frigate-genai/worker.py` — modify: register SubAgentWorkflow

## Verification

```bash
# After deploy:
# 1. Temporal UI shows SubAgentWorkflow children
temporal workflow describe -w genai-<latest> --address 192.168.5.76:32682
# Expected: Child Workflows shows SubAgentWorkflow instances

# 2. spawn/join produces findings
# Trigger event with multiple objects (car + person)
# Check completed workflow's description:
curl -s https://frigate.john2143.com/api/events/<event_id> | jq '.description'
# Expected: description includes subagent findings

# 3. Subagent search attributes
temporal workflow list --query 'SubagentDepth >= 1' --address 192.168.5.76:32682
# Expected: returns subagent workflows

# 4. Recursive spawn (subagent spawns sub-sub-agent)
temporal workflow list --query 'SubagentDepth = 2' --address 192.168.5.76:32682
# Expected: returns depth-2 workflows (rare — requires specific event)

# 5. Max depth limits apply
# Subagent at max_depth should NOT have spawn in tools schema
# Verified by: subagent runs, calls close_subagent() without spawning
```

## Assumptions

- Subagent uses `close_subagent` to exit the loop. `run_genai_turn_activity` treats it like `set_description` — sets `result["description"]` and breaks loop. Guard: if called alongside other tools, strip it.
- `spawn()` is non-blocking: returns spawn_key immediately. Parent continues its turn loop. `join()` blocks. Unjoined spawns are auto-cancelled when parent calls `set_description()`.
- All 7 existing tools work unchanged for subagents — they read from their own `messages.json` via `msg_path`.
- Subagent gets focused task prompt (no two-phase protocol, no camera description, no forensics persona). Minimal, task-focused.
- Max depth: 2 (root → subagent → sub-sub-agent). Max concurrent spawns: 5. Max total subagents per event: 20.
- `fork()` (symmetric clone) is NOT included. If needed later, it can be added as a variant of spawn that passes the full parent context instead of a task-specific subset.
