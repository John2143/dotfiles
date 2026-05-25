---
description: Fast-path for trivial GitHub issues — discover, fix, PR, done. No plan/review cycle. For typos, one-liners, dependency bumps, and obvious fixes only
argument-hint: "[issue-number]"
allowed-tools: Read, Write, Edit, Bash, Search
tool-hints: |
  Use `gh issue list/view` to fetch the issue. Use `edit` for single-line changes.
  Commit and push in one shot. Open a PR with `Fixes #<number>`.
  Skip if the issue fails the triviality checklist below. Suggest `do-gh-issue` instead.
---

## Usage

**Invocation:** `/skill:gh-sweep [issue-number]`

- `issue-number` — (optional) The GitHub issue number to fix. If omitted, auto-discovers the first open issue without an `in-progress` label that passes the triviality checklist.

**Examples:**
- `/skill:gh-sweep 42` — Fix issue #42 if it passes the triviality checklist
- `/skill:gh-sweep` — Auto-discover and fix the next eligible trivial issue
Parse `$ARGUMENTS`:
- First positional argument is an optional `$ISSUE_NUMBER`. If omitted, auto-discover the next eligible open issue without `in-progress` label.
- If no eligible trivial issues exist, report and stop.

---

## Mode: Sweep

### Step 1 — Discover

1. `gh issue list --state open --limit 20 --json number,title,labels,body`
2. Filter to issues without `in-progress` label. Skip `question` and `discussion` labels.
3. For each candidate, run the triviality checklist. An issue is trivial ONLY if ALL of these are true:

   - [ ] The fix changes ≤ 2 files
   - [ ] The fix changes ≤ 5 lines total
   - [ ] No new functions or types are created
   - [ ] No control flow changes (no new if/else, loop, or match branches)
   - [ ] The fix does not touch: auth, security, cryptography, concurrency, data persistence, or networking code
   - [ ] The fix has exactly one unambiguous correct answer (no design decisions)
   - [ ] Examples: typo fixes, version string bumps, dead code removal, config value tweaks, broken URL fixes, obvious copy-paste errors

4. If no issues pass: "No trivial issues found. Use `do-gh-issue` for issues requiring planning." Stop.
5. Present the first trivial issue. If in loop mode (unattended): auto-accept — no `ask` call. If not in loop mode: ask for confirmation — "This looks trivial (<description>). Fix and open a PR?" If user declines, move to the next candidate. If none remain, stop.

### Step 2 — Label and branch

1. `gh issue edit <number> --add-label in-progress`
2. `git checkout -b fix-issue-<number>`

### Step 3 — Fix

1. Read the affected file. Make the minimal change via `edit`.
   Example: `edit` a single line to fix a typo.
2. Re-read the modified lines to confirm correctness.
3. Do NOT run a review cycle. This is a trivial fix.
4. If you encounter any ambiguity during the fix: abort, remove the `in-progress` label, and suggest `do-gh-issue` instead. Do not proceed with uncertainty.

### Step 4 — Commit, push, PR

1. `git add <file>`
2. `git commit -m "<description>\n\nFixes #<number>"`
3. `git push origin fix-issue-<number>`
4. `gh pr create --base main --head fix-issue-<number> --title "<title>" --body "Fixes #<number>\n\nTrivial fix — no plan/review cycle."`

### Step 5 — Report

"PR #<number> created: <url>. Issue labeled `in-progress`. This was a trivial fix — human should verify and merge."

### Constraints

- If you have ANY doubt about triviality: stop and suggest `do-gh-issue`. False confidence on a non-trivial issue is worse than not attempting it.
- Never use this skill for anything involving: security, auth, encryption, data mutation, concurrency, networking, or more than 2 files.
- If the affected file has a detectable build system, run the build command to verify the fix compiles. If compilation fails: abort, remove the in-progress label (`gh issue edit <number> --remove-label in-progress`), and suggest `do-gh-issue` instead.
- If the fix breaks anything, the human owns the revert.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
