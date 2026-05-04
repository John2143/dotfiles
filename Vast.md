# Vast.ai Cloud GPU Workflow

Run large LLMs (e.g. DeepSeek V4 Flash, 158 GB FP4+FP8) on temporarily-rented
GPUs from Vast.ai. The local fish helpers wrap the upstream `vastai` CLI for
the common operations; vLLM runs on the rental and is reached via SSH tunnel,
exposing the same OpenAI-compatible surface as the local `office-vllm` server.

## Architecture

```
┌──────────────────────────┐         SSH tunnel              ┌──────────────────────────┐
│ workstation (NixOS)      │  localhost:8001 → rental:8000   │ Vast.ai rental (Ubuntu)  │
│ vastai CLI ──────────────┼─→ instance management            │ vllm serve (background)  │
│ omp/claude → models.yml ─┼─→ http://localhost:8001/v1       │ HF cache @ /workspace    │
│ /run/agenix/             │                                  │                          │
│   vast-credentials       │                                  │                          │
│     (API key + SSH key)  │                                  │                          │
│ /run/user/$UID/          │                                  │                          │
│   vast-ssh-key (mat'd)   │                                  │                          │
│ ~/.config/vast/profile   │                                  │                          │
│   (optional, plain text) │                                  │                          │
└──────────────────────────┘                                  └──────────────────────────┘
```

## Credential model

Three tiers, by rotation cadence:

| Where | What | Edited |
|---|---|---|
| `/run/agenix/vast-credentials` | `VAST_API_KEY` + `VAST_SSH_PRIVATE_KEY_B64` + optional `VAST_HF_TOKEN` | Rare (only on account API, SSH key, or HF token rotation) |
| `/run/user/$UID/vast-ssh-key` | SSH private key materialized from b64 (0600, tmpfs) | Auto-created by `_vast-load`; wiped on logout |
| Vast.ai API (live) | Current rental's `VAST_HOST` and `VAST_SSH_PORT` | Auto-discovered every command via `vastai show instances --label $VAST_LABEL` |
| `~/.config/vast/profile` | Optional non-secret overrides (model, max_len, ports, manual host pin) | Anytime — plain file, no nix rebuild |

Why one combined credentials file: API key and SSH key are protected by the
same agenix master key on the same hosts, so splitting them adds no security.
SSH wants a file path, the API wants an env var; the materialization step
bridges that without a second `.age` file.

Renting a fresh instance triggers **zero file edits and zero rebuilds**: `vast-create`
labels the new instance, and the next `vast-bootstrap` finds it automatically.

## One-time setup

### 1. Generate the SSH keypair

```fish
ssh-keygen -t ed25519 -f /tmp/vast-key -N ""
```

Upload `/tmp/vast-key.pub` to <https://cloud.vast.ai/account/keys> so it's
auto-added to every instance you launch.

### 2. Create the combined credentials file

Get an API key at <https://cloud.vast.ai/account/> and (strongly recommended)
a Hugging Face token at <https://huggingface.co/settings/tokens> for faster
model downloads and access to gated models. Then:

```fish
cd ~/dotfiles
echo "VAST_API_KEY=<your key>"
echo "VAST_SSH_PRIVATE_KEY_B64=$(base64 -w0 /tmp/vast-key)"
echo "VAST_HF_TOKEN=<your hf token>"   # optional but recommended
# Copy the lines, then:
agenix -e secrets/vast-credentials.age -i ~/.ssh/age
# Paste them into the editor.
```

Shred the local key files:

```fish
shred -u /tmp/vast-key /tmp/vast-key.pub
```

### 3. (Optional) per-user profile overrides

Defaults baked into the fish helpers cover the DeepSeek V4 Flash workflow.
If you want to override (different model, parsers, label, manual host):

```fish
mkdir -p ~/.config/vast
cp ~/.config/vast/profile.example ~/.config/vast/profile
$EDITOR ~/.config/vast/profile
```

The `profile.example` template is shipped via home-manager and documents
every field. Edit `profile` freely — it's plain text on your home directory,
no rebuild needed.

### 4. Apply the NixOS config

```fish
nh os switch .
```

After this, `/run/agenix/vast-credentials` is mounted, the `vastai` wrapper
is on PATH, and the fish helpers are loaded. On the first `vast-*` call,
`_vast-load` materializes the SSH private key to
`/run/user/$UID/vast-ssh-key` (0600, tmpfs).

## Renting

```fish
vast-search                       # default: verified 1×B200, ≥99% reliability
vast-search 'gpu_name=H200'       # override the query (full vastai filters)
vast-create 12345678              # OFFER_ID from vast-search output
vast-show                         # id=… status=running host=… ssh_port=…
```

`vast-create` launches with:

- **Image**: `nvidia/cuda:12.8.0-devel-ubuntu24.04` — clean upstream CUDA, no
  auto-launched services
- **Disk**: 300 GB on `/workspace` (158 GB model + ~140 GB headroom)
- **SSH**: `--direct` (not proxied) for low-latency tunneling
- **Label**: `vllm-deepseek-v4` so the helpers find it

## Spinup / Bootstrap

Once `vast-show` reports `status=running`, just:

```fish
fish -c vast-bootstrap            # ~25 min first time
fish -c vast-tunnel               # localhost:8001 → rental:8000
fish -c vast-status               # confirm vLLM responds
```

No agenix edit, no nix rebuild between rentals — the helpers query the API
for the current host/port on every invocation.

`vast-bootstrap` is idempotent. What it does remotely:

1. Sets `TMPDIR`, `HF_HOME`, `PIP_CACHE_DIR` to `/workspace/*` (Vast.ai's `/`
   overlay is only 32 GB and fills up otherwise).
2. Disables `hf-xet` / `hf-transfer` to avoid `Background writer channel
   closed` failures on overlayfs.
3. Stops any supervisord-managed vLLM that ships with Vast.ai's vLLM templates.
4. For DeepSeek V4 models, auto-adds `--kv-cache-dtype fp8`,
   `--tool-call-parser deepseek_v4`, and `--reasoning-parser deepseek_v4` so
   `reasoning_content` is split out from the final answer in OpenAI-API
   responses.
5. `pip install vllm` if not preinstalled (~5 min).
6. `nohup vllm serve …` in the background, logging to `/workspace/vllm.log`.
7. Polls `/v1/models` for up to 20 minutes.

## Using

In `omp` (or any OpenAI-compatible client), pick the
**`vast-vllm/deepseek-v4-flash`** model. Traffic routes via the local tunnel.

DeepSeek V4 launches with `--reasoning-parser deepseek_v4`, so chat
completions return `choices[].message.reasoning_content` (the chain of
thought) separately from `choices[].message.content` (the final answer).
Clients that don't know about `reasoning_content` see only the final answer,
which is usually what you want. `reasoning_effort: low|medium|high` is
honored as a top-level request parameter.

Direct test:

```fish
curl http://localhost:8001/v1/models
curl http://localhost:8001/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Hello"}]}'
```

Live remote logs:

```fish
fish -c vast-logs                 # tail -f /workspace/vllm.log
fish -c vast-logs 500             # show last 500 lines first
```

## Shutdown / Cleanup

```fish
fish -c vast-tunnel-down          # close the local SSH tunnel
vast-show                         # confirm instance ID
vast-destroy 78901234             # stops billing
```

Local cleanup is automatic. Both agenix-mounted secrets persist across
reboots and across rentals — they're long-lived.

## Re-renting

```fish
vast-show                         # if previous still up: vast-destroy <id>
vast-search | head
vast-create <new offer id>
sleep 30                          # wait for SSH to be ready
vast-show                         # confirm running
fish -c vast-tunnel-down          # in case the previous tunnel is still up
fish -c vast-bootstrap
fish -c vast-tunnel
```

That's the entire re-rental flow. Each new instance gets the same
`vllm-deepseek-v4` label, so `vast-bootstrap` automatically picks it up.

Each rental is a fresh VPS with a different SSH host key. The tunnel uses
`UserKnownHostsFile=/dev/null` and `StrictHostKeyChecking=no` so the host-key
mismatch is harmless — we authenticate with our key, not the server's.

## Pinning to a specific instance (manual override)

If you want the helpers to talk to a non-labelled instance, or the API is
flaky, set `VAST_HOST` and `VAST_SSH_PORT` in `~/.config/vast/profile`:

```
VAST_HOST=1.2.3.4
VAST_SSH_PORT=12345
```

The helpers skip API discovery whenever both are set. Comment them back out
to resume auto-discovery.

## Multi-rental (parallel workloads)

Different `--label` values let you run multiple rentals at once. Set a
different `VAST_LABEL` in `~/.config/vast/profile` (or per-shell:
`set -gx VAST_LABEL my-other-job`) and edit `vast-create` similarly.
Each label is independently discoverable.

## Command reference

| Command | What it does |
|---|---|
| `vast-search [query]` | List verified B200 offers (default query: 1×B200, 99%+ reliability, ≥5 Gbps, ≥250 GB) |
| `vast-create OFFER_ID` | Launch a new rental with our minimal CUDA image |
| `vast-show` | List active rentals tagged `vllm-deepseek-v4` |
| `vast-destroy INSTANCE_ID` | Tear down a rental |
| `vast-bootstrap [--restart]` | SSH in and (re)launch vLLM remotely. Idempotent by default; `--restart` kills the running vllm and re-launches (use after changing parsers/flags) |
| `vast-tunnel` | Open localhost:8001 → rental:8000 SSH tunnel |
| `vast-tunnel-down` | Close the tunnel |
| `vast-status` | Show tunnel + vLLM readiness |
| `vast-logs [N]` | Tail the remote vLLM log |
| `vastai …` | Raw upstream CLI (auto-loads `VAST_API_KEY`) |

All `vast-*` helpers internally call `_vast-load`, which sources
`~/.config/vast/profile`, applies defaults, and discovers the host via the
Vast.ai API.

## File reference

| Path | Purpose |
|---|---|
| `Vast.md` | This file |
| `secrets/vast-credentials.age` | Combined VAST_API_KEY + VAST_SSH_PRIVATE_KEY_B64 (long-lived) |
| `/run/user/$UID/vast-ssh-key` | SSH key materialized at runtime from the b64 above (0600, tmpfs) |
| `~/.config/vast/profile` | Plain-text user overrides (optional) |
| `~/.config/vast/profile.example` | Documented template (managed by home-manager) |
| `nixos/shared-cli-configuration.nix` | `vastai` wrapper + `age.secrets` entry |
| `nixos/home-cli.nix` | `vast-*` fish helpers + `vast-vllm` provider in models.yml |
| `.config/vast-bootstrap.bash` | Remote launch script (sourced via `ssh bash -s`) |

## Troubleshooting

### `vast-bootstrap` reports `Free memory on device cuda:0 (12 GiB)`

A supervisord-managed vLLM is hogging the GPU. Bootstrap attempts to stop it
automatically; if that failed, manually:

```fish
ssh -i /run/user/(id -u)/vast-ssh-key -p (vast-show | string match -r 'ssh_port=(\d+)' | tail -1) root@(vast-show | string match -r 'host=(\S+)' | tail -1) 'supervisorctl stop vllm'
```

(Run any `vast-*` helper first to materialize the SSH key file.) Or just
`vast-destroy` and re-`vast-create` on the minimal image.

### `Background writer channel closed` during model download

The container's `/` overlay filled up. Bootstrap pins `HF_HOME` and `TMPDIR`
to `/workspace` and clears `/tmp` if it's >50% full, but if the rental was
created with a tiny disk, destroy it and re-create with `--disk 300` (the
`vast-create` default).

### Responses lack a `reasoning_content` field

The running vLLM was started without `--reasoning-parser`. Confirm by
grepping the remote log:

```fish
fish -c 'vast-logs 200' | grep -i reasoning_parser
```

If you see `reasoning_parser=None` or "Auto-initialization of reasoning
token IDs failed", re-launch with the current bootstrap flags:

```fish
fish -c 'vast-bootstrap --restart'
```

This kills the running vllm and relaunches it with the parsers the
bootstrap script auto-sets for DeepSeek V4. No need to destroy the rental.

### `DeepseekV4 only supports fp8 kv-cache format`

Bootstrap auto-adds `--kv-cache-dtype fp8` for DeepSeek V4 models. If you set
`VAST_EXTRA_ARGS` manually with a different `--kv-cache-dtype`, fix or unset it.

### `Permission denied (publickey)` on first SSH

Vast.ai takes ~30–60 seconds to install your authorized key on a freshly
launched instance. Retry after a minute, or verify the key is uploaded at
<https://cloud.vast.ai/account/keys>.

### `No running Vast.ai instance with label '…' found`

Either no instance is rented, the instance is still booting, or it's tagged
with a different label. Check `vast-show` (or unfiltered `vastai show
instances`). Set `VAST_LABEL` in `~/.config/vast/profile` if you've changed
labels; or pin host/port directly with `VAST_HOST` + `VAST_SSH_PORT`.

### Tunnel keeps dying

`vast-tunnel --restart` recreates the systemd user unit. The unit already has
`ServerAliveInterval=30` and `ServerAliveCountMax=3`; if it still flaps, your
upstream connection is dropping packets — try a wired/ethernet link.

### `vastai CLI not found`

The wrapper lives in `environment.systemPackages` for `office`/`arch` only.
Rebuild after enabling: `nh os switch .`. On other machines, install `pkgs.uv`
manually and run `uvx vastai …` directly.

## Migration from earlier credential layouts

If you set this up before the API-discovery refactor, you may have either:

**(a) `vast-connection.age`** — the original combined per-rental file with
host/port baked in. Extract the API key (if you had it elsewhere — likely in
`vastai-key.age`) and the SSH key:

```fish
# Decrypt the old per-rental file
agenix -d secrets/vast-connection.age -i ~/.ssh/age > /tmp/old-conn

# Get the SSH key b64 line
grep VAST_SSH_PRIVATE_KEY_B64 /tmp/old-conn

# Get your API key (if you had vastai-key.age)
agenix -d secrets/vastai-key.age -i ~/.ssh/age

# Build the new combined file:
agenix -e secrets/vast-credentials.age -i ~/.ssh/age
# Paste:
#   VAST_API_KEY=<from vastai-key.age>
#   VAST_SSH_PRIVATE_KEY_B64=<from VAST_SSH_PRIVATE_KEY_B64 line>

# Clean up
rm secrets/vast-connection.age secrets/vastai-key.age secrets/vast-ssh-key.age 2>/dev/null
shred -u /tmp/old-conn
```

**(b) Split `vast-ssh-key.age` + `vastai-key.age`** — the brief intermediate
layout. Combine:

```fish
agenix -d secrets/vastai-key.age -i ~/.ssh/age          # → VAST_API_KEY=...
agenix -d secrets/vast-ssh-key.age -i ~/.ssh/age \
  | base64 -w0                                          # → b64 of raw key

# Build the combined file
agenix -e secrets/vast-credentials.age -i ~/.ssh/age
# Paste both fields, then:
rm secrets/vastai-key.age secrets/vast-ssh-key.age
```

Then in either case:

```fish
nh os switch .
```

After migration, `vast-bootstrap` and `vast-tunnel` no longer require any
edit between rentals.

## Market context (May 2026)

Verified 1×B200 hosts run **$3.94–6.25/hr** on Vast.ai — roughly 8–20× cheaper
than hyperscalers (AWS p5e.48xlarge with 8×H200 = $39.80/hr; Azure ND H100 v5 ≈
$98/hr). The default `vast-search` filters out low-reliability and
underprovisioned listings.

For DeepSeek V4 Flash specifically, a single B200 is the sweet spot:

- 179 GB usable VRAM holds the 158 GB FP4+FP8 weights with ~20 GB free
- V4's hybrid attention shrinks 1M-token KV cache to ~10 GB (10% of V3.x)
- Native FP4 tensor cores give full speed on V4's quantized weights
- MoE with 13 B active params fits comfortably on a single GPU

Avoid templates whose names mention "vLLM Inference" or "vLLM Openai" —
those auto-launch a small DeepSeek-R1-Distill model at boot via supervisord
that holds the entire GPU. Bootstrap can dispose of it but it's friction.
The minimal `nvidia/cuda:12.8.0-devel-ubuntu24.04` image used by
`vast-create` avoids the entire issue.
