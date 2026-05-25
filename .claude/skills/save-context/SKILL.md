---
description: Compress the current session context into portable files so another agent can resume where this session left off
argument-hint: [--name <context-name>]
allowed-tools: Read, Write, Find, Task, Bash
tool-hints: |
  Use `read` to inspect workspace artifacts (recent files, git log, diffs).
  Use `Task(quick_task)` subagents to gather context dimensions in parallel.
  Use `write` for output files. Use `mktemp` for the temp copy.
  Never include secrets. Only write output context files — never modify source.
---

You are the agent whose session is being saved. You have access to your own conversation history (everything the user said and you did), the current workspace state (files, git history, open artifacts), and the tools listed above. Your job is to introspect this session and compress the essential parts into portable files so another agent can read them and pick up where you left off.

## Usage

**Invocation:** `/skill:save-context [--name <context-name>]`

Compresses the current session context into portable files so another agent can resume where this session left off. Gathers git state, recent artifacts, open questions, decisions, and next steps via parallel subagents, then writes a structured `context-<name>.md` file to the repo root and a temp copy.

- `--name <context-name>` — A short descriptive name for the context (e.g., `fix-nginx-config`). Slugified automatically: lowercase, hyphens, truncated to 48 chars.
- If `--name` is omitted, the skill asks for a name.

**Examples:**
- `/skill:save-context --name fix-nginx-ssl` — Save context with an explicit name
- `/skill:save-context` — Prompt for a context name, then save

Parse `$ARGUMENTS`:
- If `--name NAME` is provided, use it as the context name. Slugify: lowercase, hyphens for non-alphanumeric characters, collapse consecutive hyphens, strip leading/trailing hyphens, truncate to 48 chars.
- If omitted, ask the user for a short descriptive name (e.g., "fix-nginx-config", "k3s-migration-plan"). Slugify the response.
- If the slugified name is empty after processing, ask the user to provide `--name` explicitly.

---

## Mode: Save Session Context

### Step 1 — Check for existing context file

Check whether `context-<name>.md` already exists at the repo root:
```
find(pattern="context-<name>.*")
```
If it exists, ask the user: overwrite, rename (provide a new name), or abort.

### Step 2 — Gather raw context (parallel)

Launch 3-4 `Task(quick_task)` subagents to collect distinct context dimensions in parallel. Each subagent is read-only and returns its findings as structured text.

**Subagent A — Git State**
- Run `git status --short`, `git branch --show-current`, `git log --oneline -10`, `git diff --stat`, and `git stash list`.
- Return: branch name, modified/untracked file list, last 10 commits (one per line), diff stat, any stashed changes.
- If `git` is unavailable: return "git not available" and skip git-derived fields. If the repo has no commits yet: return "no commits yet" and use `git status` alone.

**Subagent B — Recent Artifacts**
- Use `find` to discover files modified in the last 24 hours. Use `read` to inspect the 10 most recently changed non-binary files for size and first 5 lines.
- Return a table: path, size, last modified, brief description (what the file is). Skip `.git/`, `node_modules/`, and other build artifacts.

**Subagent C — Open Questions & Decisions**
- From the session conversation, extract: (1) what the user asked for originally, (2) key decisions made so far, (3) approaches that were explicitly ruled out and why, (4) open questions or unresolved design choices, (5) explicit constraints the user set.
- Return structured list under headers: Goal, Decisions, Ruled Out, Open Questions, Constraints.

**Subagent D — Next Steps**
- Based on the session conversation and what files are modified, determine: (1) what remains to be done, (2) what the next concrete action should be, (3) any blockers or dependencies, (4) verification criteria — how will we know it's done?
- Return a checklist of next steps ordered by priority, with a clear "pick up here" pointer.

Collect all subagent outputs. Do not proceed until all return. If a subagent times out or fails, note the gap and continue.

### Step 3 — Compress into structured output

Assemble the gathered context into a single Markdown file. For data-heavy sections (file lists, git state), embed tables or fenced code blocks within the Markdown.

Angle-bracket values like `<name>`, `<branch>`, `<date>` below are placeholders — replace them with actual values. Everything else is literal output.

Required sections (in order):

```markdown
# Context: <name>

> Saved <date> from branch `<branch>` by `<user>`

## Goal
<1-3 sentences: what this session is trying to accomplish>

## Current State
- **Branch**: `<branch>`
- **Modified files**: <count> files (<list key paths>)
- **Last commit**: `<hash> <message>`

## Key Decisions
| # | Decision | Rationale |
|---|----------|-----------|
| 1 | <decision> | <why> |

## Ruled Out
| Approach | Why rejected |
|----------|-------------|
| <approach> | <reason> |

## Open Questions
- [ ] <question>
- [ ] <question>

## Recent Artifacts
| Path | Description | Last Modified |
|------|-------------|---------------|
| <path> | <desc> | <time> |

## Constraints
- <constraint from user>
- <constraint from environment>

## Next Steps
1. [ ] **Pick up here**: <concrete first action>
2. [ ] <next action>
3. [ ] <next action>

## Verification
- <how we'll know this work is complete>
```

### Step 4 — Sanitize

Before writing, scan the assembled content for:
- Secrets: tokens, API keys, passwords, private keys, age-encrypted content, `.env` values.
- Personal data: email addresses in plaintext (redact to `<user>`), IP addresses in non-config contexts.
- Replace any secrets with `<redacted — secret>` and note the redaction at the bottom of the file.

### Step 5 — Write output files

Write the sanitized content to two locations:

1. **Repo file** (tracked in git):
   ```
   write(path="context-<name>.md", content=<assembled-markdown>)
   ```
   Then stage it: `git add context-<name>.md`

2. **Temp file** (ephemeral, for cross-session handoff):
   ```bash
   mktemp context-<name>-XXXXXXX
   ```
   Write the same content to that path using `write`.

### Step 6 — Report

Present to the user:

```
Context saved as "context-<name>.md"
  Repo:   context-<name>.md (staged in git)
  Temp:   /tmp/context-<name>-<random>
  Size:   <N> lines, <M> KB
  Captured: <N> decisions, <M> next steps, <K> artifacts
```

If the temp file was not written (e.g., `mktemp` failed), note it but don't block — the repo file is the primary artifact.

---

## Output

- `context-<name>.md` — primary context file at repo root, staged in git
- `/tmp/context-<name>-XXXXXXX` — temp copy via `mktemp`

## Constraints

- **Never include secrets**. Scan for tokens, keys, passwords, private keys, age-encrypted content, and `.env` values. Redact them.
- **Only write context files**. Do not modify source files, configs, or any files not produced by this skill.
- **If a subagent fails** (timeout, error), note what was missing in the context file under a `## Missing` section and continue with what you have. Do not block on subagent failures.
- **Keep it complete, not minimal**. Context files may be as large as needed (up to tens of MB) to retain all necessary context. Prefer completeness over brevity — a context file that omits critical detail leaves the next agent guessing. The only size limit is what remains usable: if the file exceeds ~50 MB, warn the user before writing.

## Example

User runs: `save-context --name fix-nginx-ssl`

The agent discovers they've been debugging an nginx SSL configuration issue. Subagents report: 2 decisions made (switch to Let's Encrypt, use acme.sh), 3 approaches ruled out (self-signed certs, paid CA, Cloudflare origin certs), 5 files modified (nginx config, firewall rules, acme hook script), and 4 remaining steps. The agent writes `context-fix-nginx-ssl.md` (87 lines, 3.2 KB), stages it, and also writes to `/tmp/context-fix-nginx-ssl-a1b2c3d`. Reports: "Context saved — 2 decisions, 4 next steps, 5 artifacts."
