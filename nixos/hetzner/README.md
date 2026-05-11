# Hetzner Enterprise HA Platform

6-node + Home Pi Kubernetes platform across 3 geographic regions on Hetzner Cloud.

**Stack**: NixOS / k3s / Cilium / Istio / Traefik+CrowdSec / k8gb+PowerDNS(MariaDB Galera)+ExternalDNS(RFC2136) / Bunny CDN / SeaweedFS / B2 / Longhorn / MongoDB / CloudNativePG / Temporal / ArgoCD

**Modes**: LA (3 server nodes, ~$75/mo) or HA (6 nodes, ~$140/mo).

## Structure

```
nixos/hetzner/
├── modules/           # Shared NixOS modules
│   ├── hetzner-disko.nix
│   ├── hetzner-powerdns.nix
│   ├── hetzner-galera.nix
│   ├── hetzner-k3s-server.nix
│   └── hetzner-k3s-agent.nix
├── hosts/             # Per-node configurations
│   ├── ashburn-server.nix
│   ├── ashburn-agent.nix
│   ├── hillsboro-server.nix
│   ├── hillsboro-agent.nix
│   ├── nuremberg-server.nix
│   └── nuremberg-agent.nix
└── scripts/           # Provisioning and management
    ├── provision.sh
    ├── toggle-ha.sh
    ├── toggle-la.sh
    └── demo.sh
```

## Quick Start

### Demo (~$8-10 for 48 hours)

```bash
export HCLOUD_TOKEN="your-hetzner-api-token"
cd nixos/hetzner/scripts
./demo.sh
# Deploys 3 server nodes, verifies them, tears down

./demo.sh --keep
# Same but leaves nodes running
```

### Deploy for production

```bash
# LA mode (3 nodes, ~$75/mo)
./provision.sh ashburn server
./provision.sh hillsboro server
./provision.sh nuremberg server

# HA mode (+3 agents, ~$140/mo)
./toggle-ha.sh

# Back to LA mode
./toggle-la.sh
```

## Prerequisites

- [Hetzner Cloud](https://www.hetzner.com/cloud) account + API token
- `hcloud` CLI (`nix shell nixpkgs#hcloud`)
- `nixos-anywhere` available via flake
### Generating secrets

All secrets are encrypted with [agenix](https://github.com/ryantm/agenix). The `secrets/secrets.nix` file defines which public keys can decrypt each secret — add your host keys there before generating.

From `nixos/hetzner/secrets/`, run:

```bash
# 1. Hetzner API token (interactive — paste your token, then Ctrl+D)
agenix -e hcloud-token.age -i ~/.ssh/age

# 2. Auto-generated secrets (random base64 from /dev/urandom)
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e k3s-token.age        -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e luks-passphrase.age   -i ~/.ssh/age
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e galera-password.age        -i ~/.ssh/age
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e mariadb-root-password.age  -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e powerdns-tsig-key.age      -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e mongodb-encryption-key.age  -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e seaweedfs-master-key.age    -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e rclone-b2-password.age      -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e rclone-rustfs-password.age  -i ~/.ssh/age
```

> **Note:** `-i ~/.ssh/age` is your age identity (the private key matching a public key in `secrets.nix`). The `secrets.nix` entry for a secret must exist *before* running `agenix -e` for that file.
- Domain delegated to PowerDNS nameservers

## Architecture

See `hosting-research.md` and `hosting-next-steps.md` at the repo root.
