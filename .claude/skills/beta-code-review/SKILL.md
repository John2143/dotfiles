---
description: Perform a structured code review on a file or directory, evaluating correctness, security, error handling, maintainability, and performance
argument-hint: [path] [--focus (correctness|security|maintainability|performance)]
allowed-tools: Read, Bash, LSP, Search
---

Parse `$ARGUMENTS`:
- First positional argument is the target `$PATH` (file or directory to review).
- If `--focus FOCUS` is provided, restrict the review to the named dimension only. Valid values: `correctness`, `security`, `maintainability`, `performance`.
- If no argument was given, ask the user for the path.

---

## Mode: Single File Review

When `$PATH` points to a single file:

1. Read the file in full.
2. Check cross-references by searching for symbols and types used from this file using LSP or Search.
3. Evaluate the file against all analysis dimensions below.
4. Produce the output.

## Mode: Directory / PR Review

When `$PATH` points to a directory:

1. List the directory contents and identify the subset of files that were changed or are relevant (source code, configs, tests).
2. For each relevant file, perform a single-file review; cross-reference dependencies between files.
3. Produce a composite output with per-file findings and a cross-cutting summary.

---

## Analysis dimensions

Evaluate in this order, stopping early if a fatal correctness or security issue is found (flag it immediately):

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

Order by severity, then by confidence.

### Overall assessment
A paragraph addressing:
- Whether the code is ready for production
- What the single most impactful improvement would be
- Any patterns that are consistently good or consistently bad across the reviewed surface
