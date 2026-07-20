## Context

Depends on `dotfiles/docs/plans/2026-07-20/frigate-genai-ipc-foundation.md` and `dotfiles/docs/plans/2026-07-20/frigate-genai-ipc-interruption.md`; implementation must not start until their tests pass. This plan adds explicit adversarial analysis: after a primary agent produces a candidate finding, the outer agent may spawn a `role="red_team"` child tasked with independently trying to disprove that claim. Red-team output is structured evidence (DISPROVES, SUPPORTS, or INCONCLUSIVE verdict plus visual evidence), never an automatic truth oracle. The outer/root agent retains full authority to interpret results, request re-investigation, or spawn a tie-breaker.

## Approach

### 1. Extend task contracts with role and target fields

Edit `dotfiles/nixos/modules/frigate_genai/models.py`. Extend `SpawnTask` (currently at lines 148-152) with:

- `role: Literal["primary", "red_team"] = "primary"`
- `target_task_id: Optional[str] = None`
- `target_findings: Optional[str] = None`
- `target_confidence: Optional[Literal["high", "medium", "low", "nothing_found"]] = None`

Do not accept a caller-supplied `task_id` on `SpawnTask`. After a spawn batch passes validation, the parent assigns each launched child a deterministic `task_id = f"{spawn_key}:task:{i}"`, returns it in the spawn tool result, and propagates it through `SubAgentInput`, `SubAgentOutput`, the subagent state metadata, and the `child_registry`.

Validation rules (enforced for the entire batch before launching any child):
- A red-team task must reference a **previously completed** primary `task_id`. It cannot target a primary in the same spawn batch because that candidate result does not yet exist.
- A red-team task must include non-empty `target_findings` and `target_confidence`.
- A primary task must omit all three target fields (`target_task_id`, `target_findings`, `target_confidence`).
- Reject the entire batch with a deterministic tool error if any task violates these rules; launch no children for an invalid batch.

Preserve all existing limits: 1–5 tasks per spawn, 20 total subagents, image-ref validation with maximum 3 refs, depth limit, and `max_turns` 1–15. All previously omitted spawn propagation fields (`genai_queue`, `prompts_path`, `start_time`, `end_time`, `depth + 1`, `max_depth`, `max_turns`) must already be present from the foundation plan.

### 2. Explicit outer-agent lifecycle

The intended flow is sequential and model-directed:

1. The outer agent spawns or completes a primary analysis. It receives a candidate finding, confidence, key image refs, and deterministic `task_id`.
2. The outer agent decides whether adversarial verification is useful for this claim.
3. If useful, it spawns a separate `spawn()` call with `role="red_team"` tasks, each referencing the primary `task_id` and including the exact `target_findings`, `target_confidence`, and evidence image refs.
4. The outer agent may continue unrelated investigation but must not call `set_description` or otherwise finalize while the red-team batch is pending. The workflow returns a structured rejection if `set_description` is attempted with an unresolved red-team batch.
5. On red-team completion via `join()`, the outer agent may accept, reject, downgrade, re-investigate, send IPC steering to surviving children, or spawn a tie-breaker. The workflow provides structured evidence; it never selects the final camera description automatically.

Red-team children:
- Receive the IPC, visual tools (show_frame, crop, transcode, upscale), `compact`, and `close_subagent`.
- Do not receive `spawn` or `join` — they cannot recursively launch red-team work.
- Can message their parent via `send_ipc` using the foundation IPC tools.
- Call `close_subagent(findings, confidence, show_images)` exactly once with a VERDICT prefix.

Ordinary primary spawns with omitted `role` and target fields remain backward-compatible; no red-team logic activates for them.

### 3. Independent red-team prompt and verdict contract

In `init_subagent_state_activity` (`activities/agent_state.py:269-343`), branch on `role="red_team"`. The system prompt must:

- Identify the exact target claim from `target_findings`.
- Exclude the primary agent's reasoning beyond the claim text — the red-team agent sees only the claim, not how the primary arrived at it.
- Instruct independent inspection of only the supplied evidence.
- Require that the final `findings` string in `close_subagent` begins exactly:  
  `VERDICT: DISPROVES|SUPPORTS|INCONCLUSIVE\nEVIDENCE: <specific observable details>`
- State that high confidence is allowed only for direct visual evidence visible in the supplied frames.

The child still uses the existing `close_subagent(findings, confidence, show_images)` exactly once; `genai_turn.py:235-244` already extracts `findings`, `confidence`, and `key_images` from that call. Propagate `key_images` through `AgentSessionWorkflow` output: `genai_turn.py` returns them at line 244, but `AgentSessionWorkflow` currently discards them. Add `key_images` to `AgentSessionOutput` and pass it through `SubAgentWorkflow` to the parent so the outer agent receives the evidence refs.

Add a dedicated verdict parser function in `workflows/agent_session.py` called before `_format_spawn_findings`:
- Extract the `VERDICT:` prefix and trailing newline-separated `EVIDENCE:` block.
- A missing or malformed `VERDICT:` prefix produces `INCONCLUSIVE` with a `protocol_warning` annotation.
- Never infer stance from confidence or prose.

Preserve full red-team evidence text in aggregation output; do not apply the ordinary 200-character `findings` truncation that `_format_spawn_findings` applies to primary entries. Aggregated output groups: `[PRIMARY]`, `[RED-TEAM SUPPORTS]`, `[RED-TEAM DISPROVES]`, and `[RED-TEAM INCONCLUSIVE/FAILED]`. Each entry includes `task_id`, `target_task_id`, confidence, `subagent_id`, evidence text, and key image references so the parent can re-inspect disputed regions.

### 4. Decision and termination policy

Red-team output is advisory only:

- `DISPROVES` creates a structured conflict notice in the parent conversation and prompts the outer agent to re-inspect or use a tie-breaker. It does not automatically mark the primary as false.
- `SUPPORTS` provides corroborating evidence. It does not independently prove the primary claim or raise its confidence.
- `INCONCLUSIVE`, timeout, protocol warning, or child failure leaves the primary unverified.

Do not automatically call `set_description`, raise or lower final confidence, terminate unrelated children, or alter the camera description solely from a red-team verdict. The outer agent may explicitly send `kind="terminate"` IPC when it considers the evidence sufficient.

When a red-team child returns a terminal result (via `close_subagent` or timeout), the parent records it in the child registry and marks that batch as resolved. The parent-close invariant from the foundation plan remains mandatory: the parent cannot return from `run()` with any pending red-team child, child handle, or IPC waiter. On turn exhaustion, cancel and drain remaining children and report typed incomplete status.

### 5. Test additions

Extend `tests/test_ipc.py` with a red-team test class:

- Deterministic `task_id` assignment on valid spawn and propagation through the result and child registry.
- Rejection of same-batch red-team targeting, unknown primary `task_id`, missing target fields on red-team, and target fields on primary tasks.
- Ordinary (primary-only) spawn continues to work without red-team fields and without red-team prompts.
- Red-team children receive `close_subagent` and visual tools but not `spawn`/`join`.
- Correct prompt isolation: red-team system message references `target_findings` but no primary reasoning.
- Verdict parsing: exact `VERDICT: DISPROVES` produces `DISPROVES`; exact `VERDICT: SUPPORTS` produces `SUPPORTS`; exact `VERDICT: INCONCLUSIVE` produces `INCONCLUSIVE`; malformed or missing prefix produces `INCONCLUSIVE` with `protocol_warning`.
- Full red-team evidence text is preserved in join output (no 200-character truncation).
- `DISPROVES` produces a conflict notice in the parent conversation; `SUPPORTS` is only corroboration; `INCONCLUSIVE` remains unverified.
- Red-team child failure or timeout produces typed incomplete status.
- Outer agent can continue or spawn a tie-breaker after receiving any verdict; no automatic final description.
- `set_description` is rejected while a red-team batch is pending.
- Parent cannot exit with pending red-team children; they are cancelled/drained on turn exhaustion.
- Key images from `close_subagent` propagate through `SubAgentWorkflow` to the parent.

Run after the foundation and interruption suites pass, inside the flake-provided Python environment. Use `unittest.IsolatedAsyncioTestCase` for parser/validation tests and Temporal's `WorkflowEnvironment.start_time_skipping()` for child lifecycle/prompt/tool availability tests. If the in-process test server cannot start, use a local Temporal dev server with the same registrations; do not replace routing or lifecycle tests with import stubs.

## Critical files & anchors

1. `dotfiles/nixos/modules/frigate_genai/models.py:143-194` — existing spawn/subagent/close/join contracts to extend with role and target fields.
2. `dotfiles/nixos/modules/frigate_genai/workflows/agent_session.py:58-117,218-308` — `_format_spawn_findings`, `_get_tools_for_depth`, and spawn/join dispatch.
3. `dotfiles/nixos/modules/frigate_genai/workflows/subagent.py:13-65` — child lifecycle that must propagate `role` and `key_images`.
4. `dotfiles/nixos/modules/frigate_genai/activities/agent_state.py:269-343` — subagent state/prompt construction where the red-team prompt branch lives.
5. `dotfiles/nixos/modules/frigate_genai/activities/genai_turn.py:235-244` — `close_subagent` parsing that already returns `key_images`, which must now be propagated.

## Verification

Run from `dotfiles/nixos/modules/frigate_genai`:

```bash
python -m pytest tests/test_ipc.py tests/test_agent_session.py tests/test_worker.py tests/test_tls_config.py -v
```

Assertions required (in addition to all foundation and interruption plan assertions remaining green):
- Red-team spawn validation rejects invalid targets and propagates valid task IDs.
- Verdict parsing handles all four cases (three valid verdicts, one malformed).
- Join output groups red-team entries separately from primaries and does not truncate red-team evidence.
- `DISPROVES` produces conflict; `SUPPORTS` provides corroboration; `INCONCLUSIVE` leaves the primary unverified.
- No automatic `set_description` call or confidence change results from any verdict.
- `set_description` rejected with a red-team batch pending.
- Key images appear in the parent's join output for red-team children.
- Parent-close invariant holds: no pending red-team children at `run()` return.
- Foundation and interruption test assertions continue to pass.

## Assumptions & contingencies

- Red-team activation is explicit per spawn; no automatic red-team spawning occurs for any label or confidence threshold.
- A red-team task follows a completed primary claim and cannot target a primary in the same spawn batch.
- The outer agent retains authority to accept, reject, re-investigate, or request a tie-breaker; no verdict automatically selects the final camera description.
- Foundation star IPC routing and interruption contracts remain unchanged.
- Existing spawn limits (5 per batch, 20 total, image refs, depth, turns) apply equally to red-team tasks.
- The `key_images` fix (propagated from `genai_turn.py` through `AgentSessionWorkflow` and `SubAgentWorkflow`) is required for red-team evidence to reach the outer agent; if this propagation was partially present before, verify and reconcile rather than adding a second path.
