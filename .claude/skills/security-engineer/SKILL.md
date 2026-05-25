---
description: Audit a codebase for security vulnerabilities using parallel subagent review across multiple phases
argument-hint: [commit-range]
allowed-tools: Read, Search, Find, Task, Bash, AstGrep, WebSearch
tool-hints: |
  Use Task subagents to fan out parallel security reviews across directories, files, and specialized checks.
  Use Bash ONLY for `git diff --name-only`, `git ls-files`, and `git rev-parse --git-dir` — never for content search.
  Use Search, Find, and AstGrep for scoping and pattern detection.
  Use WebSearch ONLY for CVE lookups in the Dependency CVE Auditor — never for general research.
  This skill is read-only — never modify, delete, or create files.
  Subagent assignments MUST include the full finding schema and severity criteria.
---

## Usage

**Invocation:** `/skill:security-engineer [commit-range]`

- `[commit-range]` — A git commit range to scope the audit (e.g., `HEAD~10`, `main..feature`, `abc123..def456`). When provided, only files changed in that range are audited.
- _(no argument)_ — Audits the entire repository (Full Audit mode).
- `--help` — Print usage information and exit.

**Examples:**
- `/skill:security-engineer` — Full audit of the entire repository
- `/skill:security-engineer HEAD~5` — Audit only files changed in the last 5 commits
- `/skill:security-engineer main..feature` — Audit files changed between `main` and `feature`

Parse `$ARGUMENTS`:
- If a positional argument is provided, treat it as a commit range (e.g., `HEAD~10`, `main..feature`, `abc123..def456`). Enter Commit-Range Audit mode.
- If no argument is provided, enter Full Audit mode.
- If the argument is `--help`, print the description and usage and exit.
- Run `git rev-parse --git-dir`. If it fails, print "Not in a git repository. Security Engineer requires a git repo." and stop.

---

## Severity Criteria

Every subagent and the consolidator must use these definitions:

| Level    | Definition |
|----------|------------|
| CRITICAL | Remotely exploitable with no authentication. Remote code execution, unauthenticated data exfiltration, hardcoded production credentials visible in source. |
| HIGH     | Authentication bypass, authorization bypass, privilege escalation, sensitive data leak (PII, tokens, keys in logs/responses), SQL/command injection with confirmed reachable path. |
| MEDIUM   | Defense-in-depth gap: missing CSRF tokens, missing rate limiting, debug endpoints in production, overly permissive CORS, weak TLS configuration, unsafe deserialization without known gadget chain, missing input validation on non-critical paths. |
| LOW      | Hardening opportunity: missing security headers, verbose error messages leaking stack traces, use of deprecated cryptographic primitives on non-critical data, informational findings. |

---

## Mode: Full Audit

Run a four-phase pipeline. **Phase 1 runs first.** Collect all recon results, then launch Phase 2 and Phase 3 in parallel. Phase 4 runs after all prior phases complete.

### Checkpointing

This skill may run for many subagent invocations. To avoid losing work if a phase times out, write findings to `.security-audit-state.json` after each phase completes. On invocation, if this file exists, read it to determine which phases are already complete and skip them.

State file schema:
```json
{
  "phases_complete": [],
  "phase1_findings": [],
  "phase2_findings": [],
  "phase3_findings": [],
  "scope": "full_audit",
  "commit_range": null
}
```

**On invocation**, if `.security-audit-state.json` exists: read `phases_complete` and skip any phase already listed there. Load findings from the matching arrays instead of re-running subagents. If the file does not exist, all phases are pending.

### Collecting findings across phases

After each phase, read all subagent results. If a subagent's output is not in the expected schema, re-request it with the schema and an example. Index findings by file path so they can be routed to the correct Phase 2 review unit. Track which subagents returned results and which did not — the consolidator needs this information.

### Phase 1 — Recon (5 parallel subagents)

Spawn all five simultaneously. Each subagent receives the repo root as its scope, the skip list, and the finding schema.

**Skip list (all subagents must respect):**
- Directories: `.git`, `node_modules`, `vendor`, `target`, `dist`, `build`, `__pycache__`, `.next`, `.nuxt`, `coverage`
- Files: lockfiles (`*.lock`, `package-lock.json`, `yarn.lock`, `poetry.lock`, `Gemfile.lock`, `Cargo.lock`), generated code (`*.pb.go`, `*.gen.go`, `__generated__`, `*.graphqlgen*`), binaries (any file detected as binary), minified bundles (`*.min.js`, `*.min.css`), `.env` files
- Never read `.env` files, age-encrypted files (`.age`), or private key files.

**Subagent 1 — Repo Classifier:**
Walk the repo tree. Produce:
- Full directory listing with language classification per directory (detect by file extensions present)
- List of skipped paths with reason
- Recommended review unit partitioning (group directories into logical modules for Phase 2)

**Subagent 2 — Dependency Scanner:**
Find all dependency manifests. Extract package names and pinned/specified versions. Produce a structured manifest:
```
[{file, ecosystem, packages: [{name, version}]}]
```
Manifest files: `Cargo.toml`, `package.json`, `go.mod`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `flake.nix`, `flake.lock`, `build.gradle`, `pom.xml`, `composer.json`, `mix.exs`
If no dependency manifests are found, return an empty list.

**Subagent 3 — Secret Scanner:**
Search for high-signal patterns across all non-skipped files. Use Search with these patterns (case-sensitive where noted):
- `(api[_-]?key|api[_-]?secret|access[_-]?key|secret[_-]?key)\s*[:=]\s*['"][^'"]{8,}['"]`
- `(password|passwd|pwd)\s*[:=]\s*['"][^'"]+['"]` (flag unless obviously a placeholder)
- `(token|auth[_-]?token)\s*[:=]\s*['"][^'"]{8,}['"]`
- `-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----`
- `(jdbc|mysql|postgres|mongodb|redis)://[^'"]*@`
- `sk-[a-zA-Z0-9]{20,}` (OpenAI/Stripe-style keys)
- `ghp_[a-zA-Z0-9]{36}` (GitHub personal access tokens)
- `(eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})` (JWTs — flag as potential credential)

Return findings as: `[{severity: "CRITICAL"|"HIGH", file, line, pattern, snippet_truncated}]`. Do NOT include the full secret value in the report — truncate to first 8 chars.

**Subagent 4 — Config & Infrastructure Scanner:**
Find and audit infrastructure/config files. Look for:
- Dockerfiles: `USER root`, `--privileged`, exposed sensitive ports, `COPY . .` without `.dockerignore`, secrets in `ENV` or `ARG`, `curl | sh` patterns
- CI configs (`.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`): `--no-verify` bypasses, `secrets: inherit`, checkout of untrusted refs, artifact upload without integrity check
- Kubernetes manifests: `privileged: true`, `hostNetwork: true`, `hostPID: true`, `allowPrivilegeEscalation: true`, missing `runAsNonRoot`, `CAP_SYS_ADMIN`, `readOnlyRootFilesystem: false`
- NixOS configs: open firewall ports without justification, `services.*.enable = true` on sensitive services, `users.users.*.hashedPassword` with weak hash
- Terraform: `0.0.0.0/0` in security group rules, hardcoded credentials in provider blocks, S3 buckets with `acl = "public-read"`

**Subagent 5 — Hotspot Scanner:**
Search for high-risk code patterns across all non-skipped files. Use AstGrep for language-aware matching where possible, Search for cross-language patterns:

| Pattern | Risk | Language(s) |
|---------|------|-------------|
| `exec(`, `system(`, `popen(`, `subprocess`, `os.command` | Command injection | All |
| `eval(`, `Function(`, `vm.runInNewContext` | Code injection | JS/TS/Python |
| `.innerHTML`, `dangerouslySetInnerHTML`, `bypassSecurityTrust*` | XSS | JS/TS |
| `Runtime.getRuntime().exec(` | Command injection | Java |
| `sql.*\+.*\$|sql.*format|sql.*f['\"]` | SQL injection | All |
| `pickle.loads`, `yaml.load(`, `marshal.load` | Unsafe deserialization | Python |
| `assert` in non-test files | Assertion misuse | All |
| `--no-verify`, `--no-gpg-sign`, `--force` | Git safety bypass | Shell/CI |
| `curl.*\|.*sh`, `wget.*\|.*bash` | Pipe-to-shell | Shell/Docker/CI |
| `openssl.*-md5`, `openssl.*-sha1`, `-des-`, `-rc4-` | Weak crypto | All |
| `http://` (not `https://`) in URL constants/hardcoded endpoints | Cleartext transport | All |

Return findings as: `[{severity, file, line, pattern, problem, fix_suggestion}]`

**Wait for all five Phase 1 subagents to complete.** Read their results, index findings by file path. Write `.security-audit-state.json` with `phases_complete: ["phase1"]` and all phase 1 findings in `phase1_findings`. Then proceed to Phase 2 and Phase 3, which launch in parallel.

### Phase 2 — Deep Review (N parallel subagents)

Partition the repo into review units using the classifier's recommendation from Phase 1. Auto-cap at 12 parallel subagents (agent judgment — fewer for small repos).

Each Phase 2 subagent receives in its assignment:
- The path(s) it is responsible for (one review unit)
- The language(s) present (from the classifier)
- The hotspot scanner's findings for those paths
- The secret scanner's findings for those paths

**Core checklist** (every subagent must evaluate every item):

1. **Injection** — SQL, command, code, template, LDAP, XPath, NoSQL. Check every place user/external input reaches an interpreter. Flag any unparameterized query, unsanitized shell command, or string-concatenated template.
2. **Authentication bypass** — Missing auth checks on sensitive endpoints, hardcoded credentials, weak password policies, missing MFA enforcement, session fixation, JWT `alg: none` acceptance, missing signature verification.
3. **Authorization bypass** — Missing ownership checks (can user A access user B's data?), missing role checks on privileged operations, direct object references without authorization, default-allow patterns.
4. **Credential leaks** — Hardcoded tokens, keys, passwords in source. Credentials in logs, error messages, or debug output. Secrets in client-side code.
5. **Input validation** — Missing or insufficient validation on external input. Type confusion, integer overflow, path traversal (`../`), null byte injection, XML External Entity (XXE), regex DoS (catastrophic backtracking).
6. **Unsafe dependencies** — Use of deprecated/unmaintained packages, direct use of known-vulnerable functions, supply-chain risks (unpinned dependencies, suspicious package names).

**Language-specific additions** (subagent discretion):

- **Python**: `pickle`, `yaml.load` (unsafe), Flask `debug=True` in production, Django `DEBUG=True`, missing CSRF middleware, `assert` in production code
- **JavaScript/TypeScript**: `eval`, `new Function`, prototype pollution, `no-sql-injection` in MongoDB, `helmet` missing, CSP not set, `same-origin` not set on cookies
- **Rust**: `unsafe` blocks, `std::process::Command` with user input, `panic!` in non-recoverable paths, missing `#[deny(unsafe_code)]`
- **Go**: `text/template` with user-controlled templates (use `html/template`), `os/exec` with shell=true, `crypto/md5` or `crypto/sha1` for security
- **Java**: `Runtime.exec`, `ProcessBuilder` with shell=true, XML external entity processing enabled, deserialization of untrusted data, `@RequestMapping` without auth
- **Nix**: `builtins.fetchurl` without hash, `--impure` in flake commands, secrets in `/nix/store` (world-readable), `allowed-users` in nix.conf for multi-user installs
- **Shell**: Unquoted variables, `eval`, command substitution in untrusted input, `sudo` without restrictions

**Finding schema** (every subagent MUST return findings in this exact format):

```
[{severity: "CRITICAL"|"HIGH"|"MEDIUM"|"LOW", file: "path/to/file", line_range: "42-45", check: "injection|auth_bypass|authz_bypass|credential_leak|input_validation|unsafe_deps|other", problem: "One-sentence description of the vulnerability", fix: "One-sentence concrete fix recommendation"}]
```

Example finding:
`[{severity: "HIGH", file: "src/api/handler.ts", line_range: "42-47", check: "injection", problem: "User-controlled `req.query.sort` is interpolated directly into SQL ORDER BY clause without whitelist validation", fix: "Use a whitelist: `const allowed = ['id','name']; if (!allowed.includes(sort)) sort = 'id';`"}]`

### Phase 3 — Specialized Deep Scans (5 parallel subagents)

Spawn alongside Phase 2. Each receives the full repo scope, the skip list, dependency manifest (from Phase 1), and the finding schema.

**Subagent 6 — Dependency CVE Auditor:**
Take the dependency manifest from Phase 1. If the manifest is empty, return an empty list. For each dependency:
- Check if the version is known-vulnerable (use web_search for major CVEs if needed — search for `"<package> <version> CVE"`). Flag packages >1 year without updates, unmaintained forks, typosquatting candidates.
- Return: `[{severity, file: manifest_path, package, version, risk_type: "known_cve"|"unmaintained"|"unpinned"|"typosquatting", cve_id?, problem, fix}]`

**Subagent 7 — Auth & Session Auditor:**
Deep-dive on authentication and session management:
- JWT handling: verify `exp`, `nbf`, `iss`, `aud` claims are checked, algorithm is pinned (not `alg: none`), key material is not hardcoded
- Session cookies: `HttpOnly`, `Secure`, `SameSite=Strict` set, session fixation protection, secure session ID generation
- Password handling: bcrypt/argon2 used (not MD5/SHA1), salts present, timing-safe comparison
- OAuth/OIDC: state parameter verified, redirect URI validated, PKCE used for public clients
- Multi-factor: bypass paths, recovery flow security

Return findings using the standard schema.

**Subagent 8 — Authorization & ACL Auditor:**
Deep-dive on authorization:
- Find every authorization check (`if user.role`, `@require_auth`, `can_`, `allowed_to`, middleware guards). Flag any privileged operation without a check.
- Look for direct object references (`/users/{id}` with no ownership check), missing resource-level authorization, role confusion (can lower-role user escalate?), default-allow patterns.
- Return findings using the standard schema.

**Subagent 9 — Data Exposure Auditor:**
Deep-dive on data leakage:
- Search for logging statements that include user data, tokens, passwords, session IDs, or PII
- Search for error handlers that return stack traces, system paths, or internal state
- Search for debug/test endpoints or flags enabled in production configs
- Search for CORS: `Access-Control-Allow-Origin: *` with credentials, overly permissive origins
- Search for `console.log`, `print`, `debug!`, `log::debug!` with variables named `token`, `password`, `secret`, `key`, `credential`
- Return findings using the standard schema.

**Subagent 10 — Cryptography Auditor:**
Deep-dive on cryptographic usage:
- Hardcoded keys, IVs, or nonces
- Weak algorithms: MD5, SHA1 (for security), DES, 3DES, RC4, Blowfish
- ECB mode in symmetric encryption
- Missing certificate validation (`InsecureSkipVerify`, `rejectUnauthorized: false`, `verify=False`)
- Custom/non-standard cryptographic implementations
- Insufficient key sizes (RSA <2048, ECC <256)
- Predictable PRNGs (`Math.random()`, `rand()` instead of `crypto.randomBytes`)
- Key derivation: missing or weak KDF, hardcoded salts, insufficient iterations
- Return findings using the standard schema.
**Wait for all Phase 2 and Phase 3 subagents to complete.** Read their results. Append to `.security-audit-state.json`: add `"phase2"` and `"phase3"` to `phases_complete`, store Phase 2 findings in `phase2_findings`, Phase 3 findings in `phase3_findings`. Then proceed to Phase 4.

### Phase 4 — Consolidation (1 subagent)

The consolidator ingests ALL findings from Phases 1-3 and produces the final report.

0. **Check completeness** — Verify that every dispatched subagent returned results. If a subagent failed or timed out, note it as a gap: "⚠ Subagent N (<name>) did not return results — its scope was not audited." Include this note in the report summary.
1. **Deduplicate** — Same file, same line range, same problem class → merge into one finding. If severity differs between subagents, use the higher severity.
2. **Compute overall risk score**:
   - CRITICAL if any CRITICAL finding exists
   - HIGH if any HIGH finding exists (and no CRITICAL)
   - MEDIUM if any MEDIUM finding exists (and no CRITICAL/HIGH)
   - LOW otherwise
   - If zero findings total, report: "No security findings detected." and show only the summary with scope.
3. **Weight the score** — Append `(C CRITICAL, H HIGH, M MEDIUM, L LOW)` for transparency.
4. **Pick top remediation** — The single CRITICAL or HIGH finding that, if fixed, would most reduce risk. If none, the most impactful MEDIUM finding. Explain in one sentence why it's the highest priority.
5. **Render the report** in chat using the format below.

### Report Format

```
## Security Audit Report — Full Audit

### Summary
- **Overall risk:** CRITICAL (2 CRITICAL, 5 HIGH, 12 MEDIUM, 8 LOW)
- **Scope:** 347 files across 18 directories
- **Completeness:** 10/10 subagents returned results
- **Top remediation:** Fix hardcoded JWT secret in src/auth/config.ts:23 — this key signs all authentication tokens and is visible to anyone with repo access.

### Recon Findings
| # | Category | File:Line | Detail |
|---|----------|-----------|--------|
| 1 | Secret | src/config.ts:23 | Hardcoded JWT signing key (sk-12ab34...) |
| 2 | Hotspot | src/api/users.ts:156 | Raw SQL string concatenation with user input |
| 3 | Config  | docker-compose.yml:12 | PostgreSQL port 5432 exposed to 0.0.0.0 |

### Severity Criteria
*(Repeat severity criteria table from the top of this document)*

### Deep Review Findings
| # | Severity | File:Line | Problem | Fix |
|---|----------|-----------|---------|-----|
| 1 | CRITICAL | src/auth/config.ts:23 | Hardcoded JWT secret exposes all sessions to forgery | Move to environment variable or secret manager |
| 2 | HIGH | src/api/users.ts:156-160 | SQL injection via unsanitized `req.query.name` in raw query | Use parameterized query: `db.query('SELECT ... WHERE name = ?', [name])` |
| 3 | HIGH | src/middleware/auth.ts:42 | Missing JWT signature verification — `decode()` used instead of `verify()` | Replace `jwt.decode()` with `jwt.verify(token, secret)` |
| 4 | MEDIUM | src/server.ts:88 | Stack traces sent to client in production error handler | Set `NODE_ENV=production` and use generic error messages |
| 5 | LOW | Dockerfile:7 | Container runs as root | Add `USER node` after `npm install` |

### Dependency Risks
| # | Package | Version | Risk | Recommendation |
|---|---------|---------|------|----------------|
| 1 | lodash | 4.17.15 | Known prototype pollution CVE-2020-8203 | Upgrade to 4.17.21+ |
| 2 | express | 4.16.0 | 3 years behind; multiple CVEs since | Upgrade to 4.19.2+ |

### Specialized Scan Findings
| # | Severity | Category | File:Line | Problem | Fix |
|---|----------|----------|-----------|---------|-----|
| 1 | MEDIUM | Auth | src/auth/sessions.ts:34 | Session cookie missing `SameSite=Strict` | Add `sameSite: 'strict'` to cookie options |
| 2 | MEDIUM | Crypto | src/utils/hash.ts:12 | SHA1 used for password hashing | Replace with bcrypt or argon2 |
| 3 | LOW | Data | src/api/debug.ts:5 | Debug endpoint `/api/debug` enabled unconditionally | Guard with `NODE_ENV !== 'production'` |
```

---

## Mode: Commit-Range Audit

Same four-phase pipeline, scoped to files changed in the specified commit range.

### Phase 1 — Recon (3 parallel subagents)

**Subagent 1 — Diff Classifier:**
Run `git diff --name-only <commit-range>`. If no files are returned, report "No files changed in <commit-range>." and stop. Filter through the skip list (same exclusions as Full Audit). If no files remain after filtering, report "All changed files were skipped (vendored, generated, or lockfiles)." and stop. Classify each changed file by language and risk category. If fewer than 5 files remain, collapse all remaining phases into a single subagent. Produce the diff file list and language classification.

**Subagent 2 — Hotspot + Secret Scanner:**
Run the same secret patterns and hotspot patterns from Full Audit Phase 1, but only on the changed files identified by the Diff Classifier. Return findings using the standard schema.

**Subagent 3 — Config & Dependency Scanner:**
Check if any changed files are dependency manifests or infrastructure configs. If yes, scan them using the same checks as the Full Audit dependency and config scanners. If no manifests changed, return empty.

**Wait for all three Phase 1 subagents to complete.** Then proceed to Phase 2 and Phase 3 in parallel.

### Phase 2 — Deep Review (N parallel subagents)

Group changed files logically (by directory/module). Auto-cap at one subagent per group, minimum 1, maximum same as number of changed files. Each subagent receives the same core checklist, language-specific additions, finding schema, and hotspot/secret findings for its files as Full Audit Phase 2.

### Phase 3 — Specialized Deep Scans (up to 5 parallel subagents, gated)

Only spawn specialized scans if relevant files changed:
- **Dependency CVE Auditor** — only if dependency manifests changed
- **Auth & Session Auditor** — only if auth-related files changed (files matching `auth`, `login`, `session`, `jwt`, `oauth`, `token`)
- **Authorization & ACL Auditor** — only if authz-related files changed (files matching `auth`, `role`, `permission`, `acl`, `policy`, `guard`)
- **Data Exposure Auditor** — only if logging, error-handling, or response-rendering files changed
- **Cryptography Auditor** — only if crypto-related files changed (files matching `crypto`, `hash`, `encrypt`, `decrypt`, `sign`, `verify`, `key`, `cipher`)

Gate each subagent: if no relevant files changed, skip it instead of spawning.

### Phase 4 — Consolidation (1 subagent)

Same as Full Audit consolidation. Report title: `## Security Audit Report — Commit-Range Audit (<commit-range>)`. Add a `Files reviewed` line showing the diff range and file count.

---

## Constraints (both modes)

- **Read-only.** Never modify, delete, or create files. Never run `git commit`, `git push`, `gh pr create`, or any mutation command.
- **Respect `.gitignore`.** Use Search and Find tools (which respect `.gitignore` by default). Do not use `git grep` or raw `find` unless `.gitignore` is explicitly handled.
- **Skip list** is mandatory. See Phase 1 skip list. Do not audit vendored code, lockfiles, generated artifacts, or binaries.
- **Never read secrets.** Do not read `.env` files, `.age` files, or private key files. If a search hit lands in one of these, note the file name only, do not read its contents.
- **Do not run destructive commands.** No `rm`, `git reset --hard`, `nix-collect-garbage`, `docker rm`, etc.
- **Subagents must return structured findings.** Prose summaries without the schema fields are invalid — re-request with the schema and example.
- **Do not ask questions.** The skill runs unattended once invoked; make decisions autonomously within the constraints above.
- **No network calls** except `web_search` for CVE lookups (and only for CVE lookups). Do not call external APIs or download code.
- **If invoked in loop mode**, call `exit_loop_mode('Security audit complete — overall risk: <RISK_LEVEL>')` after rendering the final report.
