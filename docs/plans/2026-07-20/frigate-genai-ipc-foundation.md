## Context

`AgentSessionWorkflow` currently starts `SubAgentWorkflow` children via `start_child_workflow` and observes their terminal results only when the model calls `join()`. There are no workflow Signal, Update, or Query handlers anywhere in `workflows/`. The intended end state of this plan is a bidirectional parent/child star: each child can send IPC messages to its parent, the parent can send to any direct child, and siblings do not message each other directly. This plan adds durable messaging with send/wait/reply semantics, run-scoped opaque tokens, deduplication, bounded inboxes, and lifecycle cleanup. It deliberately does not promise current-turn cancellation of the model Activity; that belongs to the next plan at `dotfiles/docs/plans/2026-07-20/frigate-genai-ipc-interruption.md`.

## Approach

### 1. Add strict Pydantic contracts

Edit `dotfiles/nixos/modules/frigate_genai/models.py` using the existing `BaseFrigateModel` class with `extra="forbid"`. Add these models after the existing `JoinArgs` block:

- `IPCMessage(BaseFrigateModel)` — `message_id: str`, `from_token: str`, `to_token: str`, `kind: Literal["finding", "question", "reply", "terminate"]`, `content: str`, `confidence: Optional[Literal["high", "medium", "low", "nothing_found"]] = None`, `reply_to: Optional[str] = None`, `seq: int`, `created_at: float`.
- `SendIPCArgs(BaseFrigateModel)` — `to_token: str`, `kind` (same four literals), `content: str`, `confidence: Optional[Literal["high", "medium", "low", "nothing_found"]] = None`, `reply_to: Optional[str] = None`, `wait_for_reply: bool = False`, `timeout_seconds: int = 30`.
- `WaitIPCArgs(BaseFrigateModel)` — `message_id: Optional[str] = None`, `timeout_seconds: int = 30`.

Extend `SubAgentInput` with `parent_workflow_id: str`, `parent_run_id: str`, `parent_ipc_token: str`, `ipc_token: str`.

Extend `AgentSessionInput` with optional `ipc_token` and `parent_ipc_token`.

Validation rules (use Pydantic validators or manual checks in the dispatch layer): content is non-empty and at most 8192 UTF-8 bytes; `seq` is positive; timeout is 0–300 seconds; `kind="reply"` requires `reply_to` to be set; other kinds must omit `reply_to`. Runtime routing rejects unknown tokens, wrong run IDs, stale incarnations, closed recipients, and out-of-scope tokens.

### 2. Token format and routing contract

Use opaque token format `ipc-v1:<workflow_id>:<run_id>:<logical_agent_id>`. The run ID scopes tokens to a specific workflow execution so a reprocessed event cannot accept stale traffic. A subagent token addresses its `SubAgentWorkflow` wrapper, which forwards accepted messages to its inner `AgentSessionWorkflow`; the root token addresses the root `AgentSessionWorkflow`. Tokens are capabilities but not credentials: never include secrets and never derive them from S3 paths or display names.

The root keeps `child_registry: dict[str, dict]` mapping token → `{"workflow_id": str, "run_id": str, "handle": ChildWorkflowHandle, "status": str}`, populates it at spawn time, and exposes direct-child tokens in the spawn tool result. A child receives only `parent_ipc_token`. Parent `send_ipc` resolves `to_token` against its direct-child registry; child `send_ipc` resolves `to_token` against its stored parent token. Unknown, sibling, or arbitrary tokens return `stale_recipient` or `rejected` without retry loops.

### 3. Temporal signal, update, and query handlers

Use confirmed `temporalio 1.30.0` APIs (async Signals, async Updates, `workflow.wait_condition`, typed external workflow handles). Add to both `AgentSessionWorkflow` (in `workflows/agent_session.py`) and `SubAgentWorkflow` (in `workflows/subagent.py`):

- `@workflow.signal(name="receive_ipc") async def receive_ipc(payload: dict) -> None` — internal fire-and-forget IPC delivery. Validate token scope, reject duplicate `message_id`, reject wrong-run/stale/closed senders, enforce inbox bound of 100, append accepted messages, set inbox-change flag, and wake any matching reply/interrupt waiters. Return no value.
- `@workflow.update(name="receive_ipc_update") async def receive_ipc_update(payload: dict) -> dict` — external harness/client acknowledgement only. Perform the same validation and return `{"status": "accepted"|"duplicate"|"rejected"|"closed"|"stale", "message_id": "…"}`. Must not execute an Activity or child workflow. Internal workflows must not call `execute_update` across workflows because the Python SDK does not support that path.
- `@workflow.query(name="ipc_status") def ipc_status() -> dict` — return local token, inbox count, direct child states, waiter count, and accepted/duplicate/rejected counters. No message content.

Live IPC state is Temporal workflow state, never S3: bounded inbox of 100 accepted message dicts, dedupe set or ordered window of the latest 200 `message_id` values, monotonic sender `seq` counter, pending reply waiters keyed by `message_id`, inbox-change marker, closed flag, and child registry. Validation is deterministic and side-effect-free apart from workflow-state mutation. Duplicate `message_id` records `duplicate` status without injecting content. Inbox overflow rejects the newest message with `inbox_full` and never drops an older accepted message silently.

`SubAgentWorkflow` stores the inner `AgentSessionWorkflow` child handle before awaiting it and forwards parent-to-child messages through it. If forwarding races child completion, report `recipient_closed` and preserve the child result.

### 4. Tool schemas and workflow-level dispatch

Add `_tool_send_ipc_schema()` and `_tool_wait_ipc_schema()` to `dotfiles/nixos/modules/frigate_genai/tools/schemas.py` following the existing pattern in `_tool_join_schema()`. Import them in `workflows/agent_session.py` and in the default schema imports inside `activities/genai_turn.py`. Handle both tool names inside `AgentSessionWorkflow` before ordinary `_TOOL_ACTIVITIES` dispatch; they are workflow operations, not tool Activities.

`send_ipc` dispatch:
- Validate `SendIPCArgs` and routing scope (child-to-parent or parent-to-registered-child).
- Generate `message_id = f"{ipc_token}:{seq}"` and increment `seq` before sending.
- Send via `workflow.get_external_workflow_handle_for(AgentSessionWorkflow.run, target_wf_id).signal("receive_ipc", payload)`.
- Return structured outcome: `accepted` | `duplicate` | `recipient_closed` | `stale_recipient` | `invalid_reply` | `timeout`.
- If `wait_for_reply=False`, return immediately after server signal acceptance.
- If `wait_for_reply=True`, register a waiter keyed by the new message ID, use `workflow.wait_condition` with the supplied timeout, and return the first matching `kind="reply"` message (matched by `reply_to == original_message_id`) or `{"status": "timeout"}`. A reply is a separate `send_ipc(kind="reply", reply_to=<original_id>)`; the receiver is never assumed to reply.

`wait_ipc` dispatch:
- With `message_id`, wait for that specific reply.
- Without it, wait for any newly accepted inbox message.
- Return at most 20 messages per call; timeout returns a structured empty list.
- Never poll `messages.json` or S3.

In this foundation plan, accepted IPC messages wake waiters and are injected into the conversation at the next normal turn boundary; they do not cancel the current model Activity.

### 5. Spawn propagation fixes and lifecycle cleanup

When spawning children in `AgentSessionWorkflow` (at `workflows/agent_session.py:267-283`), compute root and child tokens before `start_child_workflow`. Also fix the currently omitted fields required by `SubAgentWorkflow`: `genai_queue`, `prompts_path`, `start_time`, `end_time`, `depth + 1`, `max_depth`, and task-specific `max_turns`. Pass parent workflow ID, run ID, and tokens through `sub_input`. Register each child in `child_registry`. Preserve current limits: maximum 5 tasks per spawn, 20 total subagents, depth limit, image-ref validation, and `max_turns` 1–15.

Before `AgentSessionWorkflow` or `SubAgentWorkflow` returns, resolve all IPC waiters with `parent_closed`, cancel every live child with `ChildWorkflowHandle.cancel()`, await each cancelled handle with `asyncio.gather(..., return_exceptions=True)`, and record typed completed/failed/timed_out/cancelled statuses in the trace. Replace the sequential join collection at `agent_session.py:298-307` with `asyncio.gather(*child_awaitables, return_exceptions=True)`, preserving input order when zipping results to handles. Do not use `asyncio.as_completed` or an unbounded per-child wait. Duplicate or unknown `join(spawn_key)` remains a deterministic tool error. Keep `ParentClosePolicy.TERMINATE` explicit on child starts.

### 6. Update test doubles and add IPC test suite

In `tests/test_agent_session.py`, extend every `setattr(schemas, name, lambda: {})` block (three occurrences) to include `"_tool_send_ipc_schema"` and `"_tool_wait_ipc_schema"`. Extend `_FakeWorkflow` to expose `signal(name, payload)`, a `signal_calls` recording list, and an inner child-handle mock supporting `.signal()`.

Create `tests/test_ipc.py` using the same import-stub/fake-workflow pattern from `test_agent_session.py`. Cover: bidirectional parent↔child routing, token/run validation, scope rejection, duplicate message ID, inbox capacity, fire-and-forget send, separate reply with optional wait, wait timeout, closed recipient, forwarding race (child already closed), concurrent partial join results, and the parent-close invariant (no live child or waiter at return). Mock `apply_tool_messages_activity` and assert the exact `[IPC from …]` prefix injection.

## Critical files & anchors

1. `dotfiles/nixos/modules/frigate_genai/workflows/agent_session.py:119-422` — turn loop, spawn/join handling, child-handle creation, and the location of the new IPC router.
2. `dotfiles/nixos/modules/frigate_genai/workflows/subagent.py:13-65` — child lifecycle that must expose receive handlers and forward IPC.
3. `dotfiles/nixos/modules/frigate_genai/models.py:143-194` — existing spawn/subagent/close/join contracts to extend.
4. `dotfiles/nixos/modules/frigate_genai/tools/schemas.py:172-241` — existing tool schema style to follow.
5. `dotfiles/nixos/modules/frigate_genai/tests/test_agent_session.py` — import-stub and `_FakeWorkflow` to extend.

## Verification

Run from `dotfiles/nixos/modules/frigate_genai`:

```bash
python -m pytest tests/test_ipc.py tests/test_agent_session.py tests/test_worker.py tests/test_tls_config.py -v
```

Assertions required:
- Valid child token delivers `finding` to parent; parent accepts it.
- Parent sends to valid child token; child accepts it.
- Repeat of same `message_id` produces `duplicate` and injects exactly once.
- 101st message is rejected with `inbox_full`; first 100 are preserved.
- `send_ipc(wait_for_reply=True)` times out with no reply, returns correct reply when reply arrives.
- `wait_ipc(timeout_seconds=5)` returns `[]` on timeout, returns messages on delivery.
- Sending to closed workflow returns `recipient_closed`.
- Sending to unknown token returns `stale_recipient` or `rejected`.
- Parent close drains all children and waiters; no live state left behind.
- Existing spawn validation, tool-call ID pairing, and TLS tests remain green.

## Assumptions & contingencies

- Temporal is pinned to `temporalio 1.30.0`; async Signals, `@workflow.update`, `workflow.wait_condition`, `get_external_workflow_handle_for`, and `ExternalWorkflowHandle.signal` are all available. If the deployed SDK differs, use string-based handler names and preserve the same wire fields; never replace routing with S3 polling.
- Internal workflow-to-workflow IPC uses Signals only; `receive_ipc_update` is an external-client Update endpoint and is never called cross-workflow. No Activity bridge is required.
- Live IPC state lives exclusively in workflow memory, not `messages.json`. S3 remains the conversation artifact store.
- Star topology only; sibling tokens and mesh routing are not supported.
- Current-turn interruption and generation fencing are explicitly deferred to `dotfiles/docs/plans/2026-07-20/frigate-genai-ipc-interruption.md`. This plan verifies that message delivery, routing, and lifecycle cleanup are correct without cancellation.
