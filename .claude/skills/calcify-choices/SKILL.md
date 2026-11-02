---
description: Pauses the current task to record the session's choices by who made them — user-driven choices become invariants, user-consented ones become recommendations — then resumes. Use when the user asks to calcify, lock in, or record decisions mid-task.
argument-hint: "[--plan <path>] [--card <id>] [--repo-file <path>]"
allowed-tools: Read, Write, Edit, mcp__ai_tasks_tasks_read, mcp__ai_tasks_tasks_update
---

Pause the task. From your memory of this session alone (never research to fill a gap), record every choice made so far, tiered by who made it, then resume with the invariants binding.

**Tiers** — use the user's strongest signal on each choice:
- **Invariant** (user drove it): an unprompted request, a typed answer, a rejection or correction (write as NEVER), a pick *against* your recommended option, or a consented choice they later restated in their own words. Change only with their approval.
- **Recommendation** (user consented): accepted your proposal, picked your recommended option, approved a plan (covers each item in it), or hedged their own idea ("maybe X"). The default; depart only with a stated reason.
- **Not decided**: silence, moving on, or your own call. Silence is not consent; never promote these.

The latest choice wins; note what it replaced. Every entry gets the user's verbatim quote (for a consent, their acceptance) and UTC time, or `paraphrased — unverified` / `time unknown`.

Write one `## Choices` section to each target: Invariants and Recommendations as `When | Choice | Quote` tables, Not decided as a list. Merge into any existing choices or decisions section.
- **Plan**: the plan file this session is writing, else `local://<slug>-choices.md`. `--plan` overrides.
- **Card**: the board card this work belongs to; description only, `format: markdown`. `--card` overrides.
- **Repo**: an existing decisions/ADR file, else `docs/decisions.md`; only choices that outlive this task; never commit. `--repo-file` overrides.

Skip a target you can't write (no card, no git repo, plan mode) and say so. Report one line per target plus tier counts, then resume. Choices only — no status or findings.
