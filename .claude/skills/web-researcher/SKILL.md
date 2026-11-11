---
description: One-shot web research for one or more questions. Parses the arguments into questions, dispatches one web-research-orchestrator agent per question in parallel, and returns the finished cited reports — no research procedure lands in the main context.
argument-hint: '"[question 1]" "[question 2]" … [shared context for all of them]'
allowed-tools: read, bash, task, exit_loop_mode
tool-hints: |
  One question means one Task(web-research-orchestrator); N questions mean N of them in a single task call with parallel tasks[] entries.
  Never research inline and never decompose a question yourself — the orchestrator owns planning, subagents and the report under ai_research/{slug}/.
  Relay each run's answer, confidence, gaps and final_report.md path. Do not re-synthesize, rank, or merge the answers into prose of your own.
  Read a final_report.md only when the user asks for detail beyond what the run returned.
  Call exit_loop_mode(summary) once every report exists.
---

## Usage

**Invocation:** `/skill:web-researcher "[question 1]" ["question 2"] … [shared context]`

Every double-quoted span is one research question, and each gets its own orchestrator run, its own `ai_research/{slug}/` directory, and its own `final_report.md`. Text outside the quoted spans is shared context, passed verbatim to every run. Unquoted arguments are treated as one question.

**Examples:**
- `/skill:web-researcher "how effective are four-day work weeks?"` — one run
- `/skill:web-researcher "what changed in omp 18.18" "is bun stable for cli tools" "compare typst and latex for reports"` — three runs in parallel
- `/skill:web-researcher "compare hetzner and ovh" "what does attic cost" self-hosted only, exclude vendor blogs` — two runs, shared context on both

## Parse

Do not reason about quote positions — run the parser:

```bash
eval "$("$HOME/.omp/agent/skills/web-researcher/parse-args.py" << 'ARGSEOF'
<paste the raw $ARGUMENTS string here exactly as you received it>
ARGSEOF
)"
```

This sets parallel arrays `$QUESTIONS` and `$SLUGS`, plus `$COUNT`, `$CONTEXT`, and `$EMPTY`. Same-question slugs are already deduplicated, so sibling runs never collide on a directory.

## What to do

1. `$EMPTY` is `true` → ask "What would you like researched?" and stop. Nothing is spawned.
2. `$COUNT` greater than 8 → list the questions back and ask the user to confirm the run count before dispatching. Nine parallel research projects is a real bill.
3. Every question is a bare noun phrase with no askable claim ("kubernetes", "cake recipes") → ask one clarifying question and stop. If only some are bare, dispatch the answerable ones and say which you dropped.
4. Otherwise dispatch **all** questions in a single `task` call: one `tasks[]` entry per question, each `agent: web-research-orchestrator`, with the brief below. One spawn per question, never two. This is the whole job — no planning, no searches, no synthesis of your own.
5. When the runs return, relay each one as shown below. If some came back `## Blocked`, report those separately at the end; a blocked run does not invalidate the others.
6. Call `exit_loop_mode('Research complete — reports at {paths}')` if the tool exists; otherwise stop.

## Brief

Substitute the per-question values; `$CONTEXT` and the sibling count are identical in every brief. Add no research guidance of your own — the orchestrator carries the methodology.

```
# Research Run: {SLUG}

## Primary Question
{QUESTION}

## User Context
{CONTEXT verbatim, or "none"}

## Output Directory
ai_research/{SLUG}/ — every artifact goes inside it.

## Resume
If ai_research/{SLUG}/research_state.md exists, resume that project from its state file instead of starting fresh. If its phase_status is `done`, the project is finished: read the existing final_report.md and return it marked pre-existing; do not re-research or restart it.

## Sibling Runs
{COUNT} research runs are in flight in parallel, this one included. Keep your concurrent researchers at max(2, min(5, 12 / {COUNT})).

## Return
Your reply is a pointer: at most 200 words of answer, a confidence line, the path to final_report.md, and open gaps. Never paste the report body.
```

## Relay

For one question, relay the block as-is. For several, number them in the order given:

```
## 1. {question}
{answer, at most 200 words as returned}

**Confidence:** {High|Medium|Low} — {reason}
**Report:** ai_research/{slug}/final_report.md
**Gaps:** {open questions, or none}
```

Do not merge answers across runs, do not re-rank them, and do not add findings the orchestrators did not report. If the user wants a combined view, they will ask — that is a second, separate request.
