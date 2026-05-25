---
description: [Internal sub-skill] Execute one unit of implementation work — read the plan, make a focused change, verify, commit, and push. Standalone entry point for single-step fixes; for full multi-phase workflows, use `do-gh-issue` instead.
argument-hint: "[--fix finding-id]"
allowed-tools: Read, Write, Edit, Search, Bash, Find
tool-hints: |
  Use `read` with selectors to get fresh anchors before editing — hashes shift after prior edits.
  Use `edit` for all code changes — never sed -i or full-file rewrites.
  Use `search` to find stale references to old patterns after editing.
  Read `.gh-issue-state.json` and `local://PLAN.md` for context on what to do next.
  Commit with descriptive messages referencing the issue. Push after every change.
---

## Usage

**Invocation:** `/skill:gh-implement-step [--fix finding-id]`

- `--fix finding-id` — (optional) Prioritize fixing a specific review finding by ID instead of following the plan. If omitted, the next incomplete plan step or the highest-severity review finding is implemented.

**Examples:**
- `/skill:gh-implement-step` — Implement the next step from the plan or highest-severity review finding
- `/skill:gh-implement-step --fix C1` — Fix review finding C1 before continuing with plan steps
Parse `$ARGUMENTS`:
- If `--fix finding-id` is provided, prioritize fixing that specific review finding over plan steps.
- Otherwise, read state file and plan to determine the next step.
- If neither state file nor plan file exist, ask the user what to implement.

---

## Mode: Implement One Step

### Step 1 — Read context

1. Read `.gh-issue-state.json` for: `branch`, `plan_file`, `incomplete_steps`, `last_review_findings`.
2. Read the plan file for the step details.
3. Determine what to implement:
   - If `last_review_findings` has HIGH or CRITICAL entries → fix the highest-severity finding first.
   - If `--fix <id>` was passed → fix that specific finding.
   - Otherwise → pick the first item from `incomplete_steps`.
4. If nothing to implement: report "No remaining work items or findings" and stop.

### Step 2 — Re-read anchors

Before editing any file, re-read the exact lines you intend to modify. Example:
```
read(path="scripts/game_manager.gd:616-623")
```

Line hashes shift after prior edits from earlier invocations. Never reuse anchors from a previous session's output.

### Step 3 — Make the change

1. Make the minimal change that addresses the step or finding. One function, one module, one concern per invocation.
2. Use `edit` with exact anchors, not `write` (preserves formatting). If the step requires changes to multiple tightly-coupled lines in one file, make them in a single `edit` call. For changes across multiple files, edit one file per invocation.
3. Example edit:
   ```
   @scripts/game_manager.gd
   = 616ap..622uz
   ~static func clamp_launch_direction(dir: Vector2) -> Vector2:
   ~\tif dir == Vector2.ZERO:
   ~\t\treturn Vector2(0.0, -1.0)
   ~\t...
   ```

### Step 4 — Verify

1. Re-read the modified lines to confirm correct application.
2. Search for stale references: old function names, old constants, old threshold values that should have changed.
3. Attempt validation if tooling is available:
   - Check `AGENTS.md` for documented build/test commands.
   - Check `Makefile`, `package.json`, `Cargo.toml`, `project.godot`, `flake.nix` for build/test targets.
   - Run with a timeout (e.g., `timeout 60 <command>`).
   - If validation fails: read the error, fix, re-verify. Do not push failing code.
   - If no tooling available: note "Validation: not available" but do not block.
4. If the change doesn't compile or introduces obvious errors: fix before committing.

### Step 5 — Commit and push

1. `git add <files>`
2. Commit with descriptive message:
   ```
   git commit -m "<one-line summary>

   <explanation of what and why>

   Refs #<number>"
   ```
3. `git push origin <branch>`

### Step 6 — Update state

1. Remove the completed step from `incomplete_steps` or the fixed finding from `last_review_findings`.
2. If no more steps and no unresolved findings: set `phase: "review"`.
3. If findings were just fixed: set `phase: "review"` to trigger re-review.
4. Write the updated state file.

### Constraints

- One unit of work per invocation. Do not implement multiple unrelated steps.
- Never modify files outside the repo root.
- Never force-push or use `--no-verify` or `--no-gpg-sign`.
- If a single step requires touching more than 3 files: flag it — the plan step may be too large.
- If stuck (ambiguous plan step, unclear finding): surface the problem and stop — do not guess.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
- If `.gh-issue-state.json` is malformed or missing required fields: report the parse error, show the expected schema, and stop.
- If `git push` is rejected (non-fast-forward): report "Push rejected — branch may have diverged. Manual intervention needed." and stop.
