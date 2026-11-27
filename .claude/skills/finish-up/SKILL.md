---
description: This skill make sure we don't have any left open context in this chat.
argument-hint: ''
allowed-tools: read, write, edit, bash, grep, find, glob, lsp, astgrep, task, ask, todo, websearch, webfetch, browser, eval, mcp__ai_tasks_find_action, mcp__ai_tasks_do_action, mcp__ai_tasks_tasks_list, mcp__ai_tasks_tasks_read, mcp__ai_tasks_tasks_create, mcp__ai_tasks_tasks_update, mcp__ai_tasks_tasks_delete, mcp__ai_tasks_task_comments_list, mcp__ai_tasks_task_comments_create, mcp__ai_tasks_task_comments_update, mcp__ai_tasks_labels_list, mcp__ai_tasks_projects_list, mcp__ai_tasks_projects_read, mcp__ai_tasks_users_search
---
Sweep before answering — answer what you can yourself instead of asking. Nothing is off limits here: arbitrary bash, any file, any board action — verify rather than speculating.

- Repo state: `git status`, `git diff --stat`, `git stash list`, `git worktree list` — anything uncommitted, stashed, or a worktree left behind?
- Chat state: any open todo items, background jobs, or `agent-*` timers still running?
- Board: open cards this chat touched (`mcp__ai_tasks_tasks_list`) — close finished ones, comment the result, create cards for real follow-ups. Anything the direct tools do not cover goes through `mcp__ai_tasks_find_action` then `mcp__ai_tasks_do_action`.
- Files: scratch/temp files we created, or docs the chat made stale.

Then answer plainly:

Anything else here? any cards to cleanup? any final remarks or thing we should urgently follow up on? Anything we might leave behind when we're done?

Especially: Are there any decisions that we made in this chat which we should write into docs? or into cards? or anything else? Write them now — Edit/Write for docs, `mcp__ai_tasks_tasks_create` for cards — instead of only proposing to.

You may ask questions.

Write a report on what you have done.

Then close on what the sweep actually found. The two endings are mutually exclusive — pick one:

- Sweep came back empty: nothing uncommitted or stashed, no worktree, process, timer or todo of ours left running, every card this chat touched closed or carded as a follow-up, every decision written down. Only then say "We are all done, exit".
- Sweep found something: a known bug left unfixed, a doc still contradicting reality, an open card, a process or worktree of ours still up, a decision not yet written down, anything you would call urgent or hand off. Then do not say "We are all done, exit". End with what remains, what it affects, what it would take to close it, and the decision or answer you need from the user.

The exit line is a verdict on the sweep, not a sign-off at the end of a chat. Never say it in the same breath as a fault, an open card, or anything urgent still in play — if you are still reporting unfinished work, you are not all done.
