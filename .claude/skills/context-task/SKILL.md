---
description: Create, edit, or delete ai_tasks tasks from the current conversation, including while a plan is being drafted
argument-hint: '[what to create/edit/delete]'
allowed-tools: mcp__ai_tasks_tasks_list, mcp__ai_tasks_tasks_read, mcp__ai_tasks_tasks_create, mcp__ai_tasks_tasks_update, mcp__ai_tasks_tasks_delete, mcp__ai_tasks_task_comments_create
---
Sync this conversation into ai_tasks project 11. If arguments were given, they dictate the changes; otherwise infer what to create, update, close, or delete from the conversation since the last sync.

Planning counts: while a plan is being drafted, decomposed, or revised, keep the board in step with it — create a card per work item as it appears, update the ones the plan changes, close the ones it drops. Do this during planning rather than after approval: plan mode's read-only rule covers the working tree, not the board. If the session's plan-mode rules block board writes anyway, say so instead of skipping silently.

Check open tasks first and update a match instead of duplicating. Write descriptions in markdown (`format: markdown`), standalone for a fresh reader, ending with a "Done when" line. Prefer marking done over deleting unless told to delete. Reply with one line per change: `#id title — action`.
