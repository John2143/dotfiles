---
description: Auto-discover an open GitHub issue, shepherd it through plan → implement → review → fix cycles, and deliver a reviewed PR ready for human merge
argument-hint: "[issue-number]"
allowed-tools: Read, Write, Edit, Search, Find, Bash, Task, Ask
tool-hints: |
  Use `gh` CLI for all GitHub operations. Use `git` for branch/commit/push — never force-push.
  State file `.gh-issue-state.json` tracks progress across invocations.
  Sub-skill instructions (gh-get-issue-and-plan, gh-implement-step, gh-review, gh-triage, gh-pr-describe) are reproduced inline below.
  Each invocation executes exactly one phase, then stops. Do not chain phases.
---

Parse `$ARGUMENTS`:
- First positional argument is an optional `$ISSUE_NUMBER`. If provided, work on that specific issue. If omitted, auto-discover the next eligible issue.
- If no arguments, proceed with auto-discovery.

---

## Mode: Orchestrate

This is a multi-session skill. The user invokes it repeatedly. Each invocation reads state, determines the current phase, executes one unit of work, updates state, and yields.

### Key files

| File | Purpose |
|---|---|
| `.gh-issue-state.json` | Current phase, issue number, branch, PR number, plan file, review findings |
| `local://PLAN.md` | Implementation plan (written during plan phase, read during implement) |

State file schema:
```json
{
  "issue_number": 7,
  "issue_title": "don't allow people to shoot to the side really far",
  "branch": "fix-issue-7",
  "phase": "implement",
  "pr_number": 9,
  "plan_file": "local://PLAN.md",
  "incomplete_steps": ["Add zero-vector guard", "Pre-compute trig constants"],
  "last_review_findings": {"critical": 0, "high": 1, "medium": 0, "low": 2}
}
```

### How to start each session

1. Check if `.gh-issue-state.json` exists.
   - **No state file**: Go to `discover` phase below.
   - **State file exists**: Read it. Jump to the phase stored in `phase`. Execute that phase and only that phase.
2. After completing the phase, update the `phase` field in the state file to the next phase (as specified at the end of each phase). Then stop.

### How to work — execution phases

#### Phase: discover

Find the next eligible issue, confirm with the user, label it, create state.

1. Run `gh issue list --state open --limit 20 --json number,title,labels,body`.
2. Filter to issues that do NOT have a label named `in-progress`. Skip issues labeled `question` or `discussion` unless the user explicitly asks for them.
3. If no eligible issues: report "No open issues without in-progress label" and stop. Do not invent work.
4. Present the first eligible issue:
   ```
   **Issue #<number>** — "<title>"
   Labels: <label names>
   URL: <url>
   Body: <first 200 chars or "(empty)">
   ```
5. Ask: "Work on this issue?" If user says no, move to the next eligible issue. If none remain, stop.
6. On confirmation:
   - `gh issue edit <number> --add-label in-progress`
   - Create `.gh-issue-state.json`:
     ```json
     {"issue_number": <number>, "issue_title": "<title>", "branch": null, "phase": "plan", "pr_number": null, "plan_file": "local://PLAN.md", "incomplete_steps": [], "last_review_findings": {}}
     ```
   - Next phase: `plan`.

#### Phase: plan

Explore the codebase, gather requirements, produce an implementation plan.

1. Read the issue again: `gh issue view <number> --json title,body,labels`.
2. If the issue body is empty or the title is informal (e.g., "don't allow people to shoot to the side really far"):
   - Ask: "What is the concrete acceptance criterion? What should the behavior be?"
   - Surface design choices that need a decision (e.g., clamp vs reject, allow vs deny).
   - Do not proceed until requirements are unambiguous.
3. Launch 2-3 parallel `Task(explore)` subagents to scout affected subsystems. Each gets a narrow target and explicit reporting instructions.
4. Read critical files at exact line level to get anchors.
5. Draft the approach. If multiple viable approaches exist, use `ask` to let the user choose.
6. Write `local://PLAN.md` with: Goal, Current behavior (with file:line), Approach (with rationale), Exact changes (before/after tables), Verification steps, Future considerations.
7. Call `exit_plan_mode` with a descriptive title.
   - If the plan is rejected: set `phase: "plan"`, add `"plan_rejected": true` to state, report "Plan rejected. Revise and re-invoke.", and stop.
8. On approval:
   - Create branch: `git checkout -b fix-issue-<number>`
   - Update state: `branch`, `phase: "implement"`, `incomplete_steps` from plan.
   - Next phase: `implement`.

#### Phase: implement

Execute one step of the plan or fix one review finding.

1. Read state file and plan file.
2. Choose what to work on:
   - If `last_review_findings` has `high` or `critical` entries: fix the highest-severity finding first.
   - Otherwise: pick the next item from `incomplete_steps`.
   - If both lists are empty: set `phase: "review"` and stop.
3. Re-read anchor lines before editing (hashes shift after prior edits).
4. Make the change via `edit`. One function/module/concern per invocation.
5. Verify: re-read modified lines, search for stale references to old patterns.
6. Attempt validation if tooling is available (check `AGENTS.md`, `Makefile`, `package.json`, etc. for build/test commands). If unavailable, note it.
7. If validation fails: read the error, fix, re-verify. Do not push failing code.
8. Commit: `git add <files> && git commit -m "<description>\n\nRefs #<number>"`
9. Push: `git push origin <branch>`
10. If PR doesn't exist yet: `gh pr create --base main --head <branch> --title "<title>" --body "Fixes #<number>\n\n<summary>"`. Store PR number in state.
11. Update state: remove completed step/finding from lists. If all steps done and no findings: set `phase: "review"`. If fixing a finding: set `phase: "review"`.
12. Next phase: as determined above.

#### Phase: review

Review the current diff and post structured findings as a PR comment.

1. Read state file for branch and PR number.
2. Get diff: `git diff main...<branch> --stat` then `git diff main...<branch>`.
3. If more than 5 files changed: note "Review may be incomplete due to large diff."
4. Check for `AGENTS.md` or `CLAUDE.md` — read for project conventions.
5. For each changed file: read full file, cross-reference callers/callees via `search` or `lsp references`.
6. Evaluate against: correctness, security, error handling, maintainability, performance.
7. Produce findings. Each must have: severity (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`/`INFO`), file, line(s), problem description, concrete fix. Do not invent LOW/INFO findings to pad the list.
   Example finding:
   ```
   1. **HIGH** — `scripts/game_manager.gd` (lines 616-622) — `clamp_launch_direction` returns non-normalized vector for `Vector2.ZERO` input. Fix: add `if dir == Vector2.ZERO: return Vector2(0.0, -1.0)` guard.
   ```
8. Also produce: Summary (score/10 + biggest gap) and Overall assessment paragraph.
9. Post as PR comment: `gh pr comment <number> --body "## Review from automated agent\n\n### Summary\n...\n\n### Findings\n...\n\n### Overall assessment\n..."`
10. Triaging:
    - If `critical` findings exist: set `phase: "implement"`, store findings in `last_review_findings`.
    - If `high` findings exist: set `phase: "implement"`, store findings.
    - If only MEDIUM/LOW/INFO: ask user "Fix remaining MEDIUM findings or mark PR ready?" Update phase based on answer.
    - If no findings: set `phase: "ready"`.
11. Next phase: as determined above.
    - Store current HEAD commit hash in state as `last_reviewed_commit`. On next review invocation, compare `HEAD` to `last_reviewed_commit` — if identical and no new commits exist, skip review and transition to `ready`.

#### Phase: ready

Finalize the PR for human review.

1. Update PR body with AI attribution (who did what, what was not verified):
   - Get current body: `gh pr view <number> --json body`
   - Get commit log: `git log main..<branch> --oneline`
   - Prepend attribution section:
     ```
     ## AI attribution
     **Agent role**: Full implementation from plan with self-review
     **Phases**: Discover → Plan → Implement → Self-review → Fix → Re-review
     **Not verified**: <things that could not be tested in this environment>
     **Human attention needed**: <areas requiring human judgment>
     ---
     ```
   - Update: `gh pr edit <number> --body "<new body>"`
2. Final verification: `gh pr view <number>`
3. Report: "PR #<number> is ready for human review: <url>. The `in-progress` label remains — remove it after merge."
4. Set `phase: "done"` in state file. Stop.

### Constraints

- Never merge PRs. Never run `gh pr merge`.
- Never force-push. Never use `--no-verify` or `--no-gpg-sign`.
- Never modify files outside the repo root.
- Never read, print, or commit secrets, `.env` files, or private keys.
- Each invocation executes exactly one phase. Do not chain phases.
- If stuck (ambiguous issue, unclear requirement, unavailable tooling): surface the problem and stop — do not guess.
- If the issue touches more than 5 files or 3 subsystems, flag it for the user. Consider `plan-breakdown` for decomposition.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
- If `.gh-issue-state.json` is malformed or missing required fields: report the parse error, show the expected schema (from Key files above), and stop.
- If `git push` is rejected (non-fast-forward): report "Push rejected — branch may have diverged. Manual intervention needed." and stop.

### TLDR

Read `.gh-issue-state.json` to find the current phase, execute one unit of work (discover → plan → implement → review → fix loop → ready), update state, and stop. Never merge. Surface blockers rather than guessing. Invoke repeatedly until phase is `done`.
