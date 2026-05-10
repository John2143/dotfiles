---
description: Unattended loop variant of do-gh-issue — reads current PR/issue state, decides the next action automatically, executes one unit of work, then sleeps if nothing is needed
argument-hint: "(none — designed for /loop harness)"
allowed-tools: Read, Write, Edit, Search, Find, Bash, Task
tool-hints: |
  Use `gh` CLI for all GitHub operations. Use `git` for branch/commit/push.
  State file `.gh-issue-state.json` tracks progress across loop iterations.
  This skill runs unattended via `/loop`. Never ask the user questions.
  Each iteration executes exactly one action, then stops. If no work exists, sleep.
---

Parse `$ARGUMENTS`:
- This skill takes no arguments. It is designed for the `/loop` harness, which invokes it repeatedly with no user input.
- All decisions are driven by `.gh-issue-state.json` and the current PR/issue state from the GitHub API.

---

## Mode: Auto-Orchestrate

This is a loop prompt. The `/loop` harness calls it repeatedly. Each invocation reads state, decides what to do, executes one atomic action, updates state, and yields.

### Key files

| File | Purpose |
|---|---|
| `.gh-issue-state.json` | Current phase, issue number, branch, PR number, plan file, review findings, loop iteration count |
| `local://PLAN.md` | Implementation plan (written once, read during implement phase) |

State file schema:
```json
{
  "issue_number": 7,
  "issue_title": "don't allow people to shoot to the side really far",
  "branch": "fix-issue-7",
  "phase": "implement",
  "pr_number": 9,
  "plan_file": "local://PLAN.md",
  "incomplete_steps": ["Add zero-vector guard"],
  "last_review_findings": {"critical": 0, "high": 1, "medium": 0, "low": 2},
  "iteration": 4,
  "last_action": "Fixed Vector2.ZERO edge case in clamp_launch_direction"
}
```

### How to start each session — gap evaluation

Read `.gh-issue-state.json`. If it does not exist: go to `discover`. If it exists, read `phase` and jump to that phase.

Before acting, verify that work actually exists:

- **discover**: Are there open issues without `in-progress` label? If none → sleep.
- **plan**: Does a plan file exist? If yes, skip to implement. If the issue body is empty and no user has clarified requirements → sleep (cannot proceed without requirements).
- **implement**: Are there incomplete steps or unresolved review findings? If none → transition to review.
- **review**: Is there a PR to review? Has the diff changed since last review? If no changes since last review → transition to ready. If no PR exists yet → create one.
- **ready**: Has the PR been merged by a human? If merged → clean up and sleep. If still open but already marked ready → sleep (waiting for human).
- **done**: Sleep — no more work.

If at any point no action is needed: output "No work required. Sleeping." and stop. Do not invent work.

### How to work — execution actions

#### Action: discover

Find the next eligible issue.

1. `gh issue list --state open --limit 20 --json number,title,labels,body,url`
2. Filter to issues without `in-progress` label. Skip `question` and `discussion`.
3. If none: "No eligible issues. Sleeping." Stop.
4. Pick the first eligible issue.
5. Label it: `gh issue edit <number> --add-label in-progress`
6. Create state file:
   ```json
   {"issue_number": <number>, "issue_title": "<title>", "branch": null, "phase": "plan", "pr_number": null, "plan_file": "local://PLAN.md", "incomplete_steps": [], "last_review_findings": {}, "iteration": 1, "last_action": "Discovered and labeled issue #<number>"}
   ```
7. Report: "Discovered issue #<number>: <title>. Next: plan."

#### Action: plan

Explore codebase and write a plan.

1. Read issue: `gh issue view <number> --json title,body,labels,url`
2. If body is empty and title is vague (e.g., "fix the bug"): "Issue #<number> has insufficient detail for autonomous planning. Waiting for human to clarify. Sleeping." Stop. Do not proceed with assumptions.
3. Launch 2-3 `Task(explore)` subagents to scout affected subsystems.
4. Read critical files at exact line level.
5. Write `local://PLAN.md` with: Goal, Current behavior (file:line), Approach, Exact changes (before/after), Verification steps.
6. Create branch: `git checkout -b fix-issue-<number>`
7. Populate `incomplete_steps` in state file with the plan steps. Set `phase: "implement"`, `iteration: <n+1>`, `last_action: "Wrote plan and created branch <branch>"`.
8. Report: "Plan written. Branch <branch> created. Next: implement."

#### Action: implement

Execute one step or fix one finding.

1. Read state file and plan.
2. Prioritize:
   - `high` or `critical` review findings → fix highest first
   - Otherwise → first item from `incomplete_steps`
   - If both empty → set `phase: "review"`, report and stop
3. Re-read anchor lines before editing.
4. Make the change via `edit`.
5. Verify: re-read modified lines, search for stale references.
6. Attempt validation (check `AGENTS.md`, `Makefile`, etc.). If validation fails and the error is clear: fix it in the same iteration. If unclear: note the failure and continue — the review phase will catch it.
7. Commit and push.
8. If no PR exists yet: create one via `gh pr create`.
9. Update state: remove completed step/finding. If all done → `phase: "review"`. If fixing a finding → `phase: "review"`.
10. Report: "Implemented: <what was done>. Pushed to <branch>. Next: <review>."

#### Action: review

Review the current diff and post findings.

1. Get diff: `git diff main...<branch>`
2. Read changed files in full. Cross-reference callers/callees.
3. Evaluate: correctness, security, error handling, maintainability, performance.
4. Produce findings with severity, file, lines, problem, concrete fix.
5. Post as PR comment: `gh pr comment <number> --body "## Review (automated)\n\n..."`
6. Triaging:
   - `critical` or `high` findings: set `phase: "implement"`, store in `last_review_findings`.
   - `medium` only: set `phase: "implement"` and store findings.
   - LOW/INFO only or none: set `phase: "ready"`.
7. Report: "Review complete. N findings (X high, Y medium, Z low). Next: <implement or ready>."
   - Store current HEAD commit hash in state as `last_reviewed_commit`. On next review, if HEAD matches `last_reviewed_commit` and no new commits: skip review, transition to `ready`.

#### Action: ready

Finalize PR for human review.

1. If already marked ready: "PR #<number> is ready and waiting for human review. Sleeping." Stop.
2. Update PR body with AI attribution section (what was done, assumptions, not-verified, human attention needed).
3. Add a comment: `gh pr comment <number> --body "PR ready for human review. Automated cycle complete."`
4. Set `phase: "ready"`, `last_action: "PR marked ready for human review"`.
5. Report: "PR #<number> ready for human review: <url>. Sleeping until human merges or requests changes."

#### Action: sleep

No work exists. Output: "No work required. All issues are either in-progress (by another agent), blocked on human input, or already completed. Sleeping."

### Loop iteration tracking

Increment `iteration` on every action. Track `last_action` with a one-line summary. This provides an audit trail visible in the state file.

### Constraints

- **Never ask the user questions.** This skill runs unattended via `/loop`. If requirements are ambiguous, sleep and wait for human intervention.
- Never merge PRs. Never run `gh pr merge`.
- Never force-push. Never use `--no-verify` or `--no-gpg-sign`.
- Never modify files outside the repo root.
- Never read, print, or commit secrets, `.env` files, or private keys.
- If stuck (ambiguous requirements, unavailable tooling, unexpected state): surface the problem in the output and sleep. Do not guess.
- One atomic action per invocation. Do not chain actions.
- If the issue touches more than 5 files or 3 subsystems: sleep and flag for human triage.
- If validation fails with unclear errors: note the failure, continue to review — do not loop indefinitely on a failing build.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and sleep.
- If `.gh-issue-state.json` is malformed or missing required fields: report the parse error, show the expected schema, and sleep.
- If `git push` is rejected (non-fast-forward): report "Push rejected — branch may have diverged. Manual intervention needed." and sleep.

### TLDR

Read `.gh-issue-state.json` to find the current phase. If no state, discover an issue. Execute one atomic action (discover → plan → implement → review → fix loop → ready → sleep). Never ask questions. If stuck or nothing to do, sleep.

### Output format

Every invocation must output exactly one status line:
```
ACTION: <action-name> | RESULT: <one-line outcome> | NEXT: <next-phase>
```
Examples:
```
ACTION: discover | RESULT: labeled issue #7 | NEXT: plan
ACTION: implement | RESULT: fixed Vector2.ZERO edge case | NEXT: review
ACTION: review | RESULT: 1 high finding posted | NEXT: implement
ACTION: ready | RESULT: PR #9 marked ready | NEXT: sleep
ACTION: sleep | RESULT: no eligible issues | NEXT: sleep
```
