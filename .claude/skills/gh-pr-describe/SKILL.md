---
description: Update a PR body with AI-attribution metadata — what the agent did, what assumptions were made, what was not verified, and what requires human attention
argument-hint: "[--pr number]"
allowed-tools: Bash, Read
tool-hints: |
  Use `gh pr view <number>` to read the current PR body.
  Use `gh pr edit <number> --body "..."` to update it. Never delete human-written content.
  Read `.gh-issue-state.json` for workflow context (phases completed, findings history).
  Get commit log with `git log main..<branch> --oneline`.
---

Parse `$ARGUMENTS`:
- `--pr number` — PR number to update.
- If omitted, read `.gh-issue-state.json` for `pr_number`.
- If no PR number is determinable, ask the user.

---

## Mode: Describe PR

### Step 1 — Gather context

1. Read state file: `.gh-issue-state.json` for `issue_number`, `issue_title`, `phase` history, `branch`.
2. Read current PR body: `gh pr view <number> --json body,title`.
3. Get commit history: `git log main..<branch> --oneline`.

### Step 2 — Determine AI attribution

For each commit, classify the agent's role:

| Pattern | Role |
|---|---|
| New files, new functions, new constants | Full generation from plan |
| Modified existing functions with behavior change | Refactor or fix |
| Changes directly addressing a review finding | Review fix |
| Test-only changes | Test generation |

Count phases completed from the state file (discover, plan, implement, review, fix).

### Step 3 — Identify what needs human attention

From the state file and plan, list:

- **Assumptions**: design choices made (e.g., "clamp rather than reject"), edge cases handled, constraints accepted.
- **Not verified**: things that could not be tested (e.g., "Godot headless check timed out in NixOS environment — manual testing recommended").
- **Human attention needed**: areas requiring judgment (e.g., "balance tuning: is 20° the right threshold? Adjust `MIN_LAUNCH_ANGLE` constant if needed").

### Step 4 — Update PR body

Prepend an AI-attribution section to the existing PR body. Preserve all human-written content.

```
gh pr edit <number> --body "## AI attribution

**Role**: Full implementation from plan with self-review and fix cycle
**Phases**: Discover → Plan → Implement → Self-review → Fix (Vector2.ZERO edge case) → Re-review
**Commits**: 2 (initial implementation, edge case fix)
**Assumptions**:
- Chose clamping over rejection for better UX — user confirmed
- 20° threshold from horizontal; tunable via MIN_LAUNCH_ANGLE constant
**Not verified**: Godot headless check timed out; manual testing recommended
**Human attention needed**:
- Confirm 20° threshold feels right in gameplay
- Verify ball physics after bounce (unstick() threshold at ~17.5°, close but not identical)

---

<original PR body>"
```

### Constraints

- Never remove human-written content from the existing PR body. Only prepend the attribution section.
- Be honest about what was not verified. Do not claim tests passed if they were not run.
- If you don't know the agent's role for a particular change, mark it as "Unknown — human should verify."
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
