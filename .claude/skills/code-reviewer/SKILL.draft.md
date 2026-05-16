---
description: "General-purpose code review with multiple analysis personas"
argument-hint: "[@path | --focus persona1,persona2]"
allowed-tools: Read, Bash, Search, Find, LSP, Task, Edit
tool-hints: "LSP: use for call hierarchy and references. Bash: git log, git diff, git blame. Task: run personas in parallel."
---

Parse `$ARGUMENTS`:
- If `@./path/to/file` is present → single-file deep review mode (trace callers/callees via LSP).
- If no arguments → run `git diff HEAD`. If empty, check branch; if not master/main, run `git diff master...HEAD`.
- If still empty → error: "No changes to review."
- `--focus` flag optionally restricts which personas run (comma-separated: security,duplication,patterns,functionality,goal).

---

## Mode: Code Review

### Phase 1 — Scope the review
- Collect the diff content.
- Count total changed lines → set depth: <100 lines = deep, 100-500 = moderate, >500 = shallow.
- Classify changes by domain (auth, config, API, tests, docs, etc.) → weight each persona accordingly.
- If single-file mode (`@path`): also collect related callers/callees via LSP.

### Phase 2 — Run personas in parallel
Use Task subagents for each persona.

**Security Researcher:**
- Injection vectors (SQL, command, template, XSS)
- Auth/authz bypasses, missing access controls
- Secrets or credentials in code
- Unsafe input handling, missing validation
- Cryptography misuses (weak algorithms, nonce reuse, timing)

**Duplication & Reusability Specialist:**
- Copy-pasted code blocks
- Existing abstractions that should be used instead
- DRY violations at module level
- Opportunities for extraction into shared utilities

**Patterns Checker:**
- Project conventions and idioms
- Naming consistency with surrounding code
- File/module organization
- Error handling patterns
- Use of deprecated or discouraged APIs

**Functionality Tester:**
- Edge cases not covered
- Null/undefined/error states not handled
- Race conditions, ordering dependencies
- State management correctness
- Missing or inadequate tests

**Acceptance Criteria / Goal Reviewer:**
- Does the change actually solve the stated problem?
- Commit message / PR title clarity
- Scope creep or unrelated changes
- Documentation gaps

**Depth by line count:**
- Deep (<100 lines): Full analysis — trace callers, check tests, verify contracts
- Moderate (100-500): Standard analysis — spot-check tests, review logic
- Shallow (>500 lines): Surface analysis — bugs, anti-patterns, obvious issues only

**Weighting by domain:**
- Auth/config/credential changes → boost security persona
- New modules/files → boost duplication and patterns
- Bug fixes → boost functionality tester
- Refactors → boost patterns and goal reviewer

### Phase 3 — Synthesize
- Merge findings across personas, deduplicate.
- Sort by severity: critical → high → medium → low → nit.
- Write executive summary (2-3 sentences).
- Produce per-persona sections with weighted findings.
- Final verdict: merge / merge-with-revisions / do-not-merge.

### Constraints
- Read-only — never modify files.
- No destructive git commands.
- Stay within repo boundaries.
- Do not ask questions mid-review; produce the review.
