---
description: Generate or update an AGENTS.md file documenting project architecture, conventions, testing workflow, and patterns for autonomous coding agents
argument-hint: "[--update]"
allowed-tools: Read, Write, Search, Find, Task
tool-hints: |
  Use `find` to discover build files, config files, and source directories.
  Use `Task(explore)` to scout subsystems in parallel — each gets one source directory.
  Use `read` to extract conventions from existing code and configs.
  Write `AGENTS.md` to the repo root. Never modify source files.
---

Parse `$ARGUMENTS`:
- If `--update` is provided, read existing `AGENTS.md` and update stale sections rather than regenerating.
- If no arguments, generate a new `AGENTS.md` from scratch.

---

## Mode: Generate Context File

### Step 1 — Discover project structure

1. Use `find` to discover build/config files:
   ```
   find(pattern="Makefile")
   find(pattern="package.json")
   find(pattern="Cargo.toml")
   find(pattern="project.godot")
   find(pattern="flake.nix")
   find(pattern="go.mod")
   find(pattern="pyproject.toml")
   ```
2. Use `find` to discover key directories (at depth 1):
   ```
   find(pattern="src/")
   find(pattern="lib/")
   find(pattern="scripts/")
   find(pattern="nixos/")
   find(pattern="modules/")
   find(pattern="tests/")
   find(pattern="docs/")
   ```
3. Check for existing docs: `find(pattern="README.md")`, `find(pattern="CONTRIBUTING.md")`.
4. Launch 1-2 `Task(explore)` subagents to scout main subsystems. Each gets one source directory and reports: language, key abstractions, file organization, naming conventions.

### Step 2 — Extract conventions

From the discovered files and existing code, extract:

- **Language/ecosystem**: what languages, runtimes, package managers are used
- **Build system**: exact commands to build, test, lint
- **Directory layout**: what lives where and why
- **Code patterns**: naming conventions, file organization, error handling style, import patterns
- **Testing patterns**: where tests live, how to run them, what framework
- **Gotchas**: coordinate system quirks, deprecated APIs, platform-specific behavior, things an agent might assume incorrectly
- **Non-goals**: files or directories agents must never touch

### Step 3 — Write AGENTS.md

Write to `AGENTS.md` in repo root. Template:

```markdown
# AGENTS.md — Project Context for Autonomous Coding Agents

## Project overview
<2-3 sentences describing what this project is and its primary domain>

## Build & validation
- Build: `<command>`
- Test: `<command>`
- Lint: `<command>`

## Directory layout
- `src/` — <description>
- `scripts/` — <description>
- `tests/` — <description>

## Conventions
- Naming: <convention>
- Error handling: <pattern>
- File organization: <pattern>
- <any other conventions>

## Gotchas
- <thing agents commonly get wrong>

## Non-goals (do not touch)
- <files/directories to avoid>
- <patterns to never introduce>
```

If `--update`: read existing file, identify sections that are stale (commands changed, directories renamed, new gotchas discovered), update only those sections. Preserve all human-written content.

### Step 4 — Report

List what was generated or updated. Example:
```
Generated AGENTS.md with:
- Build command: godot --headless --check-only
- 3 gotchas documented (Godot y-down coordinates, normalized() returns Zero for zero vectors, sign(0) returns 0)
- 2 non-goals (export/ directory, .import files)

Agents using do-gh-issue or gh-implement-step will read this file for project conventions.
```

### Constraints

- Never modify source files. This skill only writes `AGENTS.md`.
- If `AGENTS.md` already exists and `--update` was not passed, ask before overwriting.
