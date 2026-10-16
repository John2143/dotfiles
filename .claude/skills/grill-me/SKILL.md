---
description: Interview the user in rounds about a plan, decision, or idea until every branch is resolved
argument-hint: "[topic]"
disable-model-invocation: true
allowed-tools: Read, Search, Find, Task, WebSearch, Ask
license: MIT
metadata:
  author: Matt Pocock
  copyright: "Copyright (c) 2026 Matt Pocock"
  source: https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling
# Bash is left out of allowed-tools on purpose: Claude Code pre-approves listed tools without prompting.
---

The topic is the skill argument (`$ARGUMENTS`). If it is empty, grill the plan or idea already in the conversation. If there is none, ask what to grill and stop.

Read-only for the whole session: read, search, web search, and commands that change nothing. Never write, edit, or run anything that changes state.

## Rounds

Map the topic as a design tree: each decision opens the decisions that depend on it. The frontier is every decision whose prerequisites are settled. Ask the whole frontier in one message, in plain chat (the ask tool is fine too):

**Q<n> - <title>:** <question, with options if there are any>
**Recommended:** <your answer>

- Word each question so "yes" accepts the recommendation. Number Q1, Q2, … straight through the session.
- A question that depends on another question still open this round waits for the next round.
- Facts are your job: look them up (quick ones directly, slow ones with a background Task(explore)) and never ask the user for them. A pending lookup holds back only the questions that depend on it.
- Decisions are the user's. Silence or moving on is not a yes; unanswered questions stay open.
- After each answer, recompute the frontier and ask the next round. There is no cap on questions.

## End

When the frontier is empty, or the user says stop, print:

**Decisions**
- <decision>

**Open**
- <unanswered question, or "none">

Then stop. Do not act on it or write files until the user confirms you are aligned.
