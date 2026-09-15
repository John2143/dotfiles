---
description: Pack the session's non-obvious findings into the plan before handoff, so the fresh-context agent that executes it is not blind — run at the end of plan mode
argument-hint: "[--plan <path>] [--slug <name>] [--file]"
allowed-tools: ''
tool-hints: |
  No tools. Everything comes from your own memory of this session — never research, grep, or spawn subagents to fill a gap.
  Land the output with the plan-file write/edit you have been using in plan mode all along.
---

## Usage

**Invocation:** `/skill:pack-context [--plan <path>] [--slug <name>] [--file]`

The plan you are about to hand off is executed in a fresh context window: the next agent sees the file and nothing else. Everything you learned that the file does not say dies with this session. Pack it now, before you `resolve`.

- `--plan <path>` — explicit plan file to pack into. Overrides auto-detect.
- `--slug <name>` — name for the standalone context file (only used with `--file`).
- `--file` — write a separate `local://<slug>-context.md` plus one pointer line in the plan, instead of an in-plan section.

**Examples:**
- `/skill:pack-context` — pack into the plan this session has been writing.
- `/skill:pack-context --file --slug auth-refresh` — write `local://auth-refresh-context.md` and point the plan at it.
- `/skill:pack-context --plan local://auth-token-refresh-plan.md` — pack into an explicit plan file.

Parse `$ARGUMENTS`:
- `--plan <path>` — explicit target; overrides auto-detect.
- `--slug <name>` — slugify (lowercase, hyphens, collapsed, trimmed, ≤48 chars) for the `--file` output.
- `--file` — switch from the default in-plan section to a separate context file plus a pointer line.
- A bare argument is treated as `$SLUG`. No arguments → auto-detect the plan this session has been writing.
- Unknown flag → say so, then continue with auto-detect. Never guess what it meant.

---

## Mode: Pack Context

**Target.** Default to the plan file you have been writing this session — under plan mode that is `local://<slug>-plan.md` (the same slug you pass to `resolve` as `extra.title`). If you cannot name it and `--plan` was not given, report "no plan file to pack into" and STOP. Never invent a plan, never dump to the repo root.

**Pack only the surprises** — what a competent agent would burn time rediscovering:
- dead ends already ruled out, and why (so it does not re-walk them)
- traps and non-obvious invariants that cost you time
- decisions made under uncertainty, plus the fallback if the assumption breaks
- facts that contradict what the code superficially suggests
- environment quirks: fixtures, env vars, versions, ordering — anything required before it works
- anything you never actually confirmed, marked inline `unverified — confirm first`

**Drop** anything a `grep` or `read` answers, the goal, the plan's own steps, and anything the plan already says. Per line ask: *would a competent agent burn time rediscovering this?* No → drop it.

**Write** a `## Handoff Context` section immediately after the plan's `## Context` section (before `## Approach`), so the executor reads it before it starts. If a `## Handoff Context` section already exists, merge into it — never append a second one.

With `--file`, write `local://<slug>-context.md` instead and leave exactly one pointer line in that same position:

```
Handoff context (non-obvious findings): local://auth-refresh-context.md — read before starting.
```

**Style.** Imperative, addressed to the executor, bullets only. Target ~15 bullets / ~40 lines; past that you are restating, not packing.

Packing versus restating:

```markdown
## Handoff Context
- `src/auth/session.ts` looks like the source of truth but is not — `refreshToken()` is called
  from the middleware and its result overwrites the session cookie. Change both or neither.
- Tried fixing this in the interceptor first — dead end; it never sees the 401 because the
  client retries internally. Do not start there.
- Token TTL is read from `TOKEN_TTL` at boot only, so tests need a restart after changing it.
- Assumed refresh is idempotent; if it is not, gate it behind the existing `inflight` map.
```

A restatement would instead list the files, the goal, and the steps — all already in the plan.

**Report** 3 lines: target written, bullet count, anything left unverified.

## Constraints

- Only the plan file (or the `--file` context file) is written. No code, config, or system changes.
- Never include secrets, tokens, `.env` values, or credentials.
- Never research to fill a gap — if it is not in your memory, mark it `unverified — confirm first`.
- Do not turn this into a status report; the plan already carries status.