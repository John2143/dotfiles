---
description: Generate a conventional commit message by analyzing staged changes
argument-hint: [scope] [--type (feat|fix|refactor|chore|docs|test|perf)]
allowed-tools: Bash
---

Parse `$ARGUMENTS`:
- If a positional argument is provided, treat it as `$SCOPE` — the commit scope (e.g., `auth`, `cli`, `nix`).
- If `--type TYPE` is provided, use it as the commit type. Valid values: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`.
- If no argument was given, auto-detect scope from the changed files.

---

## Procedure

### Step 1 — Get the diff
Run `git diff --staged` to get staged changes.

If nothing is staged:
- Ask the user whether to diff unstaged (`git diff`) or diff HEAD (`git diff HEAD~1`) instead.
- If the user declines both, exit.

### Step 2 — Analyze the diff
Extract from the diff:
- **What changed**: added, modified, deleted files.
- **Nature of change**: new feature, bug fix, refactor, configuration update, dependency bump, documentation, test changes.
- **Scope**: the subsystem or module most of the changes affect.
- **Scale**: small (1–3 files, simple changes) vs. medium vs. large.
- **Breaking changes**: API or behavior changes that would break existing callers.
- **Cross-cutting**: changes that span multiple subsystems.

### Step 3 — Generate the commit message

Format:
```
type(scope): description

body (optional)
```

- **type**: derived from the diff or from `--type` if explicitly provided.
  - `feat` — new feature for the user
  - `fix` — bug fix
  - `refactor` — code restructuring with no behavior change
  - `chore` — maintenance, tooling, CI, dependencies
  - `docs` — documentation only
  - `test` — adding or updating tests
  - `perf` — performance improvement
- **scope**: derived from file paths or from `--scope` if explicitly provided. Nix-related files default to `nix`.
- **description**: imperative mood, lowercase, no period, max ~50 chars. Summarize what was done, not why.
- **body**: include when:
  - Breaking changes (prefix with `BREAKING CHANGE:`)
  - Complex refactors that need rationale
  - Multi-file coordination that is not evident from the summary
  - Migration instructions if the change affects users

Wrap the body at 72 characters.

### Step 4 — Present to the user
Show the generated commit message and ask:
- Accept as-is?
- Change type?
- Change scope?
- Edit description?
- Add/remove body?

Apply any requested edits, then show the final message again.

---

## Output

The generated commit message in the following format:

```
type(scope): description

body
```

If no body is needed, omit the blank line and body entirely.
