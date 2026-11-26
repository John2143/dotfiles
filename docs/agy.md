# Antigravity CLI (`agy`)

`agy` is Google's terminal coding agent, installed from numtide's `llm-agents`
flake. It signs in with a Google AI Pro subscription, so it talks to Google
directly: it is **not** a LiteLLM backend, gets no wrapper and no API key.

It gets the same skills (`.claude/skills/`, 35) and task agents
(`.omp/agent/agents/`, 3) as OMP and Claude Code, plus OMP's `SYSTEM.md` as its
global rules.

## Layout

| Path | Role |
|---|---|
| `nixos/shared-cli-configuration.nix:64` | package on office and arch (`inputs.llm-agents…antigravity-cli`) |
| `nixos/darwin-configuration.nix:65` | package on mac |
| `nixos/home-macbook.nix:81` | package on macbook (home profile, not system) |
| `nixos/home-cli.nix:31` | imports the module below |
| `nixos/modules/agy-config.nix` | the whole wiring: `agy-skills`, `agy-agents`, the three `.gemini` files |
| `nixos/scripts/convert-skills.py:15` | `--agy ROOT` mode of the shared skill converter |
| `nixos/scripts/agy-agents.py` | OMP agent → agy subagent translation |
| `nixos/modules/omp-config.nix:705` | `SYSTEM.md`, the file `~/.gemini/GEMINI.md` points at |
| `~/.gemini/config/skills.json` | `{"entries":[{"path":"/nix/store/…-agy-skills"}]}` |
| `~/.gemini/config/agents.json` | same shape, pointing at `…-agy-agents` |

## Why JSON manifests instead of file links

OMP links every skill file individually (`~/.omp/agent/skills/<file>`) and so
does the Claude copy. **agy loads none of them**: it skips a `SKILL.md` that is
a symlink, and a skill folder that is a symlink (tested both; a symlinked
*manifest* and a symlink *above* the skill folders are fine). So
`agy-config.nix` builds two store directories and registers them with
`skills.json` / `agents.json`, agy's "declared" customization tier. Those rank
below workspace skills, so anything written by hand in
`~/.gemini/config/skills/` still wins on a name clash — and nothing
home-manager writes is ever in the way of a quick experiment.

Same fact in one line, for whoever wires a third harness next: **agy only reads
regular files inside a customization root.**

## What the converter changes for agy

`convert-skills.py --agy ROOT` (the Claude Code path is unchanged; its output is
byte-identical to before the rename from `claude-skills.py`):

- **`name` is added.** OMP infers it from the folder; agy warns without it.
- **`description` and `argument-hint` are quoted.** agy parses frontmatter as
  strict YAML and silently skips the skill when it fails: `argument-hint: [a] [b]`
  is two flow sequences and killed `commit-writer`, `create-skill`, `debugging`
  and `nix-gardener`. The result is YAML-checked at build time
  (`convert-skills.py:183`), so a bad skill breaks the build instead of quietly
  vanishing. Other keys keep their YAML types (`disable-model-invocation: true`
  stays a boolean).
- **`allowed-tools` is dropped**; agy has no such key.
- **Self-references point at `ROOT/<skill>/`**, because agy has no
  `${CLAUDE_SKILL_DIR}`.
- **`tool-hints`** still moves into a `## Tool hints` body section.

`disable-model-invocation` works in agy: `action`, `grill-me` and `pontificate`
are hidden from the model and run only as slash commands.

## Agents

`agy-agents.py` keeps the prompt body and rewrites the frontmatter:
`subagent: true`, `mainAgent: false`, OMP tools mapped to agy's
(`read`→`read_file`, `bash`→`run_command, manage_task`, `web_search`→`search_web`,
and so on; an unmapped tool fails the build). `model`, `thinking-level` and
`spawns` are dropped — agy runs Gemini, so agents inherit the session's model.
A `spawns` that names another shipped agent becomes `agents: [<name>.md]` plus
the `invoke_subagent` tool. agy has no `scout`, so those agents carry a short
note to do that reading themselves.

## Rules

`~/.gemini/GEMINI.md` is the same file as `~/.omp/agent/SYSTEM.md` (16 KB, under
agy's 24 KB per-file cap; `SYSTEM.md` must stay under that). Lines about
OMP-only tools (eval, IRC, async jobs) come along and are ignored by agy. If
`SYSTEM.md` ever grows past the cap, split it — agy truncates silently at 24 KB,
on line boundaries.

## Not wired: the board MCP

The `ai_tasks` MCP server is an agenix secret, so it is not in the Nix store.
Add it once per machine (the token stays in your shell):

```fish
set s (jq -c '.mcpServers.ai_tasks' /run/agenix/omp-mcp)
agy mcp add -H "Authorization: "(echo $s | jq -r '.headers.Authorization') ai_tasks (echo $s | jq -r .url)
agy mcp list
```

Without it, `context-task`, `finish-up` and the card rules in `SYSTEM.md` have
no board to talk to.

## Known collisions

- **`grill-me`**: agy ships a built-in `/grill-me`, which wins over the skill of
  the same name. The skill is still loaded for the model in principle, but it is
  `disable-model-invocation`, so on agy that name is effectively the built-in.
- No other skill name clashes with an agy built-in (checked against 1.5.17).

## Checking a change

```sh
# build the two store directories without touching the live config
out=$(nix build --no-link --print-out-paths .#nixosConfigurations.office.config.home-manager.users.john.home-files)
S=$(jq -r '.entries[0].path' $out/.gemini/config/skills.json)   # the agy-skills path
A=$(jq -r '.entries[0].path' $out/.gemini/config/agents.json)

# agy's own validator, strict: wants a plugin.json wrapper
V=$(mktemp -d); printf '{"name":"check","version":"1.0.0"}\n' > $V/plugin.json
cp -r --no-preserve=mode $S $V/skills; cp -r --no-preserve=mode $A $V/agents
agy plugin validate --strict $V     # expect: skills 35 · agents 3 · ✔ Validation passed
rm -rf $V
```

To see what agy actually loads **without touching the live config**, run it with
a throwaway `HOME` holding the same symlinks home-manager creates:

```sh
T=$(mktemp -d); mkdir -p $T/.gemini/config
ln -s ~/.gemini/antigravity-cli $T/.gemini/antigravity-cli     # reuse the sign-in
for f in .gemini/GEMINI.md .gemini/config/skills.json .gemini/config/agents.json; do
  ln -s $HOME/$f $T/$f   # after a switch; or point at the result/ paths above
done
cd /tmp && HOME=$T agy -p "List every skill you have and every subagent."
```

Expect 32 model-visible skills (35 installed, 3 user-only) plus agy's own
built-ins, and `oracle`, `web-research-orchestrator`, `web-researcher`.

## Updates

`agy` comes from the `llm-agents` input, which the weekly fleet patch does
**not** bump — see `fleet-patching.md`. Move it by hand:

```fish
cd ~/dotfiles && nix flake update llm-agents   # then switch one host
```

`agy`'s own self-updater cannot replace the `/nix/store` binary; an "update
available" notice means this command.
