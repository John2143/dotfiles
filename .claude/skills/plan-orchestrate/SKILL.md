---
description: "Autonomously execute subplans from a big-plan directory, one atomic unit per loop iteration, using a state machine with terminal states and invariant checks"
argument-hint: '<path-to-plan-dir>'
allowed-tools: Read, Write, Edit, Bash, Task, Search, Find
tool-hints: |
  Use `omp launch -p "$(cat plan-X.md)" --no-session` to dispatch sub-agents.
  Use the plan dir for the state file; print its path on every update.
  Use Bash `sleep <seconds>` to pause between iterations; use `exit_loop_mode(summary)` to stop permanently. <!-- changed -->
  Use `exit_loop_mode(summary)` to stop permanently. Only available in /loop mode.
  Verify tool availability before dispatching: `which omp` — if missing, `exit_loop_mode("IMPOSSIBLE: omp CLI not found")`. <!-- changed -->
  Do not ask questions — unattended loop prompt.
---

## Usage

**Invocation:** `/loop` → starts harness → `/skill:plan-orchestrate <path-to-plan-dir>`

- `<path-to-plan-dir>` — Path to a big-plan output directory containing `Index.md`, `plan-*.md`, and `original-prompt.md`.
- If the path is missing, the skill checks session context for a previously-stated plan directory **or** the last `ORCHESTRATE STATEFILE:` line printed by a prior iteration (the parent directory of that path is `$PLAN_DIR`). <!-- changed -->
- If still nothing: reports usage and calls `exit_loop_mode('no plan directory')`.

**Example workflow:**
```
/skill:big-plan "Add authentication middleware to all API endpoints"
  → creates /tmp/ai-plan-dotfiles-aBcDeF/ with plan-*.md and Index.md

/loop
  /skill:plan-orchestrate /tmp/ai-plan-dotfiles-aBcDeF/
  → harness calls plan-orchestrate repeatedly
  → each invocation executes one state, updates state file, stops
  → when all plans done: exit_loop_mode("DONE: 3 plans completed")
```

Parse `$ARGUMENTS`:
- Single positional argument is `$PLAN_DIR` — path to a big-plan output directory (contains `Index.md`, `plan-*.md`, `original-prompt.md`).
- If missing, check session context for a previously-stated plan directory path, or recover from the last printed `ORCHESTRATE STATEFILE:` line (parent of that path is `$PLAN_DIR`). <!-- changed -->
- If still nothing: report "No plan directory provided. Usage: /skill:plan-orchestrate <path-to-plan-dir>" and call `exit_loop_mode('no plan directory')`.

---

## One-line purpose

Your job is to autonomously execute every subplan in a big-plan directory, one atomic unit of work per loop iteration, tracking progress in a state machine until all plans complete or the task is blocked.

## Terminology <!-- changed -->

- **slug** — the basename of a plan file without the `.md` extension. `plan-waybar-styling.md` → slug `plan-waybar-styling`. Slugs are the keys in `plans` and the targets of `dependencies`. <!-- changed -->
- **active plan** — the slug currently executing under `omp launch`, recorded in `active_plan`. At most one at a time. <!-- changed -->

## Key files

| File | Role |
|------|------|
| `$PLAN_DIR/orchestrate_state.json` | State machine: states, transitions, plan queue, history, iteration count. Your only memory across loop iterations. |
| `$PLAN_DIR/Index.md` | Dependency graph, overall goal, verification criteria. Written by big-plan. Read-only. |
| `$PLAN_DIR/original-prompt.md` | Original user prompt. Read-only context. |
| `$PLAN_DIR/plan-*.md` | Individual subplans to execute. Read-only; dispatched via `omp launch`. |
| `$PLAN_DIR/results/{slug}-output.md` | Output artifacts from completed sub-agents. Written by sub-agents, verified by orchestrator. |

## How to start each session

**This is a loop prompt.** The `/loop` harness calls you repeatedly with no arguments. Each invocation does exactly one atomic unit of work, then stops. The state file is your only memory across iterations. OMP will auto-compact your context window when it grows too large — this is expected and safe because you re-read the state file fresh each invocation.

### Hard session-boundary rule

1. Locate `$PLAN_DIR/orchestrate_state.json`. If it does not exist, this is the first invocation — follow state **`init`**.
2. Read the `current_state` field. Determine which single state to execute:

   | `current_state` | Execute |
   |---|---|
   | _(no file)_ | `init` |
   | `dispatch_next` | `dispatch_next` |
   | `monitor_execution` | `monitor_execution` |
   | `verify_output` | `verify_output` |
   | `handle_failure` | `handle_failure` |
   | _(anything else, including `init`)_ | `unknown` <!-- changed -->

3. Execute that one state. When its instructions say **STOP**, stop immediately.

### What "STOP" means

After completing a state, your only remaining actions are:
- Confirm the state file was written.
- Print the state file path: `echo "ORCHESTRATE STATEFILE: $PLAN_DIR/orchestrate_state.json"`

You **must not** read the next state's instructions. You **must not** evaluate whether the next step could also be done. You **must not** scroll past the STOP line in this SKILL.md.

### Anti-pattern: "the user is waiting"

> "The user is in a conversation with me right now. They probably expect me to complete all plans in this session."

That reasoning is always wrong. This is a loop prompt. Each invocation does one state. Chaining states defeats context-window isolation and produces sloppy execution. Delivering one clean atomic step per invocation is how you serve the user best.

### Anti-pattern: "I'll just check the next section"

Do not scroll past the STOP line to see what the next state requires. If you do, you have already violated the boundary. The state file is the only link between sessions — not your memory of the next step.

### Anti-pattern: "Let me archive the old project so it resets"

When all plans are `done`:
> "The user keeps re-invoking. They must want fresh work. Let me `mv` the directory and restart."

Never do this. The state file is the authority. If all plans are done, you call `exit_loop_mode` and stop. You do not rename directories or try to "fix" a finished project. If the user wants fresh plans, they will run big-plan again.

## How to work

### State file format

Write and read the state file as a JSON object using `read` and `write` tools. **Rewrite the entire file atomically on every update** — never edit individual lines. A partially written state file means starting over.

Plan `status` is one of: `pending`, `in_progress`, `done`, `failed`, `failed_permanent`. <!-- changed -->

```json
{
  "plan_dir": "/tmp/ai-plan-dotfiles-aBcDeF",
  "goal": "<from Index.md>",
  "created": "<ISO timestamp>",
  "updated": "<ISO timestamp>",
  "current_state": "dispatch_next",
  "iteration": 12,
  "max_iterations": 200,
  "plans": {
    "plan-waybar-styling": {
      "status": "done",
      "dependencies": ["plan-media-animations"],
      "output_file": "results/plan-waybar-styling-output.md",
      "retries": 0,
      "verified": true,
      "dispatched_at": null,
      "completed_at": "2026-05-24T14:32:00"
    },
    "plan-hyprland-workspaces": {
      "status": "pending",
      "dependencies": [],
      "output_file": "results/plan-hyprland-workspaces-output.md",
      "retries": 0,
      "verified": false,
      "dispatched_at": null,
      "completed_at": null
    }
  },
  "active_plan": null,
  "history": [
    {"iteration": 11, "state": "verify_output", "slug": "plan-waybar-styling", "event": "verified", "at": "2026-05-24T14:33:01", "note": "output file present, all criteria met"}
  ]
}
```

`history` entries are objects with `iteration`, `state`, optional `slug`, `event`, ISO `at`, and a short free-text `note`. Append-only; never rewrite past entries. <!-- changed -->

The state machine definitions live in this SKILL.md — they are **not** stored in the state file. Do not add a `states` key. <!-- changed -->

### State: `init`

**Purpose**: First invocation only. Read the big-plan directory, initialize the state machine.

1. Verify `$PLAN_DIR` exists and contains `Index.md`. If not: call `exit_loop_mode("IMPOSSIBLE: not a valid plan directory — missing Index.md")`.
2. If `$PLAN_DIR/orchestrate_state.json` already exists, do **not** overwrite it. This means the session-boundary rule misrouted to `init`. Transition to `unknown` so the inconsistency is diagnosed deliberately, then **STOP**. <!-- changed -->
3. Read `Index.md` to extract: overall goal, plan list, dependencies.
4. Read `original-prompt.md` for context.
5. Enumerate all `plan-*.md` files in `$PLAN_DIR`. For each plan, determine its dependencies from the Index.md Dependencies section. If a plan is listed in Index.md but the file doesn't exist: mark it `failed_permanent` immediately with note "plan file missing." <!-- changed -->
6. Create the `results/` subdirectory: `mkdir -p "$PLAN_DIR/results/"`. <!-- changed -->
7. Write the initial state file with: <!-- changed -->
   - `plan_dir`, `goal`, `created`, `updated` populated
   - `plans` populated from discovered plan files (all `status: "pending"` unless missing)
   - `current_state: "dispatch_next"`
   - `iteration: 0`, `max_iterations: 200`
   - `active_plan: null`
   - `history: []`
8. Print: `echo "ORCHESTRATE STATEFILE: $PLAN_DIR/orchestrate_state.json"` <!-- changed -->
9. **STOP.** The state file now reads `current_state: "dispatch_next"`. Do not read the `dispatch_next` section. The harness will re-invoke you. <!-- changed -->

### State: `dispatch_next`

**Purpose**: Pick the next executable plan and launch its sub-agent.

1. Read `orchestrate_state.json`. Check iteration budget: if `iteration >= max_iterations`, call `exit_loop_mode("TIMEOUT: max_iterations reached")`.
2. Verify `omp` is available: `which omp`. If missing, call `exit_loop_mode("IMPOSSIBLE: omp CLI not found — cannot dispatch sub-agents")`.
3. Find the next pending plan whose dependencies are all `verified: true`. Scan `plans` for `status: "pending"` where every slug in `dependencies` has `status: "done"` AND `verified: true`.
4. If no executable plan found but some are `pending` (blocked on dependencies):
   - `bash sleep 30 # waiting for dependencies to complete` then **STOP**.
5. If no executable plan found and none are `pending` (all are `done` or `failed`):
   - If any `failed` with `retries < 3`: set those back to `pending`, increment `retries`, atomically rewrite state file, print STATEFILE path, **STOP.** (Next iteration picks them up.) <!-- changed -->
   - If all `done` and `verified: true`: call `exit_loop_mode("DONE: N plans completed successfully. Plan dir: $PLAN_DIR")`. Terminals are not states — do **not** write `terminal_done` (or any terminal name) as `current_state`. <!-- changed -->
   - If all `failed_permanent` with retries exhausted: call `exit_loop_mode("BLOCKED: all plans failed after max retries")`.
6. Pick the next executable plan. Set `active_plan` to its slug, set `status: "in_progress"`, set `dispatched_at` to current ISO timestamp.
7. Read the plan file at `$PLAN_DIR/{slug}.md` to confirm it exists and is non-empty.
8. Launch the sub-agent:
   ```bash
   omp launch -p "$(cat "$PLAN_DIR/{slug}.md")" --no-session
   ```
   The sub-agent reads the plan (which includes file paths and output instructions), executes it, and writes output to the path specified in the plan's `## Output` section. The orchestrator does NOT pass additional context — the plan file is self-contained. <!-- changed -->
9. Append a `history` entry: `{state: "dispatch_next", slug, event: "dispatched", at: <ISO>}`. <!-- changed -->
10. Increment `iteration`. Set `current_state: "monitor_execution"`. Atomically rewrite state file.
11. Print: `echo "ORCHESTRATE STATEFILE: $PLAN_DIR/orchestrate_state.json"`
12. **STOP.** Do not wait for the sub-agent. The harness will re-invoke you for monitoring.

### State: `monitor_execution`

**Purpose**: Check if the dispatched sub-agent completed.

1. Read `orchestrate_state.json`. Read `active_plan` to identify which plan is running.
2. Check for the expected output file at `$PLAN_DIR/{output_file}` (from the plan's `output_file` field in state).
3. **If the file exists and is non-empty:**
   - Set `status: "done"` for the active plan.
   - Set `completed_at` to current ISO timestamp.
   - Set `active_plan: null`.
   - Set `current_state: "verify_output"`.
   - Append `history` entry: `{state: "monitor_execution", slug, event: "output_observed", at: <ISO>, note: <output_file path>}`. <!-- changed -->
   - Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->
4. **If the file does not exist:** evaluate elapsed time since `dispatched_at`: <!-- changed -->
   - **< 5 minutes:** the sub-agent is likely still running. `bash sleep 60 # sub-agent still running — {slug}`, then **STOP**.
   - **5–10 minutes:** still within tolerance but suspicious. `bash sleep 120 # sub-agent slow — {slug}, elapsed {N}m`, then **STOP**. <!-- changed -->
   - **> 10 minutes:** the sub-agent likely crashed or stalled. Continue to step 5. <!-- changed -->
5. Confirm the sub-agent is gone before declaring failure: `pgrep -f "omp launch.*{slug}"`. If a process is still found, `bash sleep 120 # sub-agent process still alive past timeout — {slug}`, then **STOP**. `pgrep` is a secondary heuristic only — the primary signal is the missing output file past 10 minutes. <!-- changed -->
6. Set `status: "failed"`, set `active_plan: null`, set `current_state: "handle_failure"`. <!-- changed -->
7. Append `history` entry: `{state: "monitor_execution", slug, event: "no_output_after_timeout", at: <ISO>, note: "elapsed >10m, no output file"}`. <!-- changed -->
8. Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->

### State: `verify_output`

**Purpose**: Verify the sub-agent's output against the plan's criteria.

1. Read `orchestrate_state.json`. Identify the most recently completed plan (the one that just transitioned from `in_progress` → `done`).
2. Read the plan file at `$PLAN_DIR/{slug}.md` and the output file at `$PLAN_DIR/{output_file}`.
3. Check the plan's `## Output` section. Verify each criterion:
   - **Existence**: Does the output file contain the specified artifacts?
   - **File modifications**: If the plan specified file changes, do those files show the expected modifications? (Read the target files in the repo.)
   - **Report structure**: If the plan specified a report format, does the output have the required sections?
   - **Verification commands**: If the plan specified commands to verify correctness (e.g., `cargo test`, `nix flake check`), run them and check exit codes.
   - **Fallback when `## Output` is absent or empty**: treat success as "output file exists, is non-empty, and contains no obvious error sentinel (`PANIC`, `Traceback`, `error:` at column 0)". Record this fallback in the history `note`. <!-- changed -->
4. **If verification passes:**
   - Set `verified: true` for this plan.
   - Append `history` entry: `{state: "verify_output", slug, event: "verified", at: <ISO>, note: <one-line summary>}`. <!-- changed -->
   - Set `current_state: "dispatch_next"`.
   - Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->
5. **If verification fails:**
   - Set `status: "failed"` for this plan.
   - Append `history` entry: `{state: "verify_output", slug, event: "verification_failed", at: <ISO>, note: <specific criteria that failed>}`. <!-- changed -->
   - Set `current_state: "handle_failure"`.
   - Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->

### State: `handle_failure`

**Purpose**: Diagnose and decide whether to retry or escalate.

1. Read `orchestrate_state.json`. Identify the failed plan.
2. Check `retries` for this plan:
   - If `retries >= 3`:
     - Mark `status: "failed_permanent"`.
     - Append `history` entry: `{state: "handle_failure", slug, event: "failed_permanent", at: <ISO>, note: <diagnosis across attempts>}`. <!-- changed -->
     - Set `current_state: "dispatch_next"` (move on to other plans).
     - If ALL remaining plans are `failed_permanent` or terminal: call `exit_loop_mode("BLOCKED: all plans failed after max retries. Last failure: {slug}")`. <!-- changed -->
     - Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->
   - If `retries < 3`:
     - Increment `retries`.
     - Set `status: "pending"` (retry).
     - Append `history` entry: `{state: "handle_failure", slug, event: "retry", at: <ISO>, note: "attempt N: <diagnosis>"}`. <!-- changed -->
     - Set `current_state: "dispatch_next"`.
     - Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->

### State: `unknown`

**Purpose**: Catch-all for unexpected results. Analyze the surprise, design a path forward.

1. Read `orchestrate_state.json`. Review the last 3–5 history entries to understand what happened. <!-- changed -->
2. Diagnose what diverged from expectations. Do not panic — this is your dedicated analysis space.
3. Determine the correct path forward. You may:
   - Modify plan statuses directly if the state file is inconsistent (e.g., a plan marked `in_progress` but `active_plan` is null — set it to `pending`).
   - Reset `current_state` to a known state listed in the session-boundary dispatch table. <!-- changed -->
   - Escalate by calling `exit_loop_mode("UNSAFE: ...")` if the inconsistency suggests data corruption you cannot reason about. <!-- changed -->
4. Run invariant checks after any modifications (see below).
5. Set `current_state` to the appropriate next state (typically `dispatch_next` or `handle_failure`).
6. Append `history` entry describing the anomaly and the chosen fix. <!-- changed -->
7. Atomically rewrite state file. Print STATEFILE path. **STOP.** <!-- changed -->

### Terminal exits <!-- changed -->

Terminals are **not** states — they are `exit_loop_mode` calls. Never write a terminal name to `current_state`. <!-- changed -->

| Trigger | `exit_loop_mode` message |
|---|---|
| All plans `done` and `verified: true` | `"DONE: N plans completed successfully. Plan dir: $PLAN_DIR"` |
| Needs human decision, unresolvable autonomously | `"BLOCKED: <what's needed from human>"` |
| Agent uncertain, scared, or detected danger | `"UNSAFE: <what triggered the stop>"` |
| Plan directory invalid, missing tools, contradictory dependencies | `"IMPOSSIBLE: <what's missing or contradictory>"` |
| Iteration budget exhausted | `"TIMEOUT: max_iterations reached, last state: <state>, N done, M remaining"` |

When a transition would target a terminal, call `exit_loop_mode` with the corresponding message and do not write anything further to `current_state`. The loop harness stops invoking permanently. <!-- changed -->

### Invariant checks

Run these whenever the state machine is modified (`init`, `unknown`, `handle_failure` when evolving):

1. `current_state` is one of the live states in the dispatch table (`dispatch_next`, `monitor_execution`, `verify_output`, `handle_failure`, `unknown`). Never a terminal name. <!-- changed -->
2. `active_plan` is either `null` or a slug present in `plans`.
3. No plan has `status: "in_progress"` while `active_plan` is `null` (inconsistent — set to `"pending"` or `"failed"`).
4. No plan has `status: "done"` with `verified: false` for more than one iteration (it should have transitioned through `verify_output`). <!-- changed -->
5. Every `dependencies` entry references a slug that exists in `plans`.
6. Every entry in `history` has `iteration`, `state`, `at`. <!-- changed -->
7. `iteration` is monotonically non-decreasing across history entries. <!-- changed -->

## Constraints

- **Do not ask questions.** You run unattended in a loop. Use Bash `sleep` to wait, `exit_loop_mode` to escalate.
- **Never write files outside `$PLAN_DIR/results/`** except `orchestrate_state.json`.
- **Never execute plan instructions directly.** Always delegate to `omp launch`. You are the orchestrator, not the worker.
- **Never chain states.** Execute exactly one state per invocation. After a STOP line, your session is over.
- **Respect the iteration budget.** `max_iterations` defaults to 200. If you hit it, `exit_loop_mode("TIMEOUT: ...")` — do not raise it to keep going.
- **Print state file path after every write.** `echo "ORCHESTRATE STATEFILE: $PLAN_DIR/orchestrate_state.json"` — it is your only link between iterations. If you lose it, you lose all progress.
- **Recover `$PLAN_DIR` from the last printed STATEFILE line** if the env var is missing on a subsequent iteration. The parent directory of that path is `$PLAN_DIR`; confirm by reading the `plan_dir` field of the state file. <!-- changed -->
- **Keep state file valid JSON at all times.** Write atomically: construct the full JSON object, then `write` it in one shot. A corrupted state file means starting over.
- **Quote `$PLAN_DIR` in every shell command** — paths may contain spaces or special characters. <!-- changed -->
- **Verify tool availability.** Run `which omp` before dispatching. If `omp` is missing, `exit_loop_mode("IMPOSSIBLE: omp CLI not found")`.
- **When uncertain, scared, or think you broke something:** call `exit_loop_mode("UNSAFE: ...")` immediately. Yielding to a human is always safe. Proceeding while unsure is not.
- **Do not resolve git conflicts autonomously.** If a sub-agent's output causes merge conflicts, escalate via `exit_loop_mode("BLOCKED: merge conflict in <file> — needs human resolution")`. <!-- changed -->
- **Do not delete or archive completed plan directories.** The state file is the authority. A `done` project stays done.
- **Cap retries at 3 per plan.** After 3 failures, mark `failed_permanent` and move on. Do not retry indefinitely.
- **Prefer Bash `sleep` over `exit_loop_mode()`** when uncertain whether work is truly done. A sleeping agent can be re-invoked; an exited agent cannot.
- **OMP auto-compacts context.** Your context window may shrink between invocations. This is safe because you always re-read the state file fresh. Never rely on memory of prior invocations.

## TLDR

You are plan-orchestrate: a loop prompt that executes subplans one at a time using a state machine tracked in `orchestrate_state.json`. Read the state file on every invocation to know which state to run. States cycle through: dispatch a plan → monitor execution → verify output → dispatch next. Use `unknown` when surprised. Call `exit_loop_mode` when all plans are done or blocked. Execute exactly one state per invocation, update the state file atomically, print its path, and stop. The state file is your only memory — never chain states, never scroll past STOP, never ask questions.
