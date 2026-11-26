# OMP web search: Parallel Search API

`modelRoles.web` is `web/parallel`. Searches go to the paid Parallel Search API,
which topped the independent search boards we looked at (Artificial Analysis
Search Index 2026-11-19: Parallel advanced 83 / fast 82 at $4.63 per 1k tasks;
Brave 75; DeepSeek 69) and costs from `$1 per 1,000 requests` (parallel.ai/pricing,
checked 2026-11-26).

## Layout

| Path | Role |
|---|---|
| `nixos/modules/omp-config.nix:148-149` | `models.yml` provider block: `parallel: { apiKey: "!sed … PARALLEL_API_KEY …" }`, an apiKey-only provider (no chat models) that only registers the credential |
| `nixos/modules/omp-config.nix:504-509` | `modelRoles.web: web/parallel` |
| `nixos/modules/omp-config.nix:527-536` | `retry.fallbackChains.web`: `brave`, `keenable`, `startpage` |
| `/run/agenix/llm-runtime-keys` | `PARALLEL_API_KEY=…` (agenix, same file as `DEEPSEEK_API_KEY`) |
| `~/.omp/agent/models.yml` | generated from the heredoc; `omp` resolves `!`-commands per request |

The key is read per request by a `!command`, never exported into `omp`'s
environment — the `omp` wrapper deliberately exports no keys. Get or rotate one
at <https://platform.parallel.ai/settings?tab=api-keys>, then edit the secret
from `~/repos/dotfiles/secrets`:

```sh
cd ~/repos/dotfiles/secrets && agenix -e llm-runtime-keys.age -i ~/.ssh/age
```

## What each failure mode does

`packages/coding-agent/src/web/search/providers/parallel.ts` (the pinned fork has
this identical) branches three ways:

| State | Behaviour |
|---|---|
| key resolves to a value | `POST https://api.parallel.ai/v1beta/search` with `x-api-key`, `mode: "fast"` |
| no credential configured at all | legacy keyless `https://search.parallel.ai/mcp` — *not* what we want, and Parallel plans to retire it |
| credential configured but empty | hard error (`Parallel credentials could not be resolved`); the fallback chain answers instead |

The third row is why hosts without `llm-runtime-keys` (or without the
`PARALLEL_API_KEY` line) keep working: search errors on `web/parallel` and walks
straight to Brave. There is deliberately no per-host gating.

## Why this engine

- Gemini native grounding was the previous default; on the same Gemini model
  Exa scored 41.36% against grounding's 37.04% (Vals Web Search), and Gemini
  grounding is `$14 per 1,000` after its free allowance.
- A LiteLLM `search_tools` block with `search_provider: parallel_ai` cannot be
  reached from OMP (OMP does its own search routing), so it would only help
  Claude Code on non-Anthropic models.
- The Parallel MCP server is unnecessary: OMP has a native `web/parallel`.
- Exa is out of the fallback chain: its keyless quota returned 429 in live tests.
- Keenable stays as the second fallback because it answers anonymously; Startpage
  needs no key at all.

## Verify

```sh
# live role and chain
omp config get modelRoles --json | jq -r '.value.web'          # web/parallel
omp config get retry.fallbackChains --json | jq -c '.value.web'

# the key is really being used (paid path, not the anonymous MCP)
omp search "today's top tech news" --limit 3                   # "Provider: Parallel"
sed -n 's/^PARALLEL_API_KEY=.*/present/p' /run/agenix/llm-runtime-keys   # present

# a temporary bad key must NOT fall back anonymously: it must 401
D=$(mktemp -d)
printf 'providers:\n  parallel:\n    apiKey: "!echo invalid-test-key"\n' > "$D/models.yml"
PI_CODING_AGENT_DIR=$D omp search "x" --model web/parallel --limit 2   # 401
rm -rf "$D"

# fallbacks (config with a broken key, real auth vault symlinked for Brave's key)
D=$(mktemp -d)
nix eval --raw '.#nixosConfigurations.office.config.home-manager.users.john.home.file.".omp/agent/config.yml".text' > "$D/config.yml"
printf 'providers:\n  parallel:\n    apiKey: "!echo invalid-test-key"\n' > "$D/models.yml"
ln -s ~/.omp/agent/agent.db "$D/agent.db"
PI_CODING_AGENT_DIR=$D omp search "today's top tech news" --limit 2   # Provider: Brave (API)
```

An explicit `--model web/parallel` runs that engine only, with no fallback, so a
401 is visible rather than masked.

Usage shows up on <https://platform.parallel.ai> → usage; a rising request count
is the proof that the paid endpoint — not the keyless MCP — served the search.

## Risks and rollback

- OMP calls `/v1beta/search`. Parallel's docs (2026-11) keep `/v1beta` for
  existing integrations and recommend `/v1` for new ones, with no published
  sunset. If a 404/410 ever appears, the fix is in the `oh-my-pi` fork
  (`packages/coding-agent/src/web/parallel.ts`), not here.
- Quota: a `402` means the account's free credits are spent. Search keeps working
  through Brave/Keenable until billing is added; no config change needed.
- Rollback: `git revert <the feat(omp) commit>` and rebuild, or set
  `web: web/brave` and rebuild. The `PARALLEL_API_KEY` line can stay; nothing
  reads it once the provider block is gone.
