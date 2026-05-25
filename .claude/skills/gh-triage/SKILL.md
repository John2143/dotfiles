---
description: [Internal sub-skill] Deduplicate and filter automated review findings, removing false positives, speculative issues, and style-only nits before the implementer acts on them. Standalone entry point for findings triage; for full multi-phase workflows, use `do-gh-issue` instead.
argument-hint: "[--pr number] [--input findings.json]"
allowed-tools: Read, Bash, Search
tool-hints: |
  Use `gh pr view <number> --json comments` to fetch review comments.
  Use `read` to verify source code when checking if a finding is a false positive.
  Output a filtered, deduplicated list with removal reasons.
---

## Usage

**Invocation:** `/skill:gh-triage [--pr number] [--input findings.json]`

- `--pr number` — (optional) PR number to fetch review comments from for triage.
- `--input findings.json` — (optional) Path to a JSON file of findings to triage (alternative to PR fetch). If neither is provided, reads `.gh-issue-state.json` for the PR number.

**Examples:**
- `/skill:gh-triage --pr 7` — Fetch review comments from PR #7 and triage them
- `/skill:gh-triage --input review-findings.json` — Triage findings from a local JSON file
- `/skill:gh-triage` — Triage findings for the PR in the state file
Parse `$ARGUMENTS`:
- `--pr number` — PR number to fetch review comments from.
- `--input findings.json` — path to a JSON file of findings (alternative to PR fetch).
- If neither provided, read `.gh-issue-state.json` for the PR number.
- If no source of findings can be determined: if invoked from a workflow with a state file, report "No findings source available — check state file." If standalone, ask the user.

---

## Mode: Triage

### Step 1 — Gather findings

1. If `--pr number` provided:
   ```
   gh pr view <number> --json comments --jq '.comments[] | select(.body | startswith("## Review from")) | .body'
   ```
   Extract the most recent review comment.
2. If `--input` provided: read the file.
3. Parse findings into a structured list. Each finding has: severity, file, lines, problem, fix.

### Step 2 — Deduplicate

1. Group findings by file + line range. If two findings flag the same code, keep the one with higher severity.
2. If the same issue is flagged by different dimensions (e.g., correctness AND maintainability), keep it once under the most applicable dimension.

### Step 3 — Filter

Remove findings matching any of these criteria:

- **Speculative**: uses "could be", "might cause", "consider" without a concrete failure mode or reproduction.
- **False positive**: verify against source code — if the finding is factually wrong, drop it.
- **Style-only**: purely about indentation, naming preference, or formatting without correctness/security impact.
- **Convention-blessed**: if `AGENTS.md` or project conventions explicitly allow the flagged pattern.
- **Duplicate**: same issue as another kept finding.

Example removals:
```
Removed: "Consider using const for magic number" → style-only, no correctness impact
Removed: "Possible null deref at line 42" → verified: null guard exists on line 40
Removed: Duplicate of finding #1 (same file, same lines, lower severity)
```

### Step 4 — Re-categorize

1. Move mis-categorized findings to the correct dimension.
   Example: a finding about `sin()` being called per-frame under "maintainability" → recategorize to "performance".
2. Re-evaluate severity after cross-referencing. A finding that looked HIGH in isolation may be LOW after full context.

### Step 5 — Output

Produce the filtered list. For each kept finding:
```
<#> **SEVERITY** — `file` (line N) — problem. Fix: <concrete fix>.
```

Also report removals with reasons:
```
Removed N findings:
- "<summary>" → <reason>
- ...
```

### Step 6 — Update state

If `.gh-issue-state.json` exists, update `last_review_findings` with the filtered counts.

### Constraints

- When in doubt about a finding: keep it, mark it LOW, and add "Uncertain — human reviewer should confirm."
- Do not modify source files. This is read-only triage.
- If you disagree with a finding from a prior review, explain why before removing it. Do not silently drop findings you subjectively disagree with.
- If `gh` CLI returns an auth or permission error: report "gh CLI error — check `gh auth status`." and stop.
