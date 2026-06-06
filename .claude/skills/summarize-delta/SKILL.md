---
description: Summarize code changes with a structured tree view of deltas and rationale
argument-hint: '[source] [path1] [path2]'
allowed-tools: bash, read, search, find
tool-hints: |
  bash: for git diff, git log, git show, git status, git stash, and directory diffs
  read: for structural summaries of files to understand their contents
  search/find: for locating files touched during the session
---

## Usage

**Invocation:** `/summarize-delta [source] [path1] [path2]`

Produces a structured, human-readable summary of changes: files modified, structures touched, individual deltas with rationale, and any overarching themes or next steps.

- `source` — what to diff. Interprets flexibly (see parsing below). When omitted, defaults to `HEAD`.
- `path1`, `path2` — for directory/`two repos` comparisons, the paths to compare.

**Examples:**
- `/summarize-delta` — Summarize unstaged + staged changes (git diff HEAD)
- `/summarize-delta commit` — Summarize the last commit
- `/summarize-delta abc1234` — Summarize changes in commit abc1234
- `/summarize-delta main..feature` — Summarize changes between main and feature
- `/summarize-delta this session` — Comprehensive summary of all AI changes in this session
- `/summarize-delta two repos /tmp/old /tmp/new` — Diff two directory trees

Parse `$ARGUMENTS`:
- First positional argument is `$SOURCE`. Interpret it as follows:
  - **Empty / missing**: default to `HEAD` — diff against HEAD (`git diff HEAD`).
  - **`HEAD`**: unstaged + staged changes (`git diff HEAD`).
  - **`commit` / `last` / `last commit`**: diff of the most recent commit (`git diff HEAD^ HEAD`).
  - **`this session`**: full session summary — reconstruct all changes from git status, session history, and file inspection (see Mode: Session Diff Summary).
  - **`two repos`**: diff two directories. `$PATH1` is the first path, `$PATH2` defaults to `.` (current repo root) if omitted. Run `git diff --no-index <path1> <path2>` or `diff -ruN <path1> <path2>` for a raw diff, then build the same structured summary.
  - **`<sha>`** (40-char hex, or 7+): diff of that commit (`git diff <sha>^ <sha>`).
  - **`<sha1>..<sha2>`** (contains `..`): range diff (`git diff <sha1> <sha2>`).
  - **Anything else**: attempt heuristic matching. Check if it looks like a file path (exists on disk), a ref name (`git rev-parse --verify --quiet`), or a stash reference. If none match, report "Unrecognized source: <value>" and list available options.
- `$PATH1` — first path for `two repos` comparisons.
- `$PATH2` — second path for `two repos` comparisons (optional, defaults to `.`).

---

## Mode: Git Diff Summary

Use this mode when `$SOURCE` is a git ref, sha, range, or empty (defaulting to HEAD).

### Phase 1 — Gather diff data

Determine the exact git command from `$SOURCE`:

| Source | Command |
|---|---|
| (empty) | `git diff HEAD` |
| `HEAD` | `git diff HEAD` |
| `commit` / `last` | `git diff HEAD^ HEAD` |
| `<sha>` | `git diff <sha>^ <sha>` |
| `<sha1>..<sha2>` | `git diff <sha1> <sha2>` |

Run the diff and capture the output. Also gather context:
- `git log --oneline -5` — recent history, to situate this diff in context.
- `git diff --stat` — quick file-level overview.
- For commit-specific diffs: `git log -1 --format="%h %s (%ai)" <sha>` — commit metadata.

If `git diff` exits with a non-zero status but produces output (normal for diffs that found changes), use the output. If it exits 0 with no output, report "No changes found" and exit.

### Phase 2 — Inspect changed files

For each file in the diff output:
1. Read the file using `read` with structural summary mode to understand its current structure (top-level declarations, sections, types, functions, config blocks, etc.).
2. Parse the diff hunks to understand exactly what changed. Identify the structural context (which function, section, or block each hunk belongs to).

### Phase 3 — Build the structured summary

Group changes by file. For each file, organize under a tree rooted at the file path.

For each structural section within a file that has changes:
- Show `+` for additions (new lines, keys, blocks).
- Show `-` for removals (deleted lines, keys, blocks).
- Use `→` for modifications (old value → new value).
- Append a parenthetical rationale for each change, inferred from the diff context and your understanding of the codebase.

Choose the best output format variant based on the kind of content:

**Config / data / YAML / JSON files** — tree view:
```
path/to/file.yaml
├── Section name
│   ├── + key: new_value                          (reason for addition)
│   ├── - old_key: old_value                      (reason for removal)
│   └── changed_key: old → new                    (reason for change)
└── Another section
    └── ...
```

**Code files (TypeScript, Rust, Python, etc.)** — structural summary:
```
path/to/module.ts
├── Function: parseConfig
│   └── → now returns Result<Config, Error>       (better error handling)
├── Interface: ConfigOptions
│   ├── + timeout: number                         (added configurable timeout)
│   └── - deprecated: boolean                     (removed unused field)
└── Class: Service
    └── + constructor(options)                    (injected dependency)
```

**Multiple files sharing a purpose** — impact summary:
```
┌─ Subsystem: API Routes (3 files changed)
│  ├── Added POST /api/users                      (user registration endpoint)
│  ├── Modified GET /api/users/:id                (added pagination)
│  └── Added middleware/auth.ts                   (JWT verification)
├─ Subsystem: Database (2 files changed)
│  ├── Added users table migration                 (schema for new endpoint)
│  └── Modified seed data                          (test user entries)
└─ Subsystem: Config (1 file changed)
    └── Added JWT_SECRET env var                   (required by auth middleware)
```

Prefer the variant that best communicates the *nature* of the change, not just the raw diff.

### Phase 4 — Present the summary

Render the complete summary to the user. Include:
1. **Scope header** — one line describing what was diffed (e.g., "Changes in last commit (abc1234):" or "Uncommitted changes (diff HEAD):").
2. **Structured tree view** using the chosen format variant(s).
3. **Rationale section** — if multiple changes share a common theme, add a brief paragraph explaining the overall intent (2-4 sentences).
4. **Next steps** (optional) — if the diff suggests obvious follow-up work (rebuilding images, running migrations, updating dependent configs), list them as a bulleted checklist.

---

## Mode: Session Diff Summary

Use this mode when `$SOURCE` is `"this session"`. Provides the most comprehensive summary of everything the AI has done, including uncommitted work, staged changes, recent commits, and any file writes detected from the session context.

### Phase 1 — Gather evidence

Collect from multiple sources in parallel:
1. `git status` — modified, staged, untracked files.
2. `git diff HEAD` — uncommitted changes.
3. `git diff --cached` — staged changes.
4. `git log --oneline -10` — recent commits made during the session.
5. `git stash list` — any stashed work.
6. **Session context scan**: review the session history for `edit`, `write`, `ast_edit`, `bash` (with file-modifying commands like `mv`, `cp`, `rm`, `sed`), and any other tool calls that create or modify files. Compile a list of every file touched.
7. Use `find` with recent mtime to locate any files modified in the last N minutes (set N to the session duration, e.g., 60 for the last hour). This catches files created outside git tracking.

### Phase 2 — Cross-reference and deduplicate

Merge all sources into a definitive list of changed files, each annotated with:
- Which sources reported it (git status, session history, mtime scan).
- Whether changes are committed, staged, unstaged, or untracked.
- The nature of the change (created, modified, deleted, renamed).

### Phase 3 — Inspect current state

For each changed file, read its current structure using `read` (structural summary mode). For committed changes, also inspect the commit diff to see the original state vs. current state.

### Phase 4 — Build the comprehensive summary

Group changes by file, then by structural section within each file. Use the same output format variants from Phase 3 of Git Diff Summary mode, adapted to show:
- Committed changes with commit sha reference.
- Staged or unstaged changes with a note about state.
- Untracked/new files with the full structural summary of what was created.
- Deleted files with what was removed.

Where multiple changes across files serve a single purpose (e.g., "added a user registration endpoint"), group them under a common rationale section.

### Phase 5 — Present

Render the summary. Include:
1. **Scope header** — "Changes made this session:" with a count of files and commits.
2. **Structured tree view** organized by subsystem or purpose.
3. **Commits made** — list of commit messages and shas if any were created.
4. **Uncommitted work** — any changes not yet committed, called out separately.
5. **Overall themes** — 1-3 sentences summarizing the session's objectives and how the changes achieve them.

---

## Output conventions

- Use `+` for additions, `-` for removals, `→` for modifications, `└─`/`├──` for tree structure.
- Each delta line gets a rationale in parentheses. If the rationale is obvious from the line itself (e.g., renaming a variable), a short note suffices. If non-obvious, add a sentence explaining intent.
- Keep the rationale concise — one line per change. If a change needs more explanation, add it to the Rationale section after the tree.
- Wrap rationale text at roughly 80 characters.
