# Fleet maintenance agent

**Status: design only (2026-11-25). Nothing here is built.** Tracking card: #508. The working
name is undecided; `steward` below is a placeholder (not `mend`: Mend.io is the company behind
Renovate).

A weekly job that gives an LLM agent abstract maintenance goals across most of the repos in
`John2143` and `2143-Labs` — "update the dependencies and flakes and fix what breaks", "review the
CVEs for this group of repos", "keep the oh-my-pi fork rebased" — and returns one reviewable pull
request per repo. These are the upgrades that a bot like Renovate cannot finish on its own.

The rule the whole design rests on: **a machine decides whether the work is done, never the
model.** Every goal is compiled into a playbook whose done-condition is an exit code, a CI result
or a coverage count. The agent does the part no script can, and is bounded in money, time and
attempts.

## The result it should produce: rots4 #83

[2143-Labs/rots4#83](https://github.com/2143-Labs/rots4/pull/83) (merged 2026-11-25) is the
reference output. It was prepared end to end by an omp agent and merged by hand about two hours
after CI went green.

| Property | In #83 |
|---|---|
| The deterministic step is the whole diff | `nix flake update` + `cargo update`: `Cargo.lock` +475/−457, `flake.lock` +15/−15. No `Cargo.toml` or `flake.nix` edit: every bump stays inside its existing range. |
| Hard scope fence | Majors that need manifest edits are listed under **Not included** (sqlx 0.8.6→0.9.1 with `.sqlx` regen, jsonwebtoken 11→12, tungstenite 0.28→0.30) instead of attempted. |
| One PR per repo per week | One commit, `chore(deps): update flake inputs and Cargo.lock within current ranges`, squash-merged. Not one PR per package. |
| The agent's real job was analysis | It read the upstream release notes for temporalio 1.1→1.3, named the two breaking changes, and showed neither is used here. It explained each surprise: a downgrade of `crypto-common` (0.1.7 pins `generic-array = "=0.14.7"`), and transitive majors pulled in by temporalio. |
| Repo invariants kept in the same commit | `CLAUDE.md` requires the wasm-bindgen crate and CLI to match; the "currently 0.2.129" line moved with the bump. |
| Evidence, not assertion | A 13-row table of commands run on the exact commit with pass counts, plus a behavioural equivalence check: a recorded match replayed to the same state hash as on `main`. CI ran all 11 jobs green on the same head. |
| Honest edges | **Not verified** (prod workflows under Temporal 1.3; the native window was never launched) and **Human attention** (expected cold-cache CI time, interaction with open PR #81, merging deploys prod). |
| Readable despite size | 928 changed lines, but the meaning sits in two tables; the raw `cargo update` log is collapsed in a `<details>` block. |

PR body sections, verbatim: `## Summary`, `## Not included`, `## Verification`,
`## AI attribution`, `## Human attention`.

What an automated run must **not** copy from it:

- **Attribution.** The commit carries John's identity with no trailer, while the body says an
  agent wrote it. Automated commits need their own identity or an explicit trailer.
- **The merge.** Automation stops at a green PR; merging stays a human decision, at least until
  auto-merge is explicitly allowed for a playbook.
- **Outside knowledge.** Parts of "Human attention" came from context only John had. A run can
  flag *that* something needs a look; it cannot be relied on to know *why*.
- **Silent cleanup.** An `unused dependency phf` warning was surfaced and left alone. Runs report
  such things; they do not fix unrelated code.

#83 needed no code changes. When only out-of-range majors remain, the recipe above produces an
empty PR, and the `major-upgrade` playbook below takes over.

## The fleet today

Measured 2026-11-25 with `gh`:

| | Count |
|---|---|
| Repos pushed in the last 90 days | 28 |
| … with `flake.lock` | 19 |
| … with `Cargo.lock` | 14 |
| … with `package.json` | 7 |
| … with Renovate config | 1 (`2143-Labs/argo`) |
| … with Dependabot | 1 (`John2143/little_oil`) |
| … with no CI workflow at all | 3 (`timestone-roadmap`, `timestone-lobby-watcher`, `sunspot`) |

Red CI runs in the 30 days to 2026-11-25: oh-my-pi `Fork sync` ×28, dotfiles
`Build and push frigate-genai images` ×25 and `Fleet patch` ×3, rots4 `Test, build and publish`
×13. These are not classified; several share a cause, and some are infrastructure faults no agent
can fix from a repo.

What already updates things:

- **`fleet-patch.yml`** (this repo, Sundays) bumps `nixpkgs`, `nixpkgs-stable` and `oh-my-pi` in
  dotfiles and switches every host. See `fleet-patching.md`. Unchanged by this design.
- **Renovate CronJob** in argo (`workloads/renovate/cronjob.yaml`, Sundays 05:00
  America/New_York, `renovate/renovate:44.257.9`) opens PRs on `2143-Labs/argo` only, through a
  fine-grained PAT scoped to that repo. Regex managers for Helm charts and images; no automerge.
- **`fork-sync.yml`** in oh-my-pi rebases `john` onto upstream daily and opens an issue on
  failure. Its repair is the first goal this design absorbs.

## Design rules

These come from the research listed under [Sources](#sources). Each is enforced by structure, not
by asking the model.

1. **The gate decides.** Done means the repo's CI is green on the candidate commit, or a coverage
   check passes. A model's "I'm finished" ends an attempt, never the run. Published repair rates
   are low (55–62% per merge conflict, 18.9% at best for CI repair under full re-execution), and
   most "fixed" patches in one benchmark did not pass CI.
2. **Deterministic first.** Lockfile bumps, scanners and rebases run as scripts. The agent is
   called only when they leave something red or something needs a judgement.
3. **Classify before spending.** Known infrastructure signatures (binary-cache timeouts,
   `store path … does not exist`, runner disk or network faults) stop the run with evidence
   instead of starting an agent. So does a failure that reproduces on pristine upstream.
4. **Fresh workspace per attempt**, at most three attempts, each fed the previous gate failure.
5. **The agent holds no write credential.** It edits a local clone. A separate step, holding the
   token, pushes a branch and opens the PR. Branch protection cannot be relied on: the API
   returns 403 for it on rots4 under the current plan.
6. **Bounded.** Per-attempt dollar cap (`omp --max-cost`, exit status 3, plus a LiteLLM key with
   `max_budget`), wall-clock cap (`--max-time` and the workflow deadline), a weekly fleet cap
   (LiteLLM budget with `budget_duration: 7d`). LiteLLM has its Postgres database
   (`argo/workloads/llm-proxy/cnpg-cluster.yaml`), so key budgets are enforced rather than
   failing open.
7. **Output is a PR, plus one digest.** Never a push to a default branch. Fork-sync's rebase also
   lands as a PR.

## Playbooks

A goal is a playbook: deterministic step, agent brief, done-check, output. Abstract goals stay
abstract in the brief; the done-check is what makes them safe to run unattended.

| Playbook | Deterministic step | Agent's job | Done when | Output |
|---|---|---|---|---|
| `deps-in-range` | `nix flake update`; `cargo update`; `bun update` / `npm update` within ranges | Read release notes of consequential bumps; map named breaking changes to "used here / not used"; fix what the bump broke; keep repo invariants (like #83's wasm-bindgen line) | Repo CI green on the branch | One PR per repo per week, #83's shape |
| `major-upgrade` | Bump one out-of-range major in the manifest, regenerate (e.g. `.sqlx`) | Port the code to the new API | Repo CI green; diff limited to the dependency's call sites | One PR per major, opened from the previous week's "Not included" list |
| `cve-review` | `osv-scanner`, `cargo audit`, `vulnix` (Nix closures), `npm audit` | Triage each finding: reachable or not, which fix | Every finding has a recorded disposition: fixed by a linked PR, not affected with a reason, or accepted | One issue per repo group; fixes become `deps-in-range` or `major-upgrade` runs |
| `fork-rebase` | Rebase the fork's patches onto upstream's newest green commit | Resolve conflicts and re-anchor patches per `fork-patches.md` | Full gate green; every patch commit still present (range-diff); no edit outside fork-owned paths | PR against `john`, replacing the hand repair |

"Not affected" reasons in `cve-review` are model-written; they land in the digest for a human to
skim rather than closing anything on their own.

## Architecture

```text
Temporal Schedule (weekly, e.g. Saturday 02:00 America/New_York)
  └─ FleetRun(playbook, repo group)
       ├─ per repo, at most 2–3 concurrently:
       │    RepoGoal(repo, playbook)
       │      1. classify / preflight          → infra fault? report and stop
       │      2. fresh clone on the runner VM
       │      3. deterministic step            → no change? done
       │      4. push branch, wait for repo CI
       │           green → open PR (no model spent)
       │           red   → attempt loop (≤3):
       │                     omp session in a fresh clone (no write token)
       │                     push branch, wait for repo CI
       │      5. out of attempts or budget → draft PR + written report
       └─ fan-in: weekly digest (one issue or board card) + ntfy
```

| Piece | Choice | Why |
|---|---|---|
| Schedule, fan-out, retries, long waits | Temporal 1.32.2, already in-cluster | Durable timers for "wait for CI" and "wait for John", typed retries, versioned workers. frigate-genai and john2143-com already run on it. |
| Worker | Python Temporal worker as a systemd unit on the `github` runner VM | The checkouts, Nix store and 40 vCPUs live there. Reuses frigate-genai's conventions (`config.py` retry policies, `_run_with_heartbeat`, SIGTERM drain), not its agent loop. |
| Agent | `omp -p --mode json --max-time … --max-cost …` | Hard caps, JSON events, resumable sessions, and it is the tool already maintained here. |
| Models | `llm.2143.me` (LiteLLM v1.110.2), one virtual key per attempt | Budget and rate limits per key; prompt logging. |
| Gate | Each repo's existing GitHub Actions CI on the pushed branch | Covers 25 of 28 repos with no per-repo gate code. The 3 without CI get report-only playbooks. |
| Digest | One GitHub issue in the steward repo, mirrored to a board card, ntfy on completion | One place to review the week. |

The agent loop of frigate-genai (`nixos/modules/frigate_genai/workflows/agent_session.py`) is
deliberately not reused: it ends when the model calls `set_description`, and it spreads each tool
call across pods with state in S3. A coding session needs one stateful clone and a gate the model
cannot satisfy by declaration.

### Per-repo opt-in

```yaml
# .steward.yml in each target repo
playbooks: [ deps-in-range, cve-review ]
ci_workflows: [ build_nix.yml ]     # which runs count as the gate
owned_paths: [ "**" ]               # narrower for forks
updates: [ nix-flake, cargo ]
invariants:                         # repo rules the agent must keep, checked by the gate where possible
  - "wasm-bindgen crate and CLI versions match (CLAUDE.md)"
auto_merge: false
```

### The PR it opens

Modelled on #83:

- Branch `steward/<playbook>/<yyyy-mm-dd>`; one commit
  `chore(deps): …` / `fix(deps): …` with old→new in the body; a `Co-authored-by` or
  `X-Agent:` trailer naming the agent identity.
- Body sections: **Summary** (old→new table for consequential bumps), **Breaking changes
  reviewed** (each named upstream change → used here or not, with evidence), **Not included**,
  **Verification** (commands run, on which commit, results; CI run link), **Not verified**,
  **Human attention**, **AI attribution** (model, attempts, cost, session link). Raw tool output
  in `<details>`.

## Security

The agent reads untrusted text every week: upstream changelogs, release notes, diffs and CI logs.
Logs are the worst channel (one 2026 preprint measured log-embedded instructions driving command
execution in 0–86.2% of trials depending on the model), and a repair goal is written by the
failure text itself. So:

- **No write token, no secrets in the session.** Push and PR creation happen in a separate
  activity. `GITHUB_TOKEN`-style variables are absent from the agent's environment.
- **Network allowlist** for the session: `llm.2143.me`, the package registries the playbook
  needs, GitHub read. Systemd `IPAddressAllow=` on the session's transient unit, or an nsjail
  wrapper.
- **New versions wait** a few days before adoption (Renovate calls this `minimumReleaseAge`)
  to dodge freshly compromised releases.
- **Token scope.** The push step uses a GitHub App or fine-grained PAT limited to the opted-in
  repos and to `contents` + `pull_requests`, following the argo Renovate PAT's pattern.
- **Stale-branch risk.** CI tests the branch, not the merge with the default branch (rots4
  `CLAUDE.md` records a green stale branch breaking `main` on 2026-11-09). The digest flags PRs
  whose base has moved since CI ran.

## Budget and capacity

- **Money.** Modelled, not measured: $0.53–$1.64 per repair attempt from the research. #83's
  shape needs no attempt at all when the bump is clean. Start with a $3 per-attempt cap and a
  weekly fleet cap to be decided.
- **Runner time.** One 40-vCPU VM also runs everyone's CI. oh-my-pi's full gate alone is about
  17 minutes of heavy CPU; rots4's test job took 24m33s cold in #83. Run overnight at
  concurrency 2–3, heavy repos serialized.
- **Review time** is the real limit: up to ~25 PRs a week if every repo opts in. One PR per repo,
  one digest, and auto-merge only where a playbook earns it.

## Reuse, build, rejected

**Reuse:** omp; Temporal and the worker-controller pattern; LiteLLM keys and budgets; each repo's
CI; the dotfiles → image → argo pipeline if the worker ever moves into the cluster.

**Build:** the playbooks, `.steward.yml`, the Temporal workflows (`FleetRun`, `RepoGoal`), the
PR and digest writers, the infrastructure-signature classifier.

**Decide later:** whether Renovate runs the deterministic bumps fleet-wide (it already handles
Cargo, npm and Nix flake inputs, grouping and release-age delays, and already runs in-cluster)
with steward only fixing red Renovate PRs and doing the analysis. Renovate's default is one PR per
package; #83's one-PR-per-week shape needs grouping configured.

**Evaluate before building:** LiteLLM's `litellm.agent()` harness (present from 1.105, so
available on the live 1.110.2) drives coding CLIs in a sandbox. Its maturity, and whether omp
works as its Pi runtime, are unverified.

**Rejected, with reason:**

| Option | Why not |
|---|---|
| Google AX (`google/ax`, v0.3.1 stable / v0.4.0-rc.1) | A sandbox control plane, not a loop: PR #756 (2026-11-24) removed task completion and failure states "for an external orchestrator". Needs Kubernetes 1.37+; the cluster is k3s v1.36.6. Nothing built on it orchestrates. Revisit as a sandbox after 1.0. |
| A new general harness | omp already is one. |
| A new orchestrator, Windmill, Tencent LoopForge, Restate | None beats Temporal, which is already running. LoopForge (v0.4.2) is the only one with a first-class verification gate but is four months old and needs the Docker socket. |
| gh-aw (GitHub Agentic Workflows) | Silently inert on forks, and its failure workflow only diagnoses. |
| robomp release sentinel (oh-my-pi `python/robomp`) | Closest prior art, but Docker Compose behind a public webhook, SQLite queue, and it pushes to the default branch and moves tags. Worth reading for prompts. |
| Hosted self-healing CI (GitHub Agent Merge, GitLab, Nx Cloud, Harness) | Hosted inference or a different CI; none rebases or works through LiteLLM on this runner. |

## Rollout

Each phase has an exit test; the next one starts only when it passes.

1. **`deps-in-range` on three repos by hand** (oh-my-pi, rots4, dotfiles): run the workflow
   manually, read every PR. Exit: three PRs at #83's quality, and measured cost, wall time and
   how often the deterministic step alone was green.
2. **`fork-rebase`**, replacing the repair job never built in `fork-sync.yml`. Exit: one real
   upstream conflict repaired to a green PR without a hand edit. `john`'s current red state (#507)
   is a ready test case.
3. **Weekly schedule** for those repos, with the digest. Exit: four consecutive weeks without a
   run needing a hand fix to the workflow itself.
4. **`cve-review`**, report-only, across all repos.
5. **Opt in the rest** of the repos with CI; **`major-upgrade`** for the "Not included" backlog.

## Open decisions

1. Renovate for the deterministic bumps fleet-wide, or steward runs the update commands itself.
2. Merge policy: always leave PRs, or auto-merge when only the deterministic step ran and CI is
   green.
3. Home and name: `2143-Labs` or `John2143`; final name.
4. Weekly fleet budget in dollars, and the default model.
5. Agent commit identity: a bot account or GitHub App, or John with a trailer.
6. How the worker on the runner VM authenticates to Temporal. `frigate-genai.md` says workers
   use SPIRE mTLS to `temporal-grpc.john2143.com:7233`; the VM reaches `192.168.6.20:7233` over
   TCP but has no SPIRE identity.
7. Temporal namespace: a new one with ~30-day retention (`default` keeps 72 hours).

## Known unknowns

- No live end-to-end test of omp through `llm.2143.me` in this loop; cost per run is modelled.
- `litellm.agent()` maturity.
- How a 17–25 minute CI wait behaves as a Temporal activity versus a timer-plus-poll.
- The real infrastructure-fault share of the fleet's red runs (the research's 15–40% is from
  other projects).

## Sources

Research reports under `~/repos/ai_research/`, each with a cited `final_report.md`:

- `what-is-the-thing-called-ax-or-ax-ax-from-google-that-someone-ev` — what Google AX is, fit
- `which-existing-products-and-open-source-projects-automatically-l` — self-healing CI products
- `which-headless-coding-agent-clis-and-sdks-can-run-fully-unattend` — headless CLIs, LiteLLM budgets
- `what-runtime-and-orchestration-layers-are-used-to-run-event-trig` — runtimes and orchestration
- `what-are-the-documented-security-risks-and-recommended-guardrail` — security guardrails
- `what-does-published-evidence-say-about-how-reliably-llm-coding-a` — repair reliability, session contracts
- `what-is-built-on-or-around-google-ax-agent-executor` — the AX ecosystem
- `how-to-orchestrate-google-ax-tasks-goal-verify-retry-escalate` — driving AX from an orchestrator
- `which-orchestrators-run-goal-driven-coding-agent-sessions-self-hosted` — 16 orchestrators compared

Those reports were briefed with LiteLLM at v1.100; the live proxy is v1.110.2, so their caveats
about `litellm.agent()` being unavailable no longer hold.
