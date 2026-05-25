---
description: Inspect Nix files for formatting, eval errors, common pitfalls, and outdated inputs
argument-hint: [path] [--check (eval|format|audit|updates|all)]
allowed-tools: Read, Bash, Search
tool-hints: |
  This skill may be invoked in loop mode (via `/loop` harness). When running in loop mode, call `exit_loop_mode(summary)` after producing the report to terminate the harness. When not in loop mode, just stop normally.
---


## Usage

**Invocation:** `/skill:nix-gardener [path] [--check CHECK]`

Inspects Nix files for formatting, evaluation errors, common pitfalls, and outdated inputs. Runs checks in order, stopping early for blocking failures.

- `path` — a Nix file or directory containing Nix files. Defaults to the repo root when omitted.
- `--check CHECK` — run only a specific check. Valid values:
  - `format` — check formatting with `nixpkgs-fmt` or `nixfmt`
  - `eval` — evaluate the target (`nix flake check` for flakes, `nix eval` otherwise)
  - `audit` — scan for common Nix pitfalls (missing system, hardcoded versions, deprecated `stdenv.lib`, etc.)
  - `updates` — check whether nixpkgs inputs are behind upstream
  - `all` — run all checks (default when `--check` is omitted)

**Examples:**
- `/skill:nix-gardener` — Run all checks on the repo root
- `/skill:nix-gardener nixos/modules/` — Run all checks on the modules directory
- `/skill:nix-gardener flake.nix --check eval` — Only evaluate `flake.nix`
- `/skill:nix-gardener --check format` — Only check formatting across the repo root
Parse `$ARGUMENTS`:
- First positional argument is the target `$PATH` — a Nix file or directory containing Nix files.
- If `--check CHECK` is provided, run only that check. Valid values: `eval`, `format`, `audit`, `updates`, `all` (default).
- If no path was given, default to the repo root.

---

## Procedure

Run checks in order, stopping early if a check fails and the error blocks subsequent checks.

### Check 1 — Format
Run the appropriate formatter check:
- If `nixpkgs-fmt` is available: `nixpkgs-fmt --check $TARGET`
- Else if `nixfmt` is available: `nixfmt --check $TARGET`
- Collect unformatted files and report them.

### Check 2 — Eval
Run evaluation on the target:
- If `$PATH` points to a flake directory: `nix flake check --no-build $TARGET`
- Else: `nix eval --file $TARGET`
- Surface any eval errors with file and line information.

### Check 3 — Audit
Scan the target for common Nix pitfalls using Search. Flag each finding with file, line, and a fix suggestion.

| Pitfall | What to flag | Fix suggestion |
|---------|-------------|----------------|
| Missing `system` | `let` bindings that reference `system` without it being in scope | Add `system` argument to the function or let-binding |
| Hardcoded versions | Version strings like `"1.2.3"` not derived from `inputs` | Reference the version from the flake input |
| `builtins.currentSystem` | Use of `builtins.currentSystem` in a flake context | Use the `system` argument passed by the flake |
| `fetchurl` without hash | `fetchurl { url = ... }` without `hash` or `sha256` | Add `hash = "sha256-..."` (can use `lib.fakeHash` initially) |
| Unused let bindings | Bindings defined but never referenced in the body | Remove the unused binding or justify it with a comment |
| Nested `with` | `with foo; with bar;` statements nested or sequential | Use `let inherit` or explicit attribute access instead |
| `builtins.readDir` without error handling | `builtins.readDir` on a path that may not exist | Wrap in `builtins.pathExists` check or use `tryEval` |
| Deprecated `stdenv.lib` | `stdenv.lib.*` (removed in NixOS 23.11+) | Use `lib` directly from the flake inputs |

### Check 4 — Updates
Check for outdated nixpkgs inputs:
- Run `nix flake metadata` and check the nixpkgs input revision.
- Fetch the latest nixpkgs commit hash from the official channel.
- Report whether the flake's nixpkgs is behind, and by how many commits.

---

## Output

### Report

| Check | Status | Details |
|-------|--------|---------|
| Format | PASS / FAIL | Count of unformatted files (if FAIL) |
| Eval | PASS / FAIL | Error message and location (if FAIL) |
| Audit | PASS / FAIL | Count of findings (if FAIL) |
| Updates | PASS / FAIL | Commits behind upstream (if FAIL) |

### Findings (for Audit)

Each finding includes:
- **File**: path relative to repo root
- **Line**: line number
- **Pitfall**: which pitfall was detected
- **Fix**: concrete fix suggestion

### Summary

Ordered by impact: prioritize eval errors first (blocking), then format (cosmetic but CI-breaking), then audit findings (best practices), then updates (optional).

If invoked in loop mode (via `/loop` harness), call `exit_loop_mode('Nix checks complete — <N> passed, <M> failed')` after producing this report. If not in loop mode, just stop.
