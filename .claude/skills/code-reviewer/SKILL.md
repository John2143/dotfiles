---
description: "General-purpose code review with parallel analysis personas (security, duplication, patterns, functionality, goals)"
argument-hint: "[@path | --focus persona1,persona2]"
allowed-tools: Read, Search, Find, Bash, LSP, Task
tool-hints: |
  Use `git diff HEAD` or `git diff master...<branch>` to collect changes.
  Use `read` to inspect changed files in full — a diff snippet alone is insufficient.
  Use `search` or `lsp references` to cross-reference callers and callees.
  Use Task subagents to run personas in parallel.
  Use `git symbolic-ref --short HEAD` to determine the current branch.
  Read `AGENTS.md` or `CLAUDE.md` if present for project-specific conventions.
  This skill is read-only — never modify files.
---

Parse `$ARGUMENTS`:
- If `$ARGUMENTS` contains a path matching `@` followed by a file path (e.g., `@./src/handler.ts`), extract the path and enter **Single-File Review** mode. The `@` prefix is a harness convention for file attachments; treat the path as the single review target.
- If `$ARGUMENTS` contains `--focus <comma-separated-list>`, store the list. Valid values: `security`, `duplication`, `patterns`, `functionality`, `goals`. If no `--focus` is given, all five personas run.
- If no file path is provided, enter **Diff Review** mode: infer the diff target automatically (see Phase 1).
- If `$ARGUMENTS` is `--help`, print the description and usage, then stop.
- Run `git rev-parse --git-dir`. If it fails, print "Not in a git repository. code-reviewer requires a git repo." and stop.

---

## Severity Criteria

Every finding must be assigned one of these severities:

| Level    | Definition |
|----------|------------|
| CRITICAL | Data loss, security breach, unrecoverable crash, or corruption. The change must not ship with this issue. |
| HIGH     | Bug that affects correctness under normal use, missing critical error handling, or observable regression. |
| MEDIUM   | Maintainability gap, duplicated logic that will cause drift, unclear intent that invites future bugs. |
| LOW      | Naming nit, style inconsistency, minor redundancies. |
| INFO     | Positive observation — a pattern done well that should be preserved or replicated. |

If no issues in a category, state "No issues found." Do not invent LOW findings to pad the list.

---

## Mode: Diff Review

The default mode. Infer the diff target from git state.

### Phase 1 — Determine the diff target

1. Run `git diff HEAD --stat`. If it produces output, use `git diff HEAD` as the review diff. Set `SOURCE = "git diff HEAD (staged + unstaged changes)"`.
2. If `git diff HEAD --stat` is empty, run `git symbolic-ref --short HEAD` to get the current branch. If the branch is NOT `master` or `main`, run `git diff master...HEAD --stat`. If it produces output, use `git diff master...HEAD` as the review diff. Set `SOURCE = "git diff master...HEAD (branch changes against master)"`.
3. If both are empty, print "No changes to review. Nothing staged, unstaged, or on a feature branch vs master." and stop.
4. Collect the full diff text with `git diff <target>` (no `--stat`).
5. Count total changed lines (sum of added + deleted from `--stat` output). Set depth:
   - <100 lines → **deep** (trace callers, check tests, verify contracts)
   - 100-500 lines → **moderate** (standard analysis, spot-check tests)
   - >500 lines → **shallow** (surface analysis: bugs, anti-patterns, obvious issues)
6. Get the list of changed files: `git diff <target> --name-only`.
7. Check for `AGENTS.md` or `CLAUDE.md` in repo root. If present, read it for project conventions.

### Phase 2 — Classify and weight

Read each changed file (the full file, not just the diff). Classify changes by domain to weight each persona. Use this mapping:

| Signal in diff | Weight adjustments |
|----------------|-------------------|
| Auth, tokens, credentials, crypto, env vars, config secrets | **Security** +2 (deep even if diff is large) |
| New files, new modules, new abstractions | **Duplication** +2, **Patterns** +1 |
| `.test.`, `__tests__`, `spec/`, assertion changes | **Functionality** +2 |
| Refactors (no new logic, same tests pass), renames, moves | **Patterns** +2, **Goals** +1 |
| Docs, comments, README | **Goals** +1, de-prioritize others |
| Infrastructure, CI, Docker, Nix | **Security** +1, **Duplication** +1 |
| Error handling, logging, observability | **Functionality** +1 |
| No clear signal | Equal weight on all |

Weight determines how deeply that persona investigates, not whether it runs. A persona with +0 still runs but does surface-level checks unless the depth is already deep.

### Phase 3 — Run personas in parallel

Spawn up to 5 Task subagents — one per persona enabled by `--focus`. Each subagent receives:
- The full diff text and the list of changed files.
- The depth setting and their weight adjustment.
- The project conventions from `AGENTS.md` / `CLAUDE.md` if found.
- The finding format and severity criteria.

If `--focus` restricts which personas run, only spawn those subagents.

**Persona 1 — Security Researcher:**
- Injection: SQL, command, template, XSS, path traversal — wherever external input reaches an interpreter.
- Auth: missing checks, bypasses, hardcoded credentials, JWT misconfigurations, weak session management.
- Secrets: keys, tokens, passwords in source, logs, or error messages.
- Input validation: missing or insufficient, type confusion, integer overflow.
- Cryptography: weak algorithms (MD5, SHA1 for security, DES, RC4), ECB mode, hardcoded IVs/nonces, missing certificate validation.
- Infrastructure: dangerous defaults in Dockerfiles, CI configs, Kubernetes manifests.

**Persona 2 — Duplication & Reusability Specialist:**
- Copy-pasted blocks within the diff.
- Existing abstractions in the codebase that duplicate the new code's purpose.
- Opportunities to extract shared helpers or utilities.
- Identical logic with different names in different files.
- Use `search` to find pre-existing similar code.

**Persona 3 — Patterns Checker:**
- Naming consistency with surrounding code and project conventions.
- File/module organization — does the new code belong where it is?
- Error handling patterns — consistent with the rest of the project?
- Use of deprecated or discouraged APIs.
- Idiomatic code for the language (use LSP diagnostics for guidance).
- Design patterns — is the approach standard for this codebase?

**Persona 4 — Functionality Tester:**
- Edge cases: null/missing inputs, empty collections, boundary values.
- Error states: are error paths handled or silently swallowed?
- Race conditions: shared mutable state, async ordering assumptions.
- State management: is state initialized, cleaned up, and consistent across paths?
- Tests: missing test coverage for the changed code, tests that pass but don't assert anything meaningful.
- Backward compatibility: does this change break existing callers?

**Persona 5 — Acceptance Criteria / Goal Reviewer:**
- Does the diff actually solve the problem it claims to solve?
- Commit message clarity and accuracy.
- Scope creep: changes unrelated to the stated goal.
- Documentation: missing updates to README, comments, or API docs.
- If a PR/issue reference is in the commit message, check alignment.

### Phase 4 — Synthesize

Collect all subagent outputs. For each:
1. **Deduplicate** — same file, same line range, same problem class → merge into one finding. If severity differs between personas, use the higher severity.
2. **Sort** by severity: CRITICAL → HIGH → MEDIUM → LOW → INFO.
3. **Compile per-persona sections** — group findings under their persona header. If a persona found nothing, write "No issues found."
4. **Produce a unified findings table** with columns: `# | Severity | File:Line | Persona | Problem | Fix`.
5. **Write the final report** using the format below.

### Report Format

```
## Code Review — <SOURCE>

### Summary
- **Changed files:** N
- **Lines changed:** +X / -Y
- **Depth:** deep | moderate | shallow
- **Personas run:** security, duplication, patterns, functionality, goals

### Executive Summary
(2-3 sentences: what this change does, the biggest risk, overall quality assessment)

### Findings

| # | Severity | File:Line | Persona | Problem | Fix |
|---|----------|-----------|---------|---------|-----|
| 1 | HIGH | src/foo.ts:42 | security | SQL injection via unsanitized input | Use parameterized query |
| 2 | MEDIUM | src/bar.ts:15 | duplication | Identical logic in utils.ts:30 | Extract shared helper |

### Security
(Findings from the Security Researcher persona)

### Duplication & Reusability
(Findings from the Duplication Specialist persona)

### Patterns & Conventions
(Findings from the Patterns Checker persona)

### Functionality & Testing
(Findings from the Functionality Tester persona)

### Goals & Completeness
(Findings from the Goal Reviewer persona)

### Verdict
**merge** — No blocking issues.
OR
**merge-with-revisions** — N findings that should be addressed before merge (list the HIGH/CRITICAL items).
OR
**do-not-merge** — N CRITICAL findings (list them).
```

---

## Mode: Single-File Review

For `@./path/to/file` input. Deep review of one file with LSP-powered call hierarchy.

### Phase 1 — Gather context

1. Verify the file exists. If not, print "File not found: <path>" and stop.
2. Read the full file.
3. Run `git log --oneline -10 -- <path>` for recent related commits.
4. If the file is tracked by git, get its diff if it has uncommitted changes: `git diff HEAD -- <path>`.
5. Check for `AGENTS.md` or `CLAUDE.md` in repo root. If present, read it.

### Phase 2 — Trace relationships via LSP

1. For each exported/public symbol in the file, use `lsp references` to find callers.
2. For each external symbol the file imports/calls, use `lsp definition` to locate the callee and `lsp hover` for type/signature info.
3. Use `lsp diagnostics` on the file for compiler/linter warnings.

Limit: if the file has more than 20 exported symbols, trace only the 10 most recently modified (by git blame) plus any that appear in the uncommitted diff.

### Phase 3 — Run personas

Same persona subagents as Diff Review, but scoped to:
- The single file's content.
- Its immediate callers and callees (from Phase 2).
- The git diff of the file if it has uncommitted changes.
- Weight all personas equally (single-file is always **deep**).

### Phase 4 — Synthesize

Same synthesis as Diff Review Phase 4. Replace `<SOURCE>` in the report header with the file path.

### Report Format

Same as Diff Review, but header reads:

```
## Code Review — <file-path>
```

---

## Constraints

- **Read-only** — never modify files, never commit, never push.
- Do not run destructive git commands (rebase, reset, clean, stash).
- Stay within repo boundaries.
- Do not ask questions mid-review. Produce the full review in one pass.
- If uncertain about a finding, mark it LOW and state the uncertainty.
- If the diff is larger than 2000 lines, note the truncation: "Diff exceeds 2000 lines — review focuses on high-signal changes. Some files were not exhaustively reviewed."
- Do not post findings to GitHub, Slack, or any external service. Output is chat-only.
