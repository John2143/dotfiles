# Plan: Modularize frigate-genai — Python Package + Pydantic Contracts

## Context

`frigate-genai-sidecar.py` is 3106 lines in one file. Splitting into a `frigate_genai/` Python package makes it maintainable and sets up the fork/join plan. Add Pydantic `BaseModel` contracts for all workflow and activity boundaries to catch typos at deserialization time instead of runtime.

This plan depends on Plan 1 (AgentSessionWorkflow extracted). It adds zero new behavior.

## Approach

### Step 1: Add `ps.pydantic` to Nix pythonEnv

File: `nixos/modules/frigate-genai-config.nix`, line 89:

```nix
pythonEnv = pkgs.python3.withPackages (ps: [
  ps.paho-mqtt
  ps.openai
  ps.temporalio
  ps.pillow
  ps.boto3
  ps.pydantic          # ADD
]);
```

### Step 2: Create `nixos/modules/frigate-genai/models.py`

All Pydantic contracts in one file. Models use `model_config = {"extra": "forbid"}`.

```python
from pydantic import BaseModel
from typing import Optional

class GenAIWorkflowInput(BaseModel):
    event_id: str; camera: str; label: str
    start_time: float; end_time: float
    prompts_path: str; provider_path: str
    model: Optional[str] = None
    skip_frames: bool = False
    data_box: Optional[list[float]] = None

class AgentSessionInput(BaseModel):
    msg_path: str; provider_path: str; model: str
    event_id: str; camera: str; label: str
    max_turns: int; max_frames: int
    start_time: float; end_time: float
    genai_queue: str

class AgentSessionOutput(BaseModel):
    description: Optional[str] = None
    confidence: Optional[str] = None
    total_cost: dict[str, int]
    turns_used: int
    turns_low: int = 0; turns_high: int = 0
    turns_max: int = 0; turns_transcode: int = 0
    tool_failures: int = 0
    trace_entries: list[dict]

class AgentState(BaseModel):
    messages: list[dict]
    agent_dir: str; camera: str
    start_time: float = 0; end_time: float = 0
    max_frames: int = 0
    data_box: Optional[list[float]] = None
    trace: list = []
    stats: dict = {}

class GenAITurnArg(BaseModel):
    msg_path: str; provider_path: str; model: str
    event_id: str; camera: str; label: str
    turn_num: int = 1; max_turns: int = 100

class GenAITurnOutput(BaseModel):
    prompt_tokens: int = 0; completion_tokens: int = 0
    cached_tokens: int = 0
    assistant_message: Optional[dict] = None
    tool_calls: list[dict] = []
    description: Optional[str] = None
    confidence: Optional[str] = None
    text_only: bool = False

class ToolCallArg(BaseModel):
    """Unified arg dict passed to all tool activities."""
    msg_path: str; args: dict; event_id: str
    max_frames: int; camera: str
    start_time: float; end_time: float
    provider_path: str; model: str

class ToolOutcome(BaseModel):
    messages: list[dict] = []
    error: Optional[str] = None
    # Tool-specific stats — all optional:
    frames_shown: int = 0; resolution: Optional[str] = None
    frames_extracted: int = 0; fps: float = 0
    crop_region: Optional[list[int]] = None; count: int = 0
    source: Optional[str] = None
    crops_preserved: int = 0; upscales_preserved: int = 0
    strip_images_before: Optional[int] = None
    description_set: bool = False; confidence: Optional[str] = None
    snapshot_available: bool = False
    width: int = 0; height: int = 0

class ApplyToolMessagesArg(BaseModel):
    msg_path: str; outcomes: list[dict]

class InitAgentStateArg(BaseModel):
    event_id: str; camera: str; label: str
    frames_dir: str; prompts_path: str
    data_box: Optional[list[float]] = None
    start_time: float = 0; end_time: float = 0

class InitAgentStateOutput(BaseModel):
    msg_path: str; max_frames: int
```

### Step 3: Create module layout

Create `nixos/modules/frigate-genai/` with this structure. Every function moves from the current file with zero logic changes.

```
nixos/modules/frigate-genai/
├── __init__.py             # Empty
├── __main__.py             # Entry point (argparse + async_main from lines 3087–3106)
├── models.py               # All Pydantic contracts (Step 2)
├── config.py               # Constants from lines 137–157 + retry policies from 1971–1996
├── s3_helpers.py           # Functions from lines 59–131, 1870–1930
├── tools/
│   ├── __init__.py         # _TOOL_ACTIVITIES dict, _get_tool_queue
│   ├── schemas.py          # All _tool_*_schema() functions (lines 459–622)
│   ├── show_frame.py       # tool_show_frame_activity (lines 1176–1336)
│   ├── crop.py             # tool_crop_activity (lines 1398–1518)
│   ├── transcode.py        # tool_transcode_activity + _transcode_frames (lines 625–689, 1338–1396)
│   ├── upscale.py          # tool_upscale_activity (lines 1674–1782)
│   ├── compact.py          # tool_compact_activity (lines 1520–1647)
│   ├── set_description.py  # tool_set_description_activity (lines 1784–1814)
│   └── get_snapshot.py     # tool_get_snapshot_activity (lines 1146–1172)
├── activities/
│   ├── __init__.py
│   ├── agent_state.py      # init_agent_state_activity (lines 988–1126)
│   ├── genai_turn.py       # run_genai_turn_activity + _resolve_provider + _model_weights
│   │                       #   + _run_with_heartbeat (lines 697–985)
│   ├── tool_apply.py       # apply_tool_messages_activity (lines 1998–2027)
│   ├── select_model.py     # select_model_activity (lines 728–763)
│   ├── lifecycle.py        # update_description_activity, cleanup_cancelled_activity,
│   │                       #   save_agent_log_activity, summarize_agent_activity
│   │                       #   (lines 412–425, 1129–1138, 1816–1866, 1935–1967)
│   ├── frame_extraction.py # transcode_into_parts_activity, fetch_snapshot_activity,
│   │                       #   transcode_into_parts (sync), fetch_snapshot (sync)
│   │                       #   (lines 321–401, 764–826)
│   └── mqtt.py             # MQTT client, _start_workflow_sync, _build_workflow_input,
│                           #   build_mqtt_client (lines 2443–2587)
├── workflows/
│   ├── __init__.py
│   ├── genai.py            # GenAIWorkflow (lines 2052–2434, with child workflow call from Plan 1)
│   └── agent_session.py    # AgentSessionWorkflow (from Plan 1)
└── worker.py               # Worker registration for 4 modes, search attribute setup,
                            #   async_main (lines 2593–2735)
```

**The old file `nixos/modules/frigate-genai-sidecar.py` is deleted** after all contents are migrated.

### Step 4: Wire Pydantic into boundaries

At workflow boundaries (Temporal serialization):
```python
# GenAIWorkflow → AgentSessionWorkflow
child = await workflow.execute_child_workflow(
    AgentSessionWorkflow,
    arg=AgentSessionInput(
        msg_path=msg_path,
        provider_path=input_data["provider_path"],
        model=model, event_id=event_id, camera=camera, label=label,
        max_turns=MAX_TURNS, max_frames=max_frames,
        start_time=start_time, end_time=end_time,
        genai_queue=genai_queue,
    ).model_dump(exclude_none=True),
    ...
)
result = AgentSessionOutput.model_validate(session_result)
```

In activities (deserialize input, serialize output):
```python
@activity.defn(name="run_genai_turn")
async def run_genai_turn_activity(turn_dict: dict) -> dict:
    turn = GenAITurnArg.model_validate(turn_dict)
    # ... existing logic, using turn.msg_path, turn.model, etc. ...
    return GenAITurnOutput(
        prompt_tokens=prompt_tok, completion_tokens=comp_tok,
        cached_tokens=cached_tok, tool_calls=tool_calls,
        description=result.get("description"),
    ).model_dump(exclude_none=True)
```

In `_load_state` / `_atomic_write`:
```python
def _load_state(msg_path: str) -> tuple[AgentState, str]:
    data = json.loads(_s3_read_text(msg_path))
    state = AgentState.model_validate(data)
    return state, state.agent_dir
```

### Step 5: Update Nix build

File: `nixos/modules/frigate-genai-config.nix`, line 98–107:

```nix
frigateGenaiSidecarPkg = pkgs.runCommand "frigate-genai-sidecar" {
  buildInputs = [ pkgs.makeWrapper ];
} ''
  mkdir -p $out/lib/frigate_genai
  cp -r ${./frigate-genai}/* $out/lib/frigate_genai/
  makeWrapper "${pythonEnv}/bin/python" "$out/bin/frigate-genai-sidecar" \
    --add-flags "-m frigate_genai" \
    --prefix PATH : "${pkgs.ffmpeg}/bin" \
    --prefix PYTHONPATH : "$out/lib"
'';
```

Update Docker entrypoints (lines 136, 148):
```nix
config.Entrypoint = [ "${pythonEnv}/bin/python" "-m" "frigate_genai" ];
```

Update CI trigger (`.github/workflows/build-frigate-genai.yml`, line 7):
```yaml
paths:
  - nixos/modules/frigate-genai/**
```

## Critical files

- `nixos/modules/frigate-genai/models.py` — new: all Pydantic contracts
- `nixos/modules/frigate-genai/workflows/agent_session.py` — new: extracted turn loop
- `nixos/modules/frigate-genai/workflows/genai.py` — new: thin orchestrator
- `nixos/modules/frigate-genai/worker.py` — new: worker registration
- `nixos/modules/frigate-genai-config.nix:89,98–107,136,148` — add pydantic, change cp to cp -r, change entrypoint
- `nixos/modules/frigate-genai-sidecar.py` — DELETED after migration

## Verification

```bash
# 1. Build succeeds with new module layout
nix build .#frigate-genai-genai-image
# Expected: no import errors, wrapper points to -m frigate_genai

# 2. Same behavior as before module split
# After deploy, trigger an event:
kubectl logs -n default deploy/frigate-genai-triggers-v54 --tail=20 | grep 'duration='
# Expected: normal frame extraction + GenAI processing

# 3. Pydantic catches bad inputs at boundaries
# Trigger with a typo'd key (e.g. test env only):
# Expected: model_validate fails immediately with ValidationError, not silent default

# 4. Temporal UI unchanged
temporal workflow describe -w genai-<latest> --address 192.168.5.76:32682
# Expected: Child Workflows → AgentSessionWorkflow (same as Plan 1)
```

## Assumptions

- The module layout is a pure reorganization — every function body is identical, only imports change.
- `nixos/modules/frigate-genai/__main__.py` is the new entry point, importing from `.worker import async_main` and calling `async_main()` via `asyncio.run()`.
- `cp -r ${./frigate-genai}/* $out/lib/frigate_genai/` copies all modules. The `__pycache__` directories (if any) are harmless.
- Pydantic `model_validate` with `extra="forbid"` will catch typos that currently cause silent `None` defaults — this is a feature, not a bug.
