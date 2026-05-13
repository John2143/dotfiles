---
description: [Internal sub-skill] Discover or accept a GitHub issue, explore the codebase, gather requirements, and produce an implementation plan with exact file/line changes. Standalone entry point for planning; for full multi-phase workflows, use `do-gh-issue` instead.
argument-hint: "[issue-number]"
allowed-tools: Read, Search, Find, Task, Ask, Bash, Write
tool-hints: |
  Use `gh issue list/view` to fetch issue details. Use `gh issue edit --add-label in-progress` to claim it.
  Use `Task(explore)` to scout subsystems in parallel — never for implementation.
  Use `read` with selectors (e.g., `:615-700`) for exact line anchors.
  The only file you may write is `local://PLAN.md`. Never modify source code.
  Exit via `exit_plan_mode` to submit for approval — never ask for plan approval via text.
---

Parse `$ARGUMENTS`:
- First positional argument is an optional `$ISSUE_NUMBER`. If provided, fetch that issue. If omitted, auto-discover the first open issue without an `in-progress` label.
- If the issue body is empty or underspecified: if invoked as part of a multi-phase workflow (not standalone), follow `do-gh-issue` stuck protocol — surface the ambiguity and set phase to stuck. If standalone: ask the user to clarify requirements before exploring code.

---

## Mode: Analyze & Plan

### Step 1 — Fetch the issue

1. If `$ISSUE_NUMBER` provided:
   ```
   gh issue view <number> --json number,title,body,labels,url
   ```
2. If omitted:
   ```
   gh issue list --state open --limit 20 --json number,title,labels,body
   ```
   Filter to issues without `in-progress` label. Skip issues labeled `question` or `discussion`.
3. If no eligible issues: report "No eligible open issues found" and stop.
4. Present the first eligible issue to the user (number, title, labels, body excerpt). If in loop mode (unattended): auto-accept the first eligible issue — no `ask` call. If not in loop mode: ask for confirmation.
5. On confirmation: `gh issue edit <number> --add-label in-progress`. Proceed to Step 2.

### Step 2 — Clarify requirements

If the issue body is empty or the title is informal (e.g., "don't allow people to shoot to the side really far"):

1. If in loop mode (unattended): stop. Report "Issue <number> is underspecified — cannot plan without clarification." Return to `do-gh-issue` for stuck handling. Do not proceed.
2. If not in loop mode: surface design choices (example: "When the player aims below 20° from horizontal, should the shot be rejected entirely or clamped to the nearest allowed angle?") and ask the user for concrete acceptance criteria. Do not proceed until requirements are unambiguous.


### Step 3 — Explore (read-only)

1. Launch 2-3 parallel `Task(explore)` subagents. Example assignments:
   ```
   Task 1: "Read scripts/aim_controller.gd, scripts/magazine.gd, scripts/game_manager.gd. Find all functions related to aiming, shooting, fire, angle. Report exact line numbers, how aiming works, and where angle constraints could be applied."
   Task 2: "Read scripts/ball.gd and all ball variant scripts (explosive_ball.gd, burn_ball.gd, railgun_ball.gd). Report how direction vectors are computed, how launch() works, and any existing angle/threshold checks."
   ```
2. Read critical files at exact line level to get anchors. Use selectors like `:615-700`.
3. Identify: exact lines to change, callers/callees, existing patterns to follow, edge cases.

### Step 4 — Design the approach

1. Draft the approach: what changes, where, in what order.
2. If multiple viable approaches exist, use `ask` to let the user choose. Mark a recommended option.
3. Do not assume user intent. Clarify edge cases before writing the plan.

### Step 5 — Write the plan

Write `local://PLAN.md`. Required sections:

```markdown
# Plan: <descriptive title>

## Goal
<1-2 sentences: what must be true when complete>

## Current Behavior
- **<component>** (`file:line`): <what it does now>

## Approach: <chosen solution>
<Rationale for the approach. Why this over alternatives?>

### Angle Math (if applicable)
<Any constants, formulas, or coordinate-system assumptions>

### Changes: `path/to/file`

**1. <change description>** (line N):
| Before | After |
|---|---|
| `<old code>` | `<new code>` |

## Verification
1. <manual test step>
2. <edge case>
3. <edge case>

## Future Considerations (Out of Scope)
- <item noted but not included>
```

6. Call `exit_plan_mode` with a descriptive title (e.g., `CONSTRAIN_SHOOTING_ANGLE`).

### Constraints

- Read-only except for `local://PLAN.md`. Never modify source code, configs, or system state.
- Never run builds, tests, or state-changing commands.
- If the issue touches more than 5 files: flag it — it may need decomposition before a single plan can cover it.
- If requirements are still ambiguous after asking: do not write a plan. Surface what's missing.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
