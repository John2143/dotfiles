---
description: One-shot web research. Hands the whole project to the web-research-orchestrator agent and returns the finished cited report, so no research procedure lands in the main context.
argument-hint: '"[primary research question]" [additional context, constraints, or focus areas]'
allowed-tools: read, bash, task, exit_loop_mode
tool-hints: |
  Spawn Task(web-research-orchestrator) exactly once per invocation — never research inline, never decompose the question yourself.
  The orchestrator owns the plan, subagents, audit trail and report under ai_research/{topic-slug}/; you only relay its result.
  Do not re-synthesize or re-verify the research: the orchestrator verified the sources. Read final_report.md only if the user asks for detail beyond the returned answer.
  Call exit_loop_mode(summary) after the report exists.
---

## Usage

**Invocation:** `/skill:web-researcher "[primary research question]" [additional context]`

The primary research question must be quoted. Everything after the closing quote is additional context, passed verbatim to the orchestrator.

Parse `$ARGUMENTS` with the deterministic parser — do not reason about quote positions:

```bash
eval "$("$HOME/.omp/agent/skills/web-researcher/parse-args.py" << 'ARGSEOF'
<paste the raw $ARGUMENTS string here exactly as you received it>
ARGSEOF
)"
```

This sets `$RESEARCH_QUESTION`, `$CONTEXT`, `$TOPIC_SLUG`, and `$EMPTY`.

## What to do

1. `$EMPTY` is `true` → ask "What is the primary research question?" and stop. Nothing is spawned.
2. `$RESEARCH_QUESTION` is a bare noun phrase with no askable claim ("cake recipes", "kubernetes") → ask one clarifying question and stop. This is the only question you get; everything else the orchestrator decides.
3. Otherwise spawn `task` with `agent: web-research-orchestrator` — once, with the brief below. This is the whole job: no plan, no searches, no synthesis of your own.
4. When it returns, relay its `## Answer`, `## Confidence`, `## Gaps`, and the report path. If it came back `## Blocked`, relay the blocker and options and stop without inventing a conclusion.
5. Call `exit_loop_mode('Research complete — {report path}')` if the tool exists; otherwise just stop.

## Brief

Pass this, substituting the parsed values. Do not add research guidance of your own — the orchestrator carries the methodology.

```
# Research Run: {$TOPIC_SLUG}

## Primary Question
{$RESEARCH_QUESTION}

## User Context
{$CONTEXT verbatim, or "none"}

## Output Directory
ai_research/{$TOPIC_SLUG}/ — every artifact goes inside it.

## Resume
If ai_research/{$TOPIC_SLUG}/research_state.md exists, resume that project from its state file instead of starting fresh. If its phase_status is `done`, the project is finished: read the existing final_report.md and return it marked pre-existing; do not re-research or restart it.

## Prior context
{repo or session context the user supplied, if any — omit the line when there is none}

## Return
Your reply is a pointer: at most 200 words of answer, a confidence line, the path to final_report.md, and open gaps. Never paste the report body.
```
