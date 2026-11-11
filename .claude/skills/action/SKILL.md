---
description: Boundary marker that ends the read-only phase (investigation/pontificate) so edits are allowed.
argument-hint: "[instruction]"
disable-model-invocation: true
---

This marks the boundary: the read-only phase is over. From here you may edit files and run commands that change state. Read-only constraints from earlier `/skill:investigation`, `/skill:pontificate`, or plan mode no longer apply.

Nothing else changes: harness approvals, safety rules, git worktree rules, and verification requirements still apply.

If `$ARGUMENTS` is empty, reply with one line confirming edits are unlocked, then wait for the instruction. Don't start on the plan or findings in context on your own.

If `$ARGUMENTS` is given, it is the instruction. Carry it out using the context from earlier in the session.
