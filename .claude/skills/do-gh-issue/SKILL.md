---
description: Auto-discover an open GitHub issue, shepherd it through plan → implement → review → fix cycles, respond to human PR comments, and deliver a reviewed PR ready for human merge
argument-hint: "[issue-number]"
allowed-tools: Read, Write, Edit, Search, Find, Bash, Task, Ask
tool-hints: |
  Use `gh` CLI for all GitHub operations. Use `git` for branch/commit/push — never force-push.
  State file `.gh-issue-state.json` tracks progress across invocations.
  Each invocation executes exactly one phase, then stops. Do not chain phases. Sub-skills (`gh-get-issue-and-plan`, `gh-implement-step`, `gh-review`, `gh-triage`, `gh-pr-describe`) are standalone entry points for single-phase use; `do-gh-issue` is the recommended orchestrator for multi-phase workflows.
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
| `.gh-issue-state.json` | Current phase, issue number, branch, PR number, plan file, review findings, comment replies, cycle count |
| `local://PLAN.md` | Implementation plan (written during plan phase, read during implement) |

State file schema:
```json
{
  "schema_version": 1,
  "issue_number": 7,
  "issue_title": "don't allow people to shoot to the side really far",
  "branch": "fix-issue-7",
  "phase": "implement",
  "pr_number": 9,
  "plan_file": "local://PLAN.md",
  "incomplete_steps": ["Add zero-vector guard", "Pre-compute trig constants"],
  "last_review_findings": {"critical": 0, "high": 1, "medium": 0, "low": 2},
  "last_reviewed_commit": "a1b2c3d",
  "review_cycles": 2,
  "reply_to_comments": [
    {"comment_id": "IC_kwABC123", "author": "reviewer1", "body_preview": "This should use a lookup table instead.", "resolved": false}
  ],
  "last_comment_check": "2025-01-15T10:30:00Z",
  "iteration": null,
  "last_action": null,
  "stuck_reason": null
}
```

All state fields: `schema_version`, `issue_number`, `issue_title`, `branch`, `phase`, `pr_number`, `plan_file`, `incomplete_steps`, `last_review_findings`, `last_reviewed_commit`, `review_cycles`, `reply_to_comments`, `last_comment_check`, `iteration`, `last_action`, `stuck_reason`.

### How to start each session

0. Validate state file if it exists: after reading, check that `schema_version`, `issue_number`, `phase` are present and non-null. If any required field is missing, report the parse error with the expected schema and stop.
1. Check if `.gh-issue-state.json` exists.
   - **State file exists, phase is not `done`**: Read it. Jump to the phase stored in `phase`. Execute that phase and only that phase. This issue is still active — stay on it.
   - **State file exists, phase is `stuck`**: Read `stuck_reason` and report: "This issue is stuck: <stuck_reason>. Options: (1) resolve the blocker and set phase back manually, (2) abandon the issue (`rm .gh-issue-state.json && gh issue edit <number> --remove-label in-progress`)." Then call `exit_loop_mode("Stuck: <stuck_reason>")`. If the tool is unavailable, report text and stop.
   - **State file exists, phase is not `done` or `stuck`**: Read it. Jump to the phase stored in `phase`. Execute that phase and only that phase. This issue is still active — stay on it.
   - **State file exists, phase is `done`**: The PR was finalized, but a human may have commented since. Check for new human comments on that specific PR (same procedure as review step 13). If new unresolved comments exist, add them to `reply_to_comments`, set `phase: "implement"`, and execute implement. If no new comments, delete `.gh-issue-state.json` and fall through to step 2.
2. If no state file (or it was just deleted): **scan all open PRs for new human comments before reaching for new issues.** Existing PRs always take priority.
   - List open PRs: `gh pr list --state open --json number,comments --jq '.[] | select(.comments | length > 0) | .number'`
   - For each PR that has comments, fetch the full comment list and filter to human (non-self) comments. Since state files for completed PRs are deleted, treat any human comment on an open PR without an active state file as new.
   - If any PR has unaddressed human comments:
     - Present them: `"PR #<number> has <N> new comment(s) from <authors>. Latest: '<preview>'. Respond to this before new work?"`
     - On confirmation, create a fresh `.gh-issue-state.json` for that PR seeded with `phase: "implement"`, `pr_number`, `reply_to_comments` from the new comments, and `review_cycles: 0`. Execute implement.
   - If no PRs have new comments: proceed to `discover` phase to grab a new issue.
3. After completing the phase, update the `phase` field in the state file to the next phase (as specified at the end of each phase). Then stop.
   Always call `exit_loop_mode(reason)` when all work is exhausted (no state file, no eligible issues, no PRs with comments). If the tool is unavailable, report and stop.

#### Phase: discover

Find the next eligible issue, confirm with the user, label it, create state.

1. Run `gh issue list --state open --limit 20 --json number,title,labels,body`.
2. Filter to issues that do NOT have a label named `in-progress`. Skip issues labeled `question` or `discussion` unless the user explicitly asks for them.
3. If no eligible issues: report "No open issues without in-progress label." Then call `exit_loop_mode("No eligible open issues — all issues are in-progress, done, or skipped.")`. If the tool is unavailable, report and stop. Do not invent work.
4. Present the first eligible issue:
   ```
   **Issue #<number>** — "<title>"
   Labels: <label names>
   URL: <url>
   Body: <first 200 chars or "(empty)">
   ```
5. If in loop mode (unattended): auto-accept the first eligible issue — no `ask` call. If not in loop mode: `ask` for confirmation. If user says no, move to the next eligible issue. If none remain, call `exit_loop_mode("No remaining eligible issues — user declined all.")`. If the tool is unavailable, stop.
6. On confirmation:
   - `gh issue edit <number> --add-label in-progress`
   - Create `.gh-issue-state.json`:
     ```json
     {"schema_version": 1, "issue_number": <number>, "issue_title": "<title>", "branch": null, "phase": "plan", "pr_number": null, "plan_file": "local://PLAN.md", "incomplete_steps": [], "last_review_findings": {}, "last_reviewed_commit": null, "review_cycles": 0, "reply_to_comments": [], "last_comment_check": null, "iteration": null, "last_action": null, "stuck_reason": null}
     ```
   - Next phase: `plan`.

#### Phase: plan

Explore the codebase, gather requirements, produce an implementation plan.

1. Read the issue again: `gh issue view <number> --json title,body,labels`.
2. If the issue body is empty or the title is informal (e.g., "don't allow people to shoot to the side really far"):
   - If in loop mode (unattended): set `phase: "stuck"`, `stuck_reason: "Ambiguous issue — title or body is underspecified"`, and stop. The next invocation's stuck handler will exit the loop.
   - If not in loop mode: Ask: "What is the concrete acceptance criterion? What should the behavior be?"
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

Execute one step of the plan, fix one review finding, or respond to one human PR comment.

1. Read state file and plan file.
2. Choose what to work on (in priority order):
   - If `last_review_findings` has `critical` or `high` entries: fix the highest-severity finding first.
   - If `reply_to_comments` has unresolved entries: address the oldest unresolved comment.
   - Otherwise: pick the next item from `incomplete_steps`.
   - If all three lists are empty: set `phase: "review"` and stop.
3. Re-read anchor lines before editing (hashes shift after prior edits).
4. Make the change via `edit`. One function/module/concern per invocation.
5. Verify: re-read modified lines, search for stale references to old patterns.
6. Attempt validation if tooling is available (check `AGENTS.md`, `Makefile`, `package.json`, etc. for build/test commands). If unavailable, note it.
7. If validation fails: read the error, fix, re-verify. Do not push failing code.
8. Commit: `git add <files> && git commit -m "<description>\n\nRefs #<number>"`
9. Push: `git push origin <branch>`
10. If addressing a human comment: post a reply on the PR — `gh pr comment <number> --body "Addressed: <summary of what was changed>\n\n<optional: rationale if approach differs from suggestion>"`
11. If PR doesn't exist yet: `gh pr create --base main --head <branch> --title "<title>" --body "Fixes #<number>\n\n<summary>"`. Store PR number in state.
12. Update state:
    - If fixing a review finding: decrement the severity count in `last_review_findings`. If all counts are zero, clear `last_review_findings` (set to `{}`).
    - If addressing a comment: mark that comment `"resolved": true` in `reply_to_comments`.
    - If completing a plan step: remove it from `incomplete_steps`.
    - If all three lists (findings, comments, steps) are empty: set `phase: "review"`.
    - Otherwise: set `phase: "implement"` to continue with remaining work.
13. Next phase: as determined above.

#### Phase: review

Review the current diff, post structured findings, and triage human PR comments.

1. Read state file for branch, PR number, `last_reviewed_commit`, `review_cycles`.
2. Guard: if `HEAD` equals `last_reviewed_commit` (no new commits since last review) and `reply_to_comments` is empty: skip review — set `phase: "ready"` and stop.
3. Safety limit: if `review_cycles >= 5`: warn "5 review cycles reached — manual triage recommended." Set `phase: "ready"` and stop.
4. Increment `review_cycles` in state.
5. Get diff: `git diff main...<branch> --stat` then `git diff main...<branch>`.
6. If more than 5 files changed: note "Review may be incomplete due to large diff."
7. Check for `AGENTS.md` or `CLAUDE.md` — read for project conventions.
8. For each changed file: read full file, cross-reference callers/callees via `search` or `lsp references`.
9. Evaluate against: correctness, security, error handling, maintainability, performance.
10. Produce findings. Each must have: severity (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`/`INFO`), file, line(s), problem description, concrete fix. Do not invent LOW/INFO findings to pad the list.
    Example finding:
    ```
    1. **HIGH** — `scripts/game_manager.gd` (lines 616-622) — `clamp_launch_direction` returns non-normalized vector for `Vector2.ZERO` input. Fix: add `if dir == Vector2.ZERO: return Vector2(0.0, -1.0)` guard.
    ```
11. Also produce: one-line verdict (score/10, biggest gap).
12. Post as PR comment: `gh pr comment <number> --body "## Review (cycle <review_cycles>)\n\nScore: X/10. Gap: <gap>.\n\n<findings, one line each>\n\nVerdict: <one-line readiness>"`
13. Check for human PR comments (do this every review invocation, not just the first):
    - `gh pr view <number> --json comments --jq '.comments[] | select(.author.login != "<your login>") | {id: .id, author: .author.login, body: .body, createdAt: .createdAt}'`
    - Determine your own login: `gh auth status 2>&1 | head -1` or `gh api user --jq .login`.
    - Filter to comments created after `last_comment_check` (or all human comments if `last_comment_check` is null).
    - For each new unresolved human comment: append to `reply_to_comments` as `{"comment_id": "<id>", "author": "<login>", "body_preview": "<first 120 chars>", "resolved": false}`.
    - Update `last_comment_check` to current ISO timestamp.
14. Triaging (decide next phase):
    - If `critical` or `high` findings exist: store findings in `last_review_findings`, set `phase: "implement"`.
    - If `reply_to_comments` has unresolved entries: set `phase: "implement"`.
    - If only MEDIUM/LOW/INFO findings: store in `last_review_findings`, set `phase: "implement"` to auto-fix them. Multiple review cycles are expected and normal.
    - If no findings and no unresolved comments: set `phase: "ready"`.
15. Store current HEAD commit hash in state as `last_reviewed_commit`.
16. Next phase: as determined above.

#### Phase: ready

Finalize the PR for human review.

1. Update PR body with AI attribution (who did what, what was not verified):
   - Get current body: `gh pr view <number> --json body`
   - Get commit log: `git log main..<branch> --oneline`
   - Prepend attribution section:
     ```
     ## AI attribution
     **Agent role**: Full implementation from plan with self-review
     **Phases**: Discover → Plan → Implement → Review → Fix → Re-review (×<review_cycles> cycles) → Comment response
     **Not verified**: <things that could not be tested in this environment>
     **Human attention needed**: <areas requiring human judgment>
     ---
     ```
   - Update: `gh pr edit <number> --body "<new body>"`
2. Final verification: `gh pr view <number>`
3. Report: "PR #<number> is ready for human review: <url>. The `in-progress` label remains — remove it after merge."
4. Set `phase: "done"` in state file. **Do not call `exit_loop_mode` here.** The next invocation will check for remaining work (new issues, new PR comments) via the `done` handler and only exit when truly exhausted. Stop.

### Constraints

- Never merge PRs. Never run `gh pr merge`.
- Never force-push. Never use `--no-verify` or `--no-gpg-sign`.
- Never modify files outside the repo root.
- Never read, print, or commit secrets, `.env` files, or private keys.
- Each invocation executes exactly one phase. Do not chain phases. Multiple review→implement cycles are normal — repeat invocations until ready.
- If stuck (ambiguous issue, unclear requirement, unavailable tooling): set `phase: "stuck"`, set `stuck_reason` to a one-line description of the blocker, and stop. On next invocation, the stuck handler will present resolution options.
- If the issue touches more than 5 files or 3 subsystems, flag it for the user. Consider `plan-breakdown` for decomposition. Comment-response changes that touch additional files are expected — the 5-file limit applies to initial implementation, not follow-up responses.
- If `gh` CLI returns an auth or permission error: set `phase: "stuck"`, set `stuck_reason: "gh CLI auth/permission error — check gh auth status"`, and stop.
- When all work is exhausted (no state file, no eligible open issues, no PRs with unaddressed human comments), always call `exit_loop_mode('<summary>')`. Do not evaluate whether you are in loop mode — just call it. If the tool fails, your text report is sufficient. Under no circumstances should the skill loop when nothing is left to do.
- If `.gh-issue-state.json` is malformed or missing required fields: report the parse error, show the expected schema (from Key files above), and stop. Do not set stuck — this is a user-fixable file issue.
- If `git push` is rejected (non-fast-forward): set `phase: "stuck"`, set `stuck_reason: "Push rejected — branch may have diverged"`, and stop.

### TLDR

Read `.gh-issue-state.json` to find the current phase, execute one unit of work (discover → plan → implement → review → fix/comment loop → ready), update state, and stop. Never merge. Surface blockers rather than guessing. Multiple review cycles and comment responses are expected — invoke repeatedly until phase is `done`.
