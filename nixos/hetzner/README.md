# Hetzner Enterprise HA Platform

3-node + Home Pi Kubernetes platform on Hetzner Cloud.

**Stack**: NixOS / k3s / Flannel / ArgoCD / PowerDNS / ExternalDNS (RFC2136) / SeaweedFS / B2 / Longhorn / MongoDB / CloudNativePG (PostgreSQL) / Temporal

**Modes**: LA (3 server nodes, ~$75/mo) or HA (6 nodes, ~$140/mo).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Tailnet (ts.9s.pics) — Headscale on home-pi               │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ k3s-ashburn  │  │k3s-hillsboro │  │k3s-nuremberg │      │
│  │ control-plane│  │ control-plane│  │ control-plane│      │
│  │ pdns         │  │ pdns         │  │ pdns         │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│          │                 │                 │              │
│          └─────────┬───────┴─────────────────┘              │
│                    │                                        │
│           ┌────────┴────────┐                               │
│           │    home-pi      │                               │
│           │ Headscale :6767 │                               │
│           │ pdns (tiebreak) │                               │
│           └─────────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

All 3 server nodes are fully interchangeable (identical mkServer config). Each runs k3s + PowerDNS. PostgreSQL runs inside k3s via CloudNativePG — all services (PowerDNS, Temporal, future) share a single PostgreSQL cluster. Nodes communicate over the tailnet (Headscale at home-pi).

## Structure

```
nixos/hetzner/
├── flake.nix                     # mkServer/mkAgent/mkHome functions
├── modules/
│   ├── hetzner-disko.nix         # Disk layout (EF02 + EFI + ext4)
│   ├── hetzner-ssh.nix           # SSH + agenix identity
│   ├── hetzner-k3s-common.nix    # k3s + Flannel + ArgoCD + CNPG + cert-manager bootstrap
│   ├── hetzner-k3s-server.nix    # Adds PowerDNS + PostgreSQL schema import
│   ├── hetzner-k3s-agent.nix     # Agent node (k3s agent only)
│   ├── hetzner-powerdns.nix      # PowerDNS authoritative server
│   ├── hetzner-powerdns-bootstrap.nix  # Zone creation (oneshot)
│   ├── hetzner-postgres-schema.nix  # Import pdns schema into CNPG PostgreSQL
│   ├── headscale.nix             # Headscale coordination server
│   ├── tailscale.nix             # Tailscale client (parameterized login-server)
│   └── longhorn-host.nix         # Longhorn storage
├── hosts/
│   ├── home-pi.nix               # Home Pi (Headscale + pdns)
│   └── home-pi-hardware-configuration.nix
├── secrets/
│   ├── secrets.nix               # agenix public key mapping
│   └── hetzner/*.age             # Encrypted secrets
└── scripts/
    ├── provision.sh              # VM create + nixos-anywhere + post-deploy
    ├── desec-dns.sh              # deSEC DNS record management
    ├── toggle-ha.sh
    ├── toggle-la.sh
    └── demo.sh
## Quick Start

```bash
export HCLOUD_TOKEN=$(agenix -d $PWD/secrets/hetzner/hcloud-token.age -i ~/.ssh/age)
cd nixos/hetzner/scripts

./provision.sh ashburn server
./provision.sh hillsboro server
./provision.sh nuremberg server
```

The provision script automates the full pipeline: VM creation, nixos-anywhere deploy, age key copy, agenix decrypt, pdns schema import, tailscale connect, service verification.

## Prerequisites

- Hetzner Cloud account + API token (in `secrets/hetzner/hcloud-token.age`)
- `hcloud` CLI, `jq`, `nixos-anywhere` available via flake
- SSH key `john@office` uploaded to Hetzner (`hcloud ssh-key create`)
- Home-pi running Headscale (see `hosts/home-pi.nix`)
- Port forward `6767 → home-pi:6767` on home router
- DNS `headscale.9s.pics` → home public IP

### Generating secrets

All secrets are encrypted with [agenix](https://github.com/ryantm/agenix). From `nixos/hetzner/secrets/`:

```bash
# Hetzner API token
agenix -e hetzner/hcloud-token.age -i ~/.ssh/age

# Generated secrets
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e hetzner/k3s-token.age -i ~/.ssh/age
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e hetzner/postgres-pdns-password.age -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e hetzner/powerdns-tsig-key.age -i ~/.ssh/age
```

### Headscale preauth key (generate once on home-pi)

```bash
ssh 192.168.0.154 "sudo headscale users create hetzner-nodes"
ssh 192.168.0.154 "sudo headscale preauthkeys create --user 1 --reusable --expiration 87600h"
# Encrypt the output key on arch:
echo -n "hskey-auth-..." | agenix -e nixos/hetzner/secrets/hetzner/headscale-preauth-key.age -i ~/.ssh/age
```

## deSEC DNS Management

The `desec-dns.sh` script manages DNS records for `9s.pics` via the deSEC API.

```bash
# Encrypt the deSEC API token (one-time):
cd nixos/hetzner/secrets
echo -n "YOUR_DESEC_TOKEN" | agenix -e hetzner/desec-token.age -i ~/.ssh/age

# Usage:
cd nixos/hetzner/scripts
./desec-dns.sh list                          # List all records
./desec-dns.sh set-a headscale 1.2.3.4       # Set A record
./desec-dns.sh update-headscale              # Auto-detect public IP and update
./desec-dns.sh update-all-nodes              # Update all node + headscale records
```

## CloudNativePG setup

PostgreSQL runs inside k3s via CloudNativePG (installed automatically by `argocd-bootstrap`). On first boot, the CNPG Cluster CR creates a PostgreSQL instance with `pdns` database and user via `bootstrap.initdb`.

**Important**: CNPG 1.25 generates a random password. The `hetzner-postgres-schema` oneshot waits for PostgreSQL then imports the schema and resets the pdns password to match the agenix secret.

```bash
# Verify PostgreSQL
ssh root@<IP> "pg_isready -h 127.0.0.1 -p 30432 -U pdns -d pdns"
# Verify PowerDNS
ssh root@<IP> "systemctl status pdns"
```

## Known Issues

### CNPG 1.25 — `bootstrap.initdb` not `spec.managed`
`spec.managed` was introduced in CNPG 1.26+. The pdns user password must be reset after cluster creation.

### `pdnsutil` needs `--config-dir=/run/pdns`
Runtime config with decrypted secrets lives at `/run/pdns/pdns.conf`. Always use `pdnsutil --config-dir=/run/pdns`.

### `postgres-pdns-password` must be owned by `pdns`
If pdns fails to start: `chown pdns:pdns /run/agenix/hetzner/postgres-pdns-password`

### ExternalDNS TSIG secret key naming
The Helm chart (v1.21.1+) expects the RFC2136 credentials secret to have key `tsig-key`, not `rfc2136TsigSecret`. The `k8s-secrets-bootstrap` oneshot now uses `tsig-key`. All ArgoCD manifests in 2143-59s reference `tsig-key`.

### ExternalDNS Helm + TSIG args
ExternalDNS Helm chart v1.21.1+ does not pass `--rfc2136-*` args to the deployment container. The `argocd-bootstrap` script patches the deployment post-install with the correct args. Do not remove the `kubectl patch` block after the `helm upgrade` for external-dns.

### ArgoCD ConfigMap (argocd-cm)
The ArgoCD ConfigMap with health checks is applied inline in the bootstrap script (not from a repo file). The health check Lua script uses a permissive default ("Healthy") to avoid stalling wave progression on resources that can't report health (e.g., cert-manager Certificates pending DNS01). Only "Degraded" blocks sync.

### Traefik chart version pin
Traefik chart v35+ has template errors with `hostPort` and `hostNetwork`. The bootstrap pins `--version 34.0.0` and omits hostPort/hostNetwork. These can be re-added when DDoS protection is needed (on raw IP interface only).

## Provisioning lessons (from attempts #1 and #2)

### NixOS boot on Hetzner Cloud
- **Disko layout**: Must include EF02 BIOS boot partition (1M) + EFI partition + ext4 root. Without EF02, GRUB can't install on GPT.
- **GRUB device**: `/dev/sda` (not `nodev`). Sets up both i386-pc and x86_64-efi boot.
- **Kernel modules**: Import `qemu-guest.nix` profile; add `virtio_pci`, `virtio_scsi`, `sd_mod`, `ext4` to `boot.initrd.availableKernelModules`.
- **CPX32 / EU datacenters**: cpx32 VMs in European DCs (nbg1, fsn1) consistently fail to boot NixOS. All nodes currently use cpx31 in ashburn. This may be a Hypervisor/KVM version difference.

### agenix identity
- Hetzner VMs have no age identity at first boot. The host SSH key (`/etc/ssh/ssh_host_ed25519_key`) doesn't match agenix encryption keys.
- **Fix**: The provision script copies `~/.ssh/age` (the age identity key) to `/etc/ssh/age-identity` so the post-deploy `nixos-rebuild` can decrypt all secrets.

### tailscale connectivity
- `tailscale up` needs `--reset` flag to override existing config (left from initial deploy).
- Must restart `tailscaled` before `tailscale up` on fresh deploys.
- Never `tailscale logout; tailscale up` — creates duplicate identities. Use `systemctl restart tailscaled-autoconnect` instead.
- Tailscale DNS names must be consistent across reboots.

### PowerDNS
- pdns 5.0.x renamed many commands: `create-zone` → `zone create`, `set-soa` → `rrset replace`, `generate-tsig-key` → `tsigkey generate`, `set-meta` → `metadata set`.
- PostgreSQL schema is imported automatically by `hetzner-postgres-schema` oneshot (waits for CNPG NodePort, imports `schema.pgsql.sql`).
- `pdns` user and database are created declaratively by CloudNativePG Cluster CR (`spec.managed`).

### k3s
- `--node-external-ip` can't be determined at build time (IP not known). Removed from extraFlags — k3s auto-detects.
- Split-IP firewall disabled for initial deploy (blocks SSH). Re-enable after floating IPs verified.
- All 3 nodes are independent single-node clusters (by design — managed separately via mTLS over tailnet).

### Script fixes
- `hcloud` CLI: `--output-format json` → `-o json` (newer hcloud versions).
- `hcloud floating-ip assign` takes the floating IP **ID** (numeric), not the IP address.
- Flake ref format for nixos-anywhere: `.#<hostname>` not `.#nixosConfigurations.<hostname>`.
