---
description: [Internal sub-skill] Perform a structured code review on a PR diff, evaluating correctness, security, error handling, maintainability, and performance, then post findings as a PR comment. Standalone entry point for one-off reviews; for full multi-phase workflows, use `do-gh-issue` instead.
argument-hint: "[branch] [--pr number] [--focus (correctness|security|error-handling|maintainability|performance)]"
allowed-tools: Read, Search, Find, Bash, LSP
tool-hints: |
  Use `git diff main...<branch>` to get the diff between the PR branch and main.
  Use `read` to inspect changed files in full — a diff snippet alone is insufficient.
  Use `search` or `lsp references` to cross-reference callers and callees.
  Use `gh pr comment` to post findings. Never modify source files — this is read-only.
  Read `AGENTS.md` if it exists for project-specific conventions.
---

## Usage

**Invocation:** `/skill:gh-review [branch] [--pr number] [--focus dimension]`

- `branch` — (optional) The branch to review (diffed against `main`). If omitted, read from `.gh-issue-state.json`.
- `--pr number` — (optional) The PR number to post the review comment on.
- `--focus dimension` — (optional) Restrict review to one dimension: `correctness`, `security`, `error-handling`, `maintainability`, or `performance`. If omitted, all five dimensions are evaluated.

**Examples:**
- `/skill:gh-review fix-issue-42 --pr 7` — Full five-dimension review of `fix-issue-42`, posted to PR #7
- `/skill:gh-review fix-issue-42 --pr 7 --focus security` — Security-only review
- `/skill:gh-review` — Review the branch from the state file
Parse `$ARGUMENTS`:
- First positional argument is the branch name to review.
- `--pr number` — the PR number to comment on.
- `--focus FOCUS` — restrict review to one dimension: `correctness`, `security`, `error-handling`, `maintainability`, or `performance`.
- If state file `.gh-issue-state.json` exists, read `branch` and `pr_number` from it.
- If no branch is determinable, ask the user.

---

## Mode: Review PR Diff

### Step 1 — Gather context

1. Determine branch and PR number from arguments or state file.
2. Get diff overview: `git diff main...<branch> --stat`
3. Get full diff: `git diff main...<branch>`
4. If more than 5 files changed: note "Large diff — review focuses on core changes; some files may not be exhaustively reviewed."
5. Check for `AGENTS.md` or `CLAUDE.md` in repo root. If present, read it for project conventions, gotchas, and non-goals.

### Step 2 — Read changed files

For each changed file:
1. Read the full file (not just the diff). A diff lacks surrounding context needed for correctness evaluation.
2. Cross-reference callers and callees of changed symbols using `lsp references` or `search`.

### Step 3 — Evaluate against all dimensions

Evaluate in order. Flag CRITICAL issues immediately but continue evaluating remaining dimensions:

**1. Correctness**
- Logic errors, off-by-one, null/undefined dereferences, type mismatches
- Race conditions (shared mutable state without synchronization)
- Incorrect assumptions about input shape or range
- Missing or incorrect edge-case handling

**2. Security**
- Injection vulnerabilities (command, SQL, path traversal, XSS)
- Authentication or authorization bypass
- Credential leaks (hardcoded secrets, secrets in logs, secrets in URLs)
- Missing or insufficient input validation / sanitization

**3. Error handling**
- Silent failures (errors caught but ignored, or `/* fallthrough */` with no action)
- Swallowed panics or exceptions
- Unhandled error variants in match/switch
- Functions that return success-like values when they have actually failed

**4. Maintainability**
- Coupling and cohesion — is this module doing too much?
- Naming — do names communicate intent or just mechanics?
- Duplication — repeated patterns that should be extracted
- Dead code — unreachable branches, unused parameters or imports
- Comments — misleading, absent where needed, or present to excuse bad naming

**5. Performance**
- Hot-path allocations in loops
- N+1 queries or redundant I/O
- Unnecessary work that could be cached, batched, or hoisted
- Inefficient data structures
### Step 4 — Produce findings

Each finding must include:
- **Severity**: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, or `INFO`
- **File**: path relative to repo root
- **Line(s)**: line numbers affected
- **Problem**: specific description of what is wrong
- **Fix**: concrete code or structural change — not "consider improving"

Example:
```
1. **HIGH** — `scripts/game_manager.gd` (lines 616-622) — `clamp_launch_direction` returns non-normalized vector `(0, -0.342)` when input is `Vector2.ZERO` because `sign(0)` returns 0. The ball would launch at ~34% speed. Fix: add `if dir == Vector2.ZERO: return Vector2(0.0, -1.0)` guard at top of function.
```

If no issues in a dimension, state "No issues found." Do not invent LOW/INFO findings to pad the list.

Also produce: one-line verdict (score/10, biggest gap).

### Step 5 — Post as PR comment

```
gh pr comment <number> --body "## Review

Score: X/10. Gap: <gap>.

<findings, one line each>

Verdict: <one-line readiness>"

### Step 6 — Update state

If `.gh-issue-state.json` exists, update `last_review_findings`:
```json
{"critical": 0, "high": 1, "medium": 0, "low": 2}
```

### Constraints

- Do not modify any source files. This review is read-only.
- Do not post findings that are purely stylistic or preference-based. Every finding must have a concrete correctness, security, or maintainability impact.
- If uncertain about a finding, mark it LOW and explicitly state the uncertainty.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
