---
description: Split the plan into ordered HUMAN blocks (exact steps, questions, consent) and AI blocks that run unattended with rollback
argument-hint: "[--plan <path>]"
allowed-tools: Read, Write, Edit
---

Split the plan (`--plan <path>`, default `local://<slug>-plan.md`, the one this session writes) into one ordered sequence: replace its steps with `## Execution Blocks`, touch nothing else.

**AI** runs end to end with no human input: access present now, non-interactive, failure detectable and either recoverable by the agent or escalatable. **HUMAN** is everything else: a secret you lack, physical access, a UI without an API, a decision, spend, an outage window, an irreversible change needing approval.

HUMAN block — `### H1 — <title>`, **Why** (what it unblocks), **You do** (exact command or UI path), **Expect** (verbatim output), **Confirm** (go/no-go check), **Blocks**. Questions: **Question** + **Answer needed**. Consents: **Consent requested** + **Window** + **Approve by**.

AI block — `### A1 — <title>`, **Runs** (commands, end to end), **Done when**, **Rollback** (exact undo, or `read-only`), **If it fails** (stop, leave it rolled back, append a HUMAN block with the failing step, error, and what changed; then stop), **Retry** (flaky operations only).

Never invent a command — write the question that gets it. An AI block never asks anything mid-run. Report H/A counts, then stop.
