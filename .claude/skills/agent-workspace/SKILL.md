---
description: "Create and manage git worktree workspaces for isolated agent task execution — checkpoint a branch, do work, commit or leave for review"
argument-hint: "[task] [--branch NAME] [--base-ref REF] [--list | --cleanup [ID] | --resume ID]"
allowed-tools: Read, Write, Edit, Bash, Task, Search, Find, LSP
tool-hints: |
  Use Bash for all git worktree commands (add, remove, list, prune).
  Use Write for the single shared index file .claude/worktree-index.json.
  Use flock(1) for index file locking on every read and write.
  Always assert your working directory — cd to the repo root for index ops, cd to the worktree for task work.
  Task subagents inherit the worktree cwd automatically — they are already isolated, no further worktree setup needed.
---

## Usage

**Invocation:** `/skill:agent-workspace "task description" [--branch NAME] [--base-ref REF]`

- `task` — Natural-language task description. The agent executes this work in the isolated worktree.
- `--branch NAME` — Override the auto-generated branch name (default: `omp/task-<slug>`).
- `--base-ref REF` — Base ref to branch from (default: `HEAD`).
- `--list` — List all tracked worktrees.
- `--resume ID` — Resume work in an existing worktree.
- `--cleanup [ID]` — Remove a specific worktree by ID, or batch-remove all "done"/"orphaned" worktrees.

**Examples:**
- `/skill:agent-workspace "Refactor the auth module to use JWT tokens"` — Creates worktree, does the work, offers to commit.
- `/skill:agent-workspace "Add rate limiting middleware" --branch feat/rate-limit --base-ref main` — Custom branch and base.
- `/skill:agent-workspace --list` — Show all tracked worktrees and their status.
- `/skill:agent-workspace --resume refactor-auth-20260524T120000` — Resume a prior worktree.

**Worked example (full lifecycle):**
```
/skill:agent-workspace "Add rate limiting middleware"
→ Reads index, no existing worktree for this task
→ Creates /tmp/omp-worktrees/add-rate-limiting-20260524T120000 on branch omp/task/add-rate-limiting
→ cd's into worktree, writes middleware.ts, stages, tests
→ Shows diffstat: 1 file changed, 45 insertions
→ User chooses "commit + cleanup" → commits, pushes, removes worktree, marks done
```

Parse `$ARGUMENTS`:
- First positional argument is `$TASK` — a natural-language task description (e.g., "Refactor the auth module to use JWT tokens").
- `--branch NAME` — override the auto-generated branch name. Auto-generated format: `omp/task-<slug>` where `<slug>` is derived from the task by lowercasing and replacing non-alphanumeric chars with hyphens.
- `--base-ref REF` — base ref to branch from (default: `HEAD`).
- `--list` — list all tracked worktrees (Manage mode).
- `--cleanup [ID]` — remove a specific worktree by ID, or if omitted, find and offer to batch-remove all "done" and "orphaned" worktrees.
- `--resume ID` — resume work in an existing worktree identified by its index ID.
- If `$TASK` is empty and no manage flag is provided, ask: "What task should I work on in an isolated workspace? Or use --list, --resume, or --cleanup."

## Key Files

| File | Role |
|------|------|
| `.claude/worktree-index.json` | Single shared index of all worktrees created by this skill. Always read and written under `flock` lock. |
| `.claude/worktree-index.json.lock` | Lock file for the index (used by `flock`). |
| `$WORKTREE_BASE/<id>/` | Worktree directory (default: `/tmp/omp-worktrees/<id>/`; falls back to `$REPO_ROOT/../.omp-worktrees/<id>/` if on a different filesystem). |

### Index Schema

A single JSON object at `$REPO_ROOT/.claude/worktree-index.json` (not per-worktree files):

```json
{
  "worktrees": {
    "<id>": {
      "branch": "omp/task-<slug>",
      "path": "$WORKTREE_BASE/<id>",
      "base_ref": "main",
      "task": "the original task description",
      "status": "active",
      "created": "2026-05-24T12:00:00Z",
      "completed": null
    }
  }
}
```

Status values: `"active"` (in progress), `"done"` (committed and cleaned up), `"orphaned"` (worktree directory missing but index entry remains).

## How to Start Each Session

1. **Find the repo root**: `cd "$(git rev-parse --show-toplevel)"`. Set `REPO_ROOT="$PWD"`. All index operations happen relative to this directory. If not in a git repo, report the error and stop.

1b. **Verify the worktree target is on the same filesystem** as the repo (git requires worktrees on the same filesystem as `.git`):
   ```bash
   WORKTREE_BASE="/tmp/omp-worktrees"
   if [ "$(stat -f -c '%d' "$REPO_ROOT" 2>/dev/null || stat -c '%d' "$REPO_ROOT")" != "$(stat -f -c '%d' "$WORKTREE_BASE" 2>/dev/null || stat -c '%d' "$WORKTREE_BASE")" ]; then
     WORKTREE_BASE="$(dirname "$REPO_ROOT")/.omp-worktrees"
     mkdir -p "$WORKTREE_BASE"
   fi
   ```

2. **Read the index under lock**:
   ```bash
   flock --exclusive --timeout 5 .claude/worktree-index.json.lock -c 'cat .claude/worktree-index.json' 2>/dev/null || echo '{"worktrees":{}}'
   ```
   If the index file doesn't exist yet, initialize it as `{"worktrees":{}}`. Store the parsed index in memory — do not re-read within the same session without reason.

3. **Determine mode**:
   - `--list`, `--cleanup`, or `--resume` → **Manage mode**.
   - `$TASK` is provided → **Execute mode**.
   - Neither → Ask the user what they want to do.

## Mode: Execute

Creates an isolated git worktree, executes the task within it, then offers to commit and clean up (or leave for review).

### Step 1 — Discover Existing Worktrees

1. Read the index under lock (see How to Start Each Session).
2. Cross-check with reality: run `git worktree list --porcelain` from `$REPO_ROOT`. Compare against the index:
   - Worktrees in the index but not in `git worktree list` → mark as `"orphaned"` in the index.
   - Worktrees in `git worktree list` but not in the index → flag to the user as untracked (e.g., Cursor or manually-created worktrees). Do not auto-add them to the index.
3. If `--branch NAME` was provided and an active worktree exists on that branch: print its status and ask "Resume this worktree instead?" If user confirms, jump to Step 3 (skip creation).

### Step 2 — Create the Worktree

1. Generate a unique ID: `<slug>-<timestamp>` where slug is the lowercased, hyphenated task name (capped at 32 chars), and timestamp is compact (`20260524T120000`).
2. Determine the branch name: `--branch NAME` if provided, otherwise `omp/task-<slug>`.
3. Set the base ref: `--base-ref REF` if provided, otherwise `HEAD`.
4. Set the worktree path: `$WORKTREE_BASE/<id>/` (use `$WORKTREE_BASE` from How to Start, not a hardcoded path).
4b. **Check for a dirty working tree** in the main worktree. Run `git status --porcelain` from `$REPO_ROOT`. If there are uncommitted changes:
   - Run `git stash push -m "agent-workspace: auto-stash before creating worktree for <id>"` to temporarily clean the tree.
   - Note the stash so it can be restored or mentioned to the user after worktree creation.
   - If stash fails (e.g., merge conflicts in progress), report the error and stop.
5. Create the worktree:
   ```bash
   cd "$REPO_ROOT"
   git worktree add -b "<branch>" "$WORKTREE_BASE/<id>" <base-ref>
   ```
   - If creation fails because the branch already exists: append a counter (`-2`, `-3`) to the branch name and retry.
   - If creation fails for any other reason: report the error and stop. Do not proceed without a worktree.
6. Copy gitignored config files if needed:
   - If `.worktreeinclude` exists in the repo root (gitignore-syntax whitelist, same format as Claude Code), copy matching files from the main worktree to the new worktree.
   - Always copy `.env` if it exists in the main worktree (most common missing-file pain point).
7. **Write the index under lock**:
   ```bash
   flock --exclusive --timeout 5 .claude/worktree-index.json.lock bash -c '
     jq ".worktrees[\"<id>\"] = {branch: \"<branch>\", path: \"$WORKTREE_BASE/<id>\", base_ref: \"<base-ref>\", task: \"<json-escaped-task>\", status: \"active\", created: \"<now-iso8601>\", completed: null}" .claude/worktree-index.json > .claude/worktree-index.json.tmp && mv .claude/worktree-index.json.tmp .claude/worktree-index.json
   '
   ```
   If `jq` is unavailable, use `python3 -c "import json, sys; d=json.load(open('.claude/worktree-index.json')); d['worktrees']['<id>']={...}; json.dump(d, open('.claude/worktree-index.json','w'))"`.
   Always use a temp file + mv pattern to avoid writing a partial JSON file on failure.

### Step 3 — Execute the Task

1. **Assert your working directory**: `cd "$WORKTREE_BASE/<id>"`. Every subsequent file operation happens relative to this worktree — not the original repo. If you need to read the index or run `git worktree list`, `cd` back to `$REPO_ROOT` first, then return to the worktree.

2. Do the work described by `$TASK`:
   - Use any available tool: Read, Edit, Write, Bash, Task (for subagents), Search, Find, LSP.
   - You may spawn Task subagents from within the worktree — they inherit the worktree cwd.
   - Stage changes incrementally with `git add`.
   - Respect all standard safety rules (no destructive commands without confirmation, no bypassing hooks, etc.).

3. The worktree provides full git isolation:
   - Your commits, branches, and staging area are independent of the main working tree.
   - Other concurrent agents in other worktrees cannot see your uncommitted changes.
   - You share the same `.git/objects/` — history and blob access is identical to the main repo.

### Step 4 — Complete

1. **Assert you're in the worktree**: verify `pwd` is the worktree path from the index. If not, `cd` to it.

2. Show a summary:
   - Branch name and worktree path.
   - Files changed: `git diff --stat <base-ref>..HEAD`.
   - Uncommitted changes: `git status --short`.

3. **Offer the choice to the user**: show the summary and ask:
   — Commit changes and clean up the worktree?
   — Leave worktree as-is for manual review? (worktree at `$WORKTREE_BASE/<id>`)

4. **If user chooses commit + cleanup**:
   - Stage any remaining changes: `git add -A`.
   - Commit: `git commit -m "<descriptive message based on the task>"`. Use a conventional commit format if the repo uses it.
   - Push: `git push origin <branch>` (if a remote exists and push is safe — never force-push).
   - `cd "$REPO_ROOT"` then remove the worktree: `git worktree remove "$WORKTREE_BASE/<id>" --force`.
   - Delete the branch: `git branch -D <branch>` (only after push succeeds, or skip delete if push failed).
   - Update index under lock: set `status` to `"done"`, set `completed` to now.

5. **If user chooses leave for review**:
   - Update index under lock: keep `status` as `"active"`.
   - Print: "Worktree left at `$WORKTREE_BASE/<id>` on branch `<branch>`. Resume with `--resume <id>`."

6. **Cleanup stale entries**: After updating the index, scan for any `"done"` entries older than 7 days and remove them from the index. Scan for `"orphaned"` entries, note them, and offer to `--cleanup`.

## Mode: Manage

For inspecting, resuming, and cleaning up worktrees across sessions. All operations happen from `$REPO_ROOT`.

### --list

1. Read the index under lock.
2. Cross-check with `git worktree list --porcelain` from `$REPO_ROOT`.
3. Print a table:

```
ID                  BRANCH              STATUS    TASK                     AGE
refactor-auth-2026… omp/task-refactor-… active    Refactor auth module    2h
fix-login-20260524… omp/task-fix-login  done      Fix login redirect bug  3d
```

4. Flag any discrepancies:
   - "N untracked worktrees found (not in index). Run `git worktree list` for details."
   - "N index entries marked orphaned (worktree directory missing). Use --cleanup to remove."

### --resume ID

1. `cd "$REPO_ROOT"`. Read the index under lock. Look up `<id>`.
2. If not found: report error, run `--list` to show available IDs.
3. If found but status is `"done"`: report that this worktree was already completed and cleaned up.
4. If found but status is `"orphaned"`: report that the worktree directory is missing — offer to remove the index entry.
5. If found and status is `"active"`:
   - Verify the worktree directory exists.
   - `cd` into the worktree path.
   - Print current state: branch, `git status --short`, `git diff --stat <base_ref>..HEAD`.
   - The user continues work interactively. When they finish, return to Execute Step 4 (Complete).

### --cleanup [ID]

1. `cd "$REPO_ROOT"`. Read the index under lock.
2. **If ID provided**:
   - Look up the ID. If not found, error.
   - Remove the worktree: `git worktree remove <path> --force`.
   - Delete the branch: `git branch -D <branch>`.
   - Remove from index under lock.
3. **If no ID**:
   - Find all entries with status `"done"` or `"orphaned"`.
   - Print a list and ask: "Remove these N worktrees and their index entries?"
   - On confirmation, remove each: `git worktree remove --force`, `git branch -D`, then clear from index under lock.

## Constraints

- **Directory awareness**: Always `cd` to `$REPO_ROOT` before index operations or `git worktree` commands. Always `cd` to the worktree path before task work. Check `pwd` at the start of each step.
- **Never create a worktree without checking the index first.** Always read the index before `git worktree add`.
- **Always lock the index file** (`flock --exclusive`) during every read and every write. Timeout after 5 seconds and report the lock contention if it fails.
- **Never write outside the worktree** during task execution. Edits, writes, and bash commands in Step 3 must stay within the worktree.
- **Never delete worktrees without user confirmation.** The `--cleanup` flag asks before batch-removing. Auto-cleanup only removes index entries for worktrees already deleted.
- **Commits require user approval.** Never auto-commit in Step 4 without the user's explicit choice.
- **No force-push to shared branches.** `git push --force` requires explicit confirmation and a warning.
- The index file is `.claude/worktree-index.json` at the repo root — no per-worktree files, no scattered state.

## TLDR

Creates isolated git worktrees, executes tasks in them, and tracks everything in one locked JSON index file. Before creating any worktree, always check what already exists. After work completes, offer the user a choice: commit + cleanup or leave for review. Supports `--list`, `--resume`, and `--cleanup` for multi-session management. Always be aware of which directory you're in — repo root for index/git ops, worktree for task work.
