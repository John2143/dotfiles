---
description: Perform a structured code review on a file or directory, evaluating correctness, security, error handling, maintainability, and performance
argument-hint: [path] [--focus (correctness|security|error-handling|maintainability|performance)]
allowed-tools: Read, Search, Find, Write, Edit, LSP, Bash
tool-hints: |
  Use `read` to inspect files; use `search` or `lsp references` for cross-references.
  Use `find` to list directory contents.
  Use `write`/`edit` only to illustrate fixes in your output — do not modify the reviewed files.
---

Parse `$ARGUMENTS`:
- First positional argument is the target `$PATH` (file or directory to review).
- If `--focus FOCUS` is provided, restrict the review to the named dimension only. Valid values: `correctness`, `security`, `error-handling`, `maintainability`, `performance`.
- If no argument was given, ask the user for the path.
- If the path does not exist: report the error and stop.
- If the path is a binary file, symlink, or generated artifact: note it and skip.

---

## Mode: Single File Review

When `$PATH` points to a single file:

1. Read the file in full.
2. Check cross-references by searching for symbols and types used from this file using LSP or Search.
3. Evaluate the file against all analysis dimensions below.
4. Produce the output:
   a. Write the Summary (score + single biggest gap).
   b. List each Finding with severity, file, lines, problem, and fix.
   c. Write the Overall assessment paragraph.

## Mode: Directory / PR Review

When `$PATH` points to a directory:

1. List the directory contents and identify the subset of files that are changed or are relevant (source code, configs, tests). Cap at 20 relevant source files.
2. Exclude: vendored/third-party code, generated files, lockfiles, build artifacts, binary blobs, and dot-directories (unless they contain config files explicitly under review).
3. For each relevant file, perform a single-file review; cross-reference dependencies between files.
4. Produce a composite output with per-file findings and a cross-cutting summary.

---

## Analysis dimensions

Evaluate all dimensions in the order listed. If you encounter a CRITICAL correctness or security issue, flag it immediately in your output but continue evaluating remaining dimensions to produce a complete picture.

### 1. Correctness
- Logic errors, off-by-one, null/undefined dereferences, type mismatches
- Race conditions (shared mutable state without synchronization)
- Incorrect assumptions about input shape or range
- Missing or incorrect edge-case handling

### 2. Security
- Injection vulnerabilities (command, SQL, path traversal, XSS)
- Authentication or authorization bypass
- Credential leaks (hardcoded secrets, secrets in logs, secrets in URLs)
- Missing or insufficient input validation / sanitization

### 3. Error handling
- Silent failures (errors caught but ignored, or `/* fallthrough */` with no action)
- Swallowed panics or exceptions
- Unhandled error variants in match/switch
- Functions that return success-like values when they have actually failed

### 4. Maintainability
- Coupling and cohesion — is this module doing too much?
- Naming — do names communicate intent or just mechanics?
- Duplication — repeated patterns that should be extracted
- Dead code — unreachable branches, unused parameters or imports
- Comments — misleading, absent where needed, or present to excuse bad naming

### 5. Performance
- Hot-path allocations in loops
- N+1 queries or redundant I/O
- Unnecessary work that could be cached, batched, or hoisted
- Inefficient data structures

---

## Output

### Summary
Two lines: a score out of 10 reflecting overall quality, and the single biggest gap.

### Findings
A numbered list. Each finding must include:
- **Severity tag**: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, or `INFO`
- **File**: path relative to repo root
- **Line(s)**: line numbers affected
- **Problem**: specific description of what is wrong
- **Fix**: concrete fix — not "consider improving" but the actual code or structural change

If no issues are found in a dimension, state "No issues found." Do not invent LOW/INFO findings to pad the list.

*Example finding:*
*1. **HIGH** — `src/auth/login.ts` (line 47) — Password error message reveals whether the account exists ("Invalid password" vs "Unknown user"), enabling enumeration. Replace both messages with a generic "Invalid email or password." response.*

Order by severity, then by confidence.

### Overall assessment
A paragraph addressing:
- Whether the code is ready for production
- What the single most impactful improvement would be
- Any patterns that are consistently good or consistently bad across the reviewed surface
