---
description: Autonomously orchestrate DevOps tasks using a state machine tracked in a temp file
argument-hint: '<task description>'
allowed-tools: Read, Search, Find, Write, Edit, Bash, Task, Ask
tool-hints: |
  Use `mktemp` to create the state file; print its path on every update.
  Use `sleep(duration, reason)` when waiting for external events (PR checks, deploys, timers).
  Use `exit_loop_mode(reason)` to stop permanently when work is complete or unsafe to continue.
  Use `notify-send` to alert the human desktop for blocking questions (pauses forever).
  Use `ask` for non-blocking questions (auto-picks default after 30s).
  Use Task subagents for parallel monitoring streams with ≤120s timeouts.
---

Parse `$ARGUMENTS`:
- Single positional argument: free-form task description string.
- If empty, read from session context; if still nothing, call `exit_loop_mode("no task provided")`.

---

## Mode: Autonomous Orchestration

### Phase 1 — Initialize or recover state

1. Check for an existing state file from a prior loop iteration (look for a recent `mktemp` file with babysit state, or check session context for a printed path).
2. If found and valid: load it. Skip to Phase 3.
3. If not found: create a new state file via `mktemp`. Print its path.
4. Parse the task description into a goal statement and initial constraints.

### Phase 2 — Build/evolve the state machine

1. From the goal, design a state machine with at least 2-3 initial states.
2. Each state has: `name`, `goal`, `actions` (concrete commands/checks), `transitions` (map of `result → next_state`).
3. Write the state machine to the state file.
4. Locked transitions (only one possible next state) vs. flexible transitions (multiple next states with conditions).

### Phase 3 — Execute current state

1. Read the current state from the state file.
2. Run the state's actions. Capture output.
3. Evaluate results against transition conditions.
4. Update the state file with action outputs and timestamp.
5. If the current state reveals new information: add/modify states in the machine (evolve the plan).

### Phase 4 — Transition

1. Determine the next state based on results and transition rules.
2. If no transition matches: analyze why, add a new state for the unexpected situation.
3. If the state machine reaches a terminal state: call `exit_loop_mode(summary)`.
4. Update the state file with the new current state.

### Phase 5 — Loop controller

- If the next action is "wait for external event": call `sleep(duration, reason)`.
- If all work is complete: call `exit_loop_mode(summary)`.
- If a human decision is required and it's non-trivial: use `notify-send` for desktop alert, then `sleep(30min, "awaiting human response")`.
- If a human decision is minor: use `ask` with a 30s default timeout.
- Otherwise: let the loop harness re-invoke (the next iteration starts at Phase 1).

### Constraints

- Do not ask questions (unattended mode; use `ask` with timeout or `notify-send` for human alerts).
- No destructive commands: no `rm -rf`, no force-push, no `--no-verify`.
- When uncertain or scared: `exit_loop_mode(reason)` to yield to human.
- Cap subagent timeouts at 120s; restart them each loop iteration with fresh state.
- Never modify the state file format in a way that breaks forward/backward recovery.

### TLDR

Read or create a temp state file tracking a state machine. Parse the task, design initial states,
execute the current state's actions, transition based on results, and evolve states as you learn.
Sleep when waiting, exit when done, alert the human only when truly blocked.
