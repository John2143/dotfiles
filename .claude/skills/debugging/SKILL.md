---
description: Conduct a structured debugging session: capture the symptom, formulate and test hypotheses, isolate root cause, and verify the fix
argument-hint: [symptom] [--file path]
allowed-tools: Read, Bash, Debug, Search, LSP
---


## Usage

**Invocation:** `/skill:debugging [symptom] [--file FILE]`

Conducts a structured debugging session: capture the symptom, formulate and test hypotheses, isolate root cause, and verify the fix.

- `symptom` — a description of what is going wrong (error message, unexpected behavior, regression). When omitted, the skill asks for it.
- `--file FILE` — scope the investigation to a specific file. The debugger reads the file and traces the code path that produces the symptom.

**Examples:**
- `/skill:debugging` — Ask for symptom interactively
- `/skill:debugging "segfault on startup"` — Capture the symptom and begin hypothesis testing
- `/skill:debugging "NPE in auth flow" --file src/auth/login.ts` — Narrow investigation to `login.ts`
Parse `$ARGUMENTS`:
- First positional argument is the `$SYMPTOM` — a description of what is going wrong.
- If `--file FILE` is provided, scope the investigation to that file.
- If no symptom was given, ask the user to describe what they observed.

---

## Mode: Reproduce

1. Extract the exact failure: error message, exit code, unexpected output, performance regression metric.
2. Determine the expected behavior — what should happen instead.
3. Construct a minimal reproduction command or script.
4. If `--file` was given, read the file and trace the code path that produces the symptom.
5. Log the reproduction steps so they can be re-run after the fix.

## Mode: Isolate

1. Formulate an ordered list of hypotheses (most likely first).
2. For each hypothesis:
   - Design a test (a `printf`, a breakpoint, a bisect range, a reduced input, etc.).
   - Run the test and capture the result.
   - Log the outcome.
3. Narrow until one hypothesis is confirmed.

---

## Analysis framework

### Step 1 — Capture exact failure
Record:
- Error message (full text, no truncation)
- Exit code
- Stack trace (if any)
- Input that triggered the failure
- Environment variables or configuration relevant to the failure
- What should have happened instead

### Step 2 — Hypothesis list
Prioritize by likelihood given the symptom. Examples:
- Null pointer / missing key in map
- Off-by-one in loop or slice
- Incorrect error propagation (function returns nil on failure)
- Race condition in concurrent code
- Configuration drift (env var changed, file not regenerated)
- Type confusion / coercion
- Resource exhaustion (fd limit, OOM, disk full)

### Step 3 — Test each hypothesis
For each hypothesis, design a test that would falsify it:
- Insert a probe (log, breakpoint, assertion) at the point the hypothesis predicts the bug.
- Run the reproduction with the probe.
- If the probe shows the hypothesis is wrong, move to the next hypothesis.
- If the probe shows the hypothesis is right, proceed to isolation.

### Step 4 — Identify root cause (not proximate cause)
- Proximate cause: "the function returned nil here"
- Root cause: "the value was not initialized because the constructor was called before the config was loaded"
- Keep asking "why" until you reach a systemic failure (incorrect abstraction, missing invariant, wrong data flow).

### Step 5 — Verify fix
- Apply the fix.
- Re-run the reproduction from Step 1.
- Confirm the expected behavior is now observed.
- Run any closely related tests to confirm no regression.

---

## Output

### Debug session log
A table with columns:
| Step | Action | Observation | Conclusion |
|------|--------|-------------|------------|
|  |  |  |  |

Rows correspond to: symptom capture, each hypothesis test, root cause identification, fix, verification.

### Root cause statement
A single sentence: "The root cause is [what] in [where] because [why the system allowed it]."

### Verification result
Did the fix pass reproduction? Did any regression test fail? State both.
