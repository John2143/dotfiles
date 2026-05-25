---
description: "Decompose a complex plan into phased, delegatable work items with I/O contracts, file ownership maps, and independent verification"
argument-hint: "[path-to-plan | --text 'plan description'] [--output local://DELEGATEDPLAN.md] [--scope <area>]"
allowed-tools: Read, Write, Search, Find, Ask, Task(explore)
tool-hints: |
  Use Task(explore) subagents to scout unfamiliar subsystems in parallel — never for implementation.
  Use Search/Find to map which files each work item will touch before finalizing the plan.
  The only file you may write is DELEGATEDPLAN.md. Never use Edit, Bash(mutate), or any tool that modifies code, configs, or system state.
  This skill produces a plan file only; it does not execute the plan.
---

## Usage

**Invocation:** `/skill:plan-breakdown [path-to-plan | --text 'plan description'] [--output <path>] [--scope <area>]`

- `path-to-plan` — Path to an existing plan file to decompose. Mutually exclusive with `--text`.
- `--text 'plan description'` — Inline plan description to decompose. Mutually exclusive with a file path.
- `--output <path>` — Where to write the decomposed plan. Defaults to `local://DELEGATEDPLAN.md`.
- `--scope <area>` — Optional context narrowing (e.g., `"backend only"`, `"NixOS configs"`, `"auth subsystem"`).

**Examples:**
- `/skill:plan-breakdown ./ai-plan-myrepo-aB3x9/Index.md` — Decomposes a big-plan index into phased work items.
- `/skill:plan-breakdown --text "Add a backup health-check endpoint" --scope "backend only"` — Decomposes an inline plan, scoped to the backend.
- `/skill:plan-breakdown plan.md --output local://MYPLAN.md --scope "auth subsystem"` — Reads `plan.md`, scopes to auth, writes to `MYPLAN.md`.

Parse `$ARGUMENTS`:
- First positional argument is the plan source: a file path to an existing plan document, OR `--text "..."` for an inline plan description.
- `--output <path>` — where to write the decomposed plan. Default: `local://DELEGATEDPLAN.md`.
- `--scope <area>` — optional context narrowing (e.g. "backend only", "NixOS configs", "auth subsystem").
- If neither a file path nor `--text` is provided: ask the user to paste or point to the plan.
- Derive a plan-id from the plan title: run this exact bash snippet with the plan title in `$TITLE`. Captures output — if `EMPTY_SLUG`, use `plan-` followed by the ISO timestamp.
  ```bash
  PLAN_ID=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' | cut -c1-48)
  if [ -z "$PLAN_ID" ]; then echo "EMPTY_SLUG"; else echo "$PLAN_ID"; fi
  ```

---

## Mode: Breakdown

Your job is to produce a single file: a `DELEGATEDPLAN.md` that decomposes a complex plan into independently-verifiable, delegatable phases. You do research to inform the breakdown, but you never perform implementation work. You never modify code, configs, or system state.

### Step 1 — Ingest and scope the plan

1. Read the file at the given path, or accept the `--text` input.
2. If the plan is vague, underspecified, or has ambiguous scope: ask 1–3 clarifying questions before proceeding. Do not guess at boundaries that will cause downstream rework.
3. If the plan contradicts itself (e.g., lists files as in-scope but also says not to touch them): surface the specific contradiction and ask the user to resolve it before proceeding.
4. Extract and record:
   - **Primary goal**: what must be true when the plan is complete.
   - **Affected systems**: subsystems, directories, services, or modules touched.
   - **Known constraints**: deadlines, non-goals, tool restrictions, platform targets.
   - **Existing relevant files**: any files or directories the user already knows are in play.

If the plan is trivial (fewer than 2 distinct phases of work would make sense), flag this to the user: "This plan is small enough that a DELEGATEDPLAN may add more overhead than value. Proceed anyway or refine the ask?"

### Step 2 — Research (read-only)

Gather enough context to decompose accurately. You may:

- Search the repo with `Search` and `Find` to locate relevant code paths, configs, tests.
- Use `Task(explore)` subagents to scout unfamiliar subsystems in parallel. Each explore subagent gets a narrow target (one directory, one subsystem) and returns a summary of relevant files, patterns, and gotchas.
- Read key files to understand conventions, existing abstractions, and integration points.

You must not:

- Modify any file, run builds, execute tests, or run any command that changes state.
- Research systems unrelated to the plan — stay scoped to `--scope` if provided.

Record a **File Surface Map**: a list of files and directories the plan is likely to touch, grouped by subsystem. This map is used in Step 5 to detect collisions.
If the repo contains no relevant files (greenfield work, or the plan targets a new subsystem): record the File Surface Map as empty and note "No existing code to map — greenfield." The collision check in Step 5 will be a no-op for empty maps.
If research finds nothing relevant and the plan is not greenfield: report this explicitly. State your assumptions about which files might be in play so the orchestrator can validate them during execution.

### Step 3 — Decompose into phases

Think in a Directed Acyclic Graph (DAG): each phase is a node, dependencies are directed edges. Within a phase, work items are independent leaves that can run in parallel.

Rules for phase boundaries:

- A phase is a meaningful unit of work with a clear "done" criterion that can be verified without executing later phases.
- Each phase depends only on earlier phases. No circular dependencies.
- Within a phase, maximize parallelism — work items share no intermediate state.
- If you find a natural phase with only one work item, consider whether it can be merged into an adjacent phase or whether it truly is a sequential bottleneck.
- Aim for 2–7 phases. Fewer than 2: flag as possibly too simple. More than 7: the decomposition may be too granular.

Define each phase using the structure shown in the output template (Step 6): Goal, Depends on, Parallelism, and work items.

### Step 4 — Design work items (per phase)

Each work item is an atomic delegation to a subagent. Every field in the work-item template is required.

Define each work item using the structure shown in the output template (Step 6), filling in all fields: Role, TASK, EXPECTED OUTCOME, REQUIRED TOOLS, MUST DO, MUST NOT DO, CONTEXT, INPUT, OUTPUT, FILES TOUCHED, REVIEWER (with reviewer brief if YES), VERIFICATION (L1/L2/L3), and a [ ] checkbox.

**Granularity calibration**:
- A work item is too large if the subagent must make sub-decisions the plan should have made.
- A work item is too small if the coordination overhead (reading context, reporting output) exceeds the work itself.
- Heuristic: a work item should target 1–5 files and be completable in a single subagent session.

**Reviewer assignment rules**:
- Assign a reviewer (YES) when: the work item produces new code, changes interfaces, modifies shared configs, or has security/correctness implications.
- Skip the reviewer (NO) when: the work item is purely mechanical (rename, format, simple data extraction), is an explore/scout task, or produces no artifacts.
- For YES-reviewer items, write a **Reviewer brief** that the orchestrator will pass to a fresh subagent. The brief must:
  - State the expected outcome (same as the work item).
  - List L1/L2/L3 criteria.
  - Include the OUTPUT file paths.
  - Instruct the reviewer to use independent reasoning — do not share the original subagent's trace or intermediate work.
  - Include: "You have a fresh context window. Do not read the original subagent's work log. Verify by examining the artifacts directly and reasoning from first principles."

#### Example work item (for reference)

The following is a worked example showing two phases of a plan to add a backup-health-check endpoint. Use it to calibrate your granularity and level of detail.

```markdown
## Phase 1: Instrumentation

**Goal**: Add metrics collection to the backup subsystem so health can be queried. Verifiable by running `backupctl metrics` and seeing nonzero counters.

**Depends on**: None (initial phase).

**Parallelism**: Up to 2 simultaneous subagents.

### WI-1: Add metrics counters to backup engine

- **Role**: `task`
- **TASK**: Instrument the backup engine to track last-run timestamp, success/failure count, and total bytes backed up.
- **EXPECTED OUTCOME**: `src/backup/metrics.rs` exists with a `BackupMetrics` struct containing three counters (last_run: DateTime, success_count: u64, failure_count: u64, bytes_total: u64). Counters are updated in the existing `run_backup()` codepath.
- **REQUIRED TOOLS**: Read, Write, Edit, Search, LSP
- **MUST DO**: Add the struct and update `run_backup()` to increment counters. Use the existing `chrono` crate already in Cargo.toml.
- **MUST NOT DO**: Do not add new dependencies. Do not change the backup schedule logic. Do not touch `src/backup/retention.rs`.
- **CONTEXT**: The backup engine lives in `src/backup/engine.rs`. The project uses `chrono` for timestamps and `thiserror` for error types. Follow the existing pattern in `src/monitoring/` for metric struct layout.
- **INPUT**: None (initial work item).
- **OUTPUT**: `src/backup/metrics.rs` (new file), `src/backup/engine.rs` (modified: add counter increments after each backup run).
- **FILES TOUCHED**: `src/backup/engine.rs` (read+write), `src/backup/metrics.rs` (write), `src/backup/mod.rs` (write: add `mod metrics`).
- **REVIEWER**: `YES`
  - **Reviewer brief**: Verify that a `BackupMetrics` struct exists in `src/backup/metrics.rs` with the four specified fields. Verify that `run_backup()` in `src/backup/engine.rs` increments counters after each backup attempt (not just on success). Verify that `src/backup/mod.rs` declares `mod metrics`. L1: file exists and is not empty. L2: struct has all four fields with correct types; `run_backup()` calls increment methods. L3: module is properly wired — `cargo check` on `src/backup/` resolves without errors. You have a fresh context window. Do not read the original subagent's work log. Verify by examining the artifacts directly and reasoning from first principles.
- **VERIFICATION**:
  - **L1 — Existence**: `src/backup/metrics.rs` exists and is non-empty.
  - **L2 — Substance**: Contains `BackupMetrics` struct with `last_run`, `success_count`, `failure_count`, `bytes_total` fields. `engine.rs` calls increment methods after backup runs.
  - **L3 — Integration**: `mod metrics` declared in `src/backup/mod.rs`. No broken imports.
- **[ ] Checkbox**

### WI-2: Add metrics serialization

- **Role**: `quick_task`
- **TASK**: Add serde derives to `BackupMetrics` and implement `Display` for human-readable output.
- **EXPECTED OUTCOME**: `BackupMetrics` derives `Serialize` and has a `Display` impl that prints "last: <iso8601>, ok: N, fail: N, bytes: N".
- **REQUIRED TOOLS**: Read, Edit
- **MUST DO**: Add `#[derive(Serialize)]` to the struct. Implement `std::fmt::Display`. Use ISO 8601 format for the timestamp.
- **MUST NOT DO**: Do not modify field types or add new fields. Do not change the increment logic in `engine.rs`.
- **CONTEXT**: The project already uses `serde` with the `derive` feature (see `Cargo.toml`). `src/backup/metrics.rs` was created by WI-1.
- **INPUT**: `src/backup/metrics.rs` (from WI-1).
- **OUTPUT**: `src/backup/metrics.rs` (modified: add derives and Display impl).
- **FILES TOUCHED**: `src/backup/metrics.rs` (read+write).
- **REVIEWER**: `NO` (mechanical derive + Display — trivially verifiable by the orchestrator).
- **VERIFICATION**:
  - **L1 — Existence**: `src/backup/metrics.rs` still exists.
  - **L2 — Substance**: Struct derives `Serialize`. `Display` impl produces output matching the specified format.
  - **L3 — Integration**: `serde::Serialize` import resolves.
- **[ ] Checkbox**

---

## Phase 2: HTTP endpoint

**Goal**: Expose backup health via a `/health/backup` endpoint returning JSON. Verifiable with `curl localhost:8080/health/backup`.

**Depends on**: Phase 1.

**Parallelism**: 1 (single work item, depends on Phase 1 output).

### WI-3: Add health endpoint

- **Role**: `task`
- **TASK**: Add a `/health/backup` route that reads `BackupMetrics` and returns it as JSON.
- **EXPECTED OUTCOME**: `GET /health/backup` returns `{"last_run":"...","success_count":N,"failure_count":N,"bytes_total":N}` with HTTP 200.
- **REQUIRED TOOLS**: Read, Write, Edit, Search, LSP
- **MUST DO**: Add a route handler in the existing web layer. Import and use `BackupMetrics`. Return JSON via the existing response helpers.
- **MUST NOT DO**: Do not add a new web framework or router. Do not change the backup schedule or retention logic. Do not hardcode metrics values — always read live state.
- **CONTEXT**: The web layer uses `axum` (see `src/web/routes.rs` for existing route patterns). `BackupMetrics` is in `src/backup/metrics.rs` and implements `Serialize` (from Phase 1). Follow the existing pattern in `src/web/routes.rs` for adding routes.
- **INPUT**: `src/backup/metrics.rs`, `src/backup/engine.rs` (from Phase 1).
- **OUTPUT**: `src/web/routes.rs` (modified: add route).
- **FILES TOUCHED**: `src/web/routes.rs` (read+write).
- **REVIEWER**: `YES`
  - **Reviewer brief**: Verify the `/health/backup` route exists in `src/web/routes.rs`. Verify it imports `BackupMetrics` from `src/backup/metrics.rs`. Verify it returns JSON with the four expected fields. L1: route handler function exists. L2: handler reads from the metrics struct (not hardcoded). L3: route is registered with the axum router. You have a fresh context window. Do not read the original subagent's work log. Verify by examining the artifacts directly and reasoning from first principles.
- **VERIFICATION**:
  - **L1 — Existence**: Route handler function is present in `src/web/routes.rs`.
  - **L2 — Substance**: Handler imports `BackupMetrics`, calls a method to get current values, serializes to JSON with all four fields.
  - **L3 — Integration**: Route is registered with the axum `Router`. Imports resolve. No compilation errors in the web layer.
- **[ ] Checkbox**
```

### Step 5 — Cross-check

Before writing the output file, run these checks:

1. **File collision check**: Scan all work items within each phase. No two parallel work items may share a `FILES TOUCHED` entry. If they do, either:
   - Merge the work items into one.
   - Sequentialize them within the phase (add a note that WI-B waits for WI-A).
   - Split the shared file so each agent owns a disjoint subset.
2. **Dependency closure**: Trace every `Depends on` and `INPUT` reference. Every dependency must be satisfied by an earlier phase (or be an initial artifact). Flag any dangling references.
3. **Intra-phase independence**: Verify no work item within a phase lists another work item from the same phase as INPUT. If it does, split into sub-phases or mark the dependency explicitly with a wait note.
4. **Reviewer completeness**: Every work item marked REVIEWER: YES must have a reviewer brief with explicit L1/L2/L3 criteria.
5. **Large-data check**: Any work item whose EXPECTED OUTCOME involves large data (logs, diffs, full file contents, database dumps) must specify that output goes to a file, not inline in a chat response. Add a MUST DO: "Write results to `<path>`; do not print them inline."
6. **Role validity**: Every Role must be one of the available agent types (`task`, `explore`, `plan`, `reviewer`, `designer`, `librarian`, `quick_task`). Do not invent role names.

### Step 6 — Write DELEGATEDPLAN.md

Write the file to `--output` (default `local://DELEGATEDPLAN.md`). Use this structure:

```markdown
# DELEGATEDPLAN: [plan-id]

- **Source**: [file path or "--text"]
- **Generated**: [timestamp]
- **Scope**: [scope from --scope, or "full plan"]
- **Phases**: N total | **Work items**: M total | **With reviewers**: R

## Progress

| Phase | Work Items | Complete | Status |
|-------|-----------|----------|--------|
| 1: [Name] | N | 0/N | pending |
| ... | | | |

## Execution Instructions (for the orchestrator)

1. Work through phases in order. Do not start Phase N+1 until all work items in Phase N pass verification.
2. Within a phase, dispatch all parallel work items simultaneously using `Task` subagents.
3. For each work item marked REVIEWER: YES, after the work item completes, dispatch a fresh reviewer subagent with the Reviewer brief. The reviewer must have a clean context window — do not pass the original subagent's trace.
4. If a reviewer finds issues: mark the work item BLOCKED, note the findings, and stop. Wait for user input.
5. If any phase proves infeasible, incorrect, or too complex: STOP. Announce which phase, which work item, and what went wrong. Mark it BLOCKED. Wait for user input before replanning.
6. As work items complete, mark their checkboxes [x] and update the Progress table.

## Re-planning Protocol

If at any point a phase cannot be completed as designed:
- **STOP immediately.** Do not continue to the next phase. Do not attempt to work around the issue.
- **Announce**: which phase, which work item, and the specific problem (infeasible, blocked by unexpected state, incorrect assumption, etc.).
- **Mark**: the affected work item as `BLOCKED` with a note describing the issue.
- **Wait**: for user input. The user owns the replan decision — do not revise DELEGATEDPLAN.md autonomously.

---

## Phase 1: [Name]

**Goal**: ...

**Depends on**: ...

**Parallelism**: Up to N simultaneous subagents.

### WI-1: [Title]

- **Role**: ...
- **TASK**: ...
- **EXPECTED OUTCOME**: ...
- **REQUIRED TOOLS**: ...
- **MUST DO**: ...
- **MUST NOT DO**: ...
- **CONTEXT**: ...
- **INPUT**: ...
- **OUTPUT**: ...
- **FILES TOUCHED**: ...
- **REVIEWER**: [YES or NO]
  - (If YES) **Reviewer brief**: ...
- **VERIFICATION**:
  - **L1 — Existence**: ...
  - **L2 — Substance**: ...
  - **L3 — Integration**: ...
- **[ ] Checkbox**

### WI-2: [Title]

...

---

## Phase 2: [Name]

...
```

### Step 7 — Validate

After writing, read back the file and confirm:

1. All 7 user requirements are satisfied:
   - [ ] Phases exist with clear goals.
   - [ ] Each phase is independently verifiable; dependencies are explicit.
   - [ ] Plan is delegatable with parallelism maximized per phase.
   - [ ] Each work item instructs the agent to think, work, and return structured results.
   - [ ] Complex work items have reviewer agents with independent verification briefs.
   - [ ] Large data outputs specify file targets, not inline printing.
   - [ ] Re-planning protocol is included.
2. Report a summary to the user:
   - Number of phases and work items.
   - Which phases have the highest parallelism.
   - How many work items have reviewers assigned.
   - Any risks or assumptions the executing orchestrator should know.

