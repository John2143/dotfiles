---
description: Run project-specific build, test, and lint commands, capture results, and report pass/fail with actionable error output
argument-hint: "[--build] [--test] [--lint] [--all]"
allowed-tools: Bash, Read, Search
tool-hints: |
  Detect validation commands from AGENTS.md, Makefile, package.json, Cargo.toml, project.godot, flake.nix, go.mod, pyproject.toml.
  Run each command with a timeout. Capture stdout/stderr.
  Report failures with the last 50 lines of error output. Never modify config to make validation pass.
---

Parse `$ARGUMENTS`:
- `--build` — run build only.
- `--test` — run tests only.
- `--lint` — run linter only.
- `--all` — run all three (default if no flags given).

---

## Mode: Validate

### Step 1 — Detect validation commands

Check for project-specific validation tooling, in priority order:

1. Read `AGENTS.md` or `CLAUDE.md` — it may document the exact validation workflow.
2. Check for build files and extract commands:

| File | Build | Test | Lint |
|---|---|---|---|
| `Makefile` | `make build` or `make` | `make test` | `make lint` |
| `package.json` | `npm run build` | `npm test` | `npm run lint` |
| `Cargo.toml` | `cargo build` | `cargo test` | `cargo clippy` |
| `project.godot` | `godot --headless --check-only` | _(none)_ | _(none)_ |
| `flake.nix` | `nix build` | `nix flake check` | _(none)_ |
| `go.mod` | `go build ./...` | `go test ./...` | `golangci-lint run` |
| `pyproject.toml` | _(none)_ | `pytest` | `ruff check .` |

Only run commands whose build files exist. Do not guess or invent commands.

3. If no build files found: report "No validation tooling detected for this project." and stop.

### Step 2 — Run validation

Run each requested command with a timeout:

```
# Build
timeout 120 <build-command>

# Test
timeout 120 <test-command>

# Lint
timeout 60 <lint-command>
```

If a command is not applicable to the project (e.g., no lint target in Makefile), skip it with "Not configured."

### Step 3 — Report results

For each command:
- **Pass (exit 0)**: report "PASS" and mention any warnings.
- **Fail (non-zero exit)**: report "FAIL", exit code, last 50 lines of output.
- **Timeout (exit 124)**: report "TIMEOUT — command exceeded time limit."

Summary line:
```
Validation: 2 passed, 1 failed (lint), 1 unavailable
```

### Step 4 — On failure

1. Extract specific error messages from the output.
2. Map errors to files and lines where possible.
   Example:
   ```
   FAIL: cargo test
   error[E0308]: mismatched types
     --> src/main.rs:42:13
   ```
3. Report: "Fix these failures before proceeding:" followed by the extracted errors.

### Constraints

- Never run commands that require user interaction (no `sudo`, no `ssh`, no stdin prompts).
- Never install missing tools. If a command is unavailable, report it.
- Never modify configuration files to make validation pass.
- Respect project-specific conventions from `AGENTS.md` over generic detection.
- Validate against the current branch — do not switch branches.
- If a detected command is not found in PATH: report it as "unavailable" rather than failing.
