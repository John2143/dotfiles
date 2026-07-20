## Context

Depends on `dotfiles/docs/plans/2026-07-20/frigate-genai-ipc-foundation.md`; implementation must not start until its tests pass. `run_genai_turn_activity` currently writes the assistant message directly to S3 at `activities/genai_turn.py:203-209` before returning; cancelling the workflow `await` cannot guarantee that this side effect did not occur. Therefore an IPC message that arrives during a model call cannot safely interrupt the current turn. This plan moves conversation commit ownership to the workflow and fences every result by a monotonic generation counter, making interruption a safe discard of stale proposals rather than an attempt to reverse an S3 write. The end state is that an IPC delivery during a model call cancels the stale work, injects the message, and restarts a fresh turn from the updated conversation state.

## Approach

### 1. Proposal-only GenAI activity

Refactor `run_genai_turn_activity` in `dotfiles/nixos/modules/frigate_genai/activities/genai_turn.py`.

**Keep** (unchanged): provider resolution, image deserialisation, `_run_with_heartbeat` wrapper, parser validation, pseudo thought-call filtering, tool-call ID assignment, description/confidence extraction, and key image extraction from `close_subagent` calls at lines 235-244.

**Remove** (all post-model S3 writes):
- The ordinary assistant message `_atomic_write` at line 208.
- The text-only assistant append and mandatory-tool-call nudge write at lines 186-200.
- The batched-exit rejection tool response writes at lines 251-256.

**Add** to the returned dict:
- `"assistant_message"` (already present)
- `"tool_calls"` (already present)
- `"description"`, `"confidence"`, `"key_images"` (already present for terminal calls)
- `"prompt_tokens"`, `"completion_tokens"`, `"cached_tokens"` (already present)
- `"text_only_nudge"`: when `text_only=True`, include the proposed nudge user message and the assistant message instead of writing them.
- `"batched_exit_rejections"`: a list of tool error messages for any batched `set_description`/`close_subagent` proposals, plus the assistant message, rather than writing them.
- `"turn_generation"`: the exact generation value the workflow passes in through `turn_arg`, reflected back unchanged.

The turn-limit warning (currently written at lines 101-109) is moved to the workflow: before each model call, the workflow commits the warning if the turn number reaches that threshold, passing only the state that the Activity should read. The Activity must not mutate conversation state at any point after this plan is implemented.

### 2. Workflow-owned ordered commit

In `AgentSessionWorkflow` (`workflows/agent_session.py`), add `self.turn_generation: int = 0` in `__init__`.

Turn loop changes (at `run()`, lines 168-403):
1. Before a model call, commit any pending IPC messages and pre-turn warnings to `messages.json` via `apply_tool_messages_activity`. Snapshot the current `self.turn_generation` and pass it into `turn_arg`.
2. Await `run_genai_turn_activity(turn_arg)`.
3. On return, check `result["turn_generation"]` against the current `self.turn_generation`. Any mismatch → discard the result entirely (assistant proposal, terminal description, tool calls); record `interrupted_by_ipc` or `stale_generation` in trace; do not dispatch tools.
4. On match, commit the proposed assistant message, text-only nudge, and batched-exit rejections to `messages.json` through `apply_tool_messages_activity`. The assistant message must be persisted before tool dispatch so that `_find_tc_id` in tool activities can locate the call ID.
5. Dispatch tool calls as before; apply outcomes through the single existing batch apply.

Use the helper function `_commit_turn_messages(msg_path, generation, messages)` that re-loads state, verifies a stored `turn_generation` field matches, and rejects writes with a stale generation. S3 does not provide CAS; serialization is achieved by one workflow-owned commit path and deterministic generation validation. If the generation check fails, raise a non-retryable `ApplicationError` with `stale_generation` detail.

### 3. Interruption semantics

Every accepted non-terminate IPC message delivered to `receive_ipc` increments `self.turn_generation` and sets `self.interrupt_requested = True`.

At the next await boundary (specifically: between the `execute_activity(run_genai_turn_activity)` call and tool dispatch), check `self.interrupt_requested`:
- Cancel the in-flight GenAI activity using Temporal cancellation type `TRY_CANCEL` (fixed choice) at `start_activity` time. The existing heartbeat wrapper at `activities/genai_turn.py:25-47` responds to cancellation at its next heartbeat interval; the existing `heartbeat_timeout=15s` in `agent_session.py` remains unchanged.
- Await cancellation acknowledgement required by `TRY_CANCEL`; never apply the stale result.
- Record `interrupted_by_ipc` trace entry with old generation, new generation, and accepted message IDs.
- Commit each accepted IPC message to `messages.json` exactly once with prefix `[IPC from <from_token> | <kind> | <confidence>]: <content>` and attach a separate `ipc_message_id` metadata field to the state.
- Start a fresh model turn using the updated conversation without consuming an additional investigation turn for the cancelled attempt.

If the remote HTTP call completes before cancellation could be delivered, the returned proposal is still stale (generation mismatch). If the Activity cannot be cancelled promptly, record `deferred_until_activity_completion`; generation fencing still discards the stale proposal when it eventually arrives.

Terminate messages (`kind="terminate"`) set `self.terminate_requested = True`, cancel the model activity, skip tool dispatch, cancel all active tool/child handles, drain lifecycle handles, record `terminated_by_ipc`, and return partial findings immediately without another model turn.

Tool Activities that do not heartbeat are not promised immediate cancellation. Their outputs are accepted only if the captured generation matches; stale tool outcomes are discarded from conversation, while any immutable image artifacts they wrote to S3 remain unused and must be recorded in trace entries (do not delete them speculatively).


### 4. State-write constraints

S3 `_atomic_write` at `s3_helpers.py:112-120` is an unconditional full-object `put_object`; there is no ETag, version, or CAS. Therefore there must be exactly one workflow-controlled logical writer for `messages.json`. IPC handlers never write S3. The HTTP UI at `worker.py:669-799` remains read-only. Do not introduce unrelated cleanup of `_deserialize_messages` or S3 lifecycle behavior in this plan.

### 5. Test additions

Extend `tests/test_ipc.py` with an interrupt test class using fake blocked GenAI calls controlled by `asyncio.Event`:

- IPC delivered before model completion: Activity task is cancelled; stale proposal is discarded; IPC context is injected exactly once; a fresh turn begins without consuming an extra turn count.
- Model HTTP request completes before cancellation arrives: stale proposal is discarded by generation mismatch; `deferred_until_activity_completion` is recorded; IPC is injected before the next turn.
- Termination during model call: `terminated_by_ipc` recorded; no further turns; partial findings returned.
- Text-only nudge proposal from the activity is committed only for current-generation proposals.
- Batched-exit rejection messages are committed only for current-generation proposals.
- Existing tool-call ID pairing through `_find_tc_id` works after the workflow-owned assistant commit.
- Stale tool outcomes from a cancelled generation are discarded; only current-generation tool results appear in conversation.

## Critical files & anchors

1. `dotfiles/nixos/modules/frigate_genai/activities/genai_turn.py:81-262` — current model activity with S3 side effects that must become proposal-only.
2. `dotfiles/nixos/modules/frigate_genai/workflows/agent_session.py:168-403` — turn loop where the generation fence and cancellation must be inserted.
3. `dotfiles/nixos/modules/frigate_genai/activities/tool_apply.py:10-39` — batch outcome apply path that must be generation-gated.
4. `dotfiles/nixos/modules/frigate_genai/s3_helpers.py:112-145` — `_atomic_write` and `_load_state` whose unconditional-PUT semantics drive the single-writer constraint.
5. `dotfiles/nixos/modules/frigate_genai/tests/test_agent_session.py` — `_FakeWorkflow` that must now expose cancellable handles and a generation field.

## Verification

Run from `dotfiles/nixos/modules/frigate_genai`:
- Run these tests in the flake-provided Python environment, after the foundation suite passes. Use `unittest.IsolatedAsyncioTestCase` for blocked-activity unit tests and `temporalio.testing.WorkflowEnvironment.start_time_skipping()` for workflow cancellation races; do not add `pytest-asyncio` to the production environment. If the in-process Temporal test server cannot start, use a local Temporal dev server with the same workflow and Activity registrations.

```bash
python -m pytest tests/test_ipc.py tests/test_agent_session.py tests/test_worker.py tests/test_tls_config.py -v
```

Assertions required (in addition to all foundation plan assertions remaining green):
- Blocked fake GenAI receives IPC → activity cancelled → stale proposal discarded → exactly one IPC context injected → fresh turn starts → token counter not decremented.
- Activity returns after cancellation signal delivered → generation mismatch → `deferred_until_activity_completion` or `interrupted_by_ipc` recorded → no stale assistant in state.
- `kind="terminate"` arrives during model call → activity cancelled → no further turns → `terminated_by_ipc` trace entry → partial findings returned → no live children.
- Text-only proposal from a current-generation call is committed to `messages.json` with the assistant and nudge messages.
- Batched exit rejection from a current-generation call results in tool response messages appended.
- A stale text-only proposal (wrong generation) is discarded entirely.
- A stale batched-exit rejection (wrong generation) is discarded entirely, leaving only the valid tool calls.
- Existing spawn/join, tool-call ID pairing, and dispatcher behavior remain unchanged.

## Assumptions & contingencies

- `TRY_CANCEL` is the selected Temporal activity cancellation type; it balances fast interruption with graceful fallback through generation fencing.
- Cancellation is delivered at Temporal cancellation points (heartbeat boundaries for `run_genai_turn_activity`). A completed remote HTTP request cannot be undone; the stale proposal is discarded by generation fencing, not by cancellation.
- S3 `_atomic_write` remains unconditional; the `_commit_turn_messages` helper rejects writes when the expected generation is stale rather than introducing concurrency primitives.
- Foundation plan routing, token, and lifecycle contracts remain unchanged. No structural edits to IPC handlers are required.
- If a deployed Temporal SDK version lacks `activity_cancellation_type` on `start_activity`, fall back to `WAIT_CANCELLATION_COMPLETED` (the SDK default) and accept the longer wait; generation fencing still prevents stale context.
