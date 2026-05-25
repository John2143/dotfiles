# Hetzner Enterprise HA Platform

3-node + Home Pi Kubernetes platform on Hetzner Cloud.

**Stack**: NixOS / k3s / Flannel / ArgoCD / PowerDNS / ExternalDNS (RFC2136) / SeaweedFS / B2 / Longhorn / MongoDB / CloudNativePG (PostgreSQL) / Temporal

**Modes**: LA (3 server nodes, ~$75/mo) or HA (6 nodes, ~$140/mo).

## Architecture

### DNS Flow (deSEC → PowerDNS via Floating IPs)

```
Internet Resolver
  │
  ├─ deSEC (authoritative for NS): "9s.pics NS ns1.9s.pics, ns2.9s.pics, ns3.9s.pics"
  │         glue A: ns1 → <floating-ashburn>, ns2 → <floating-hillsboro>, ns3 → <floating-nuremberg>
  │
  ├─ Queries floating IP:53 → PowerDNS on k3s-*
  │   PowerDNS authoritative for 9s.pics, updated by ExternalDNS via RFC2136
  │
  └─ Service DNS (ts.9s.pics, *.9s.pics) resolves to floating IPs
```

Why NS delegation (not deSEC ExternalDNS webhook):
- Existing RFC2136 → PowerDNS is working and fast (no API rate limits)
- One-time NS+glue setup on deSEC; all dynamic records handled by PowerDNS locally
- deSEC API rate limits would impact frequent Ingress DNS updates

### Node Topology

```
┌─────────────────────────────────────────────────────────────┐
│  Tailnet (ts.9s.pics) — Headscale on home-pi               │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ k3s-ashburn  │  │k3s-hillsboro │  │k3s-nuremberg │      │
│  │ control-plane│  │ control-plane│  │ control-plane│      │
│  │ pdns (ns1)   │  │ pdns (ns2)   │  │ pdns (ns3)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│          │                 │                 │              │
│          └─────────┬───────┴─────────────────┘              │
│                    │                                        │
│           ┌────────┴────────┐                               │
│           │    home-pi      │                               │
│           │ Headscale :6767 │                               │
│           │ pdns (tiebreak) │                               │
│           │ deSEC DDNS timer│                               │
│           └─────────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

All 3 server nodes are fully interchangeable (identical mkServer config). Each runs k3s + PowerDNS with independent CNPG PostgreSQL. Nodes communicate over the tailnet (Headscale at home-pi).

### Per-Node IP Topology (Split-IP Firewall)

```
Primary IP (Hetzner DHCP) — locked down
  ├─ SSH (22)
  ├─ Tailscale (tailscale0)
  └─ All other ports DROP

Floating IP (Hetzner Cloud, movable between nodes)
  ├─ DNS (53 tcp+udp)          ← deSEC NS glue points here
  ├─ HTTP/HTTPS (80, 443)
  ├─ k3s API (6443)
  ├─ CNPG NodePort (30432)
  ├─ Game servers (3478, 9987, 30033, 8080)
  └─ All other ports DROP
```

Both IPs detected at runtime:
- Primary = IP with default route (`ip route get 8.8.8.8`)
- Floating = other IP on enp1s0

No hardcoded IPs in flake.nix — firewall adapts to whatever Hetzner assigns.

## Structure

```
nixos/hetzner/
├── flake.nix                       # mkServer/mkAgent/mkHome functions
├── modules/
│   ├── hetzner-disko.nix           # Disk layout (EF02 + EFI + ext4)
│   ├── hetzner-ssh.nix             # SSH + agenix identity
│   ├── hetzner-k3s-common.nix      # k3s + Flannel + ArgoCD + CNPG + cert-manager + firewall
│   ├── hetzner-k3s-server.nix      # Adds PowerDNS + PostgreSQL schema import
│   ├── hetzner-k3s-agent.nix       # Agent node (k3s agent only)
│   ├── hetzner-powerdns.nix        # PowerDNS authoritative server (gpgsql backend)
│   ├── hetzner-powerdns-bootstrap.nix  # Zone creation + TSIG key + ns A records (oneshots)
│   ├── hetzner-postgres-schema.nix # Import pdns schema into CNPG PostgreSQL
│   ├── hetzner-split-ip-firewall.nix   # Per-IP iptables (primary locked, floating open)
│   ├── headscale.nix               # Headscale coordination server
│   ├── tailscale.nix               # Tailscale client (parameterized login-server)
│   └── longhorn-host.nix           # Longhorn storage prerequisites
├── hosts/
│   ├── home-pi.nix                 # Home Pi (Headscale + pdns + deSEC DDNS)
│   └── home-pi-hardware-configuration.nix
├── secrets/
│   ├── secrets.nix                 # agenix public key mapping
│   └── hetzner/*.age               # Encrypted secrets
└── scripts/
    ├── provision.sh                # VM create → nixos-anywhere → deSEC DNS → tailscale
    ├── desec-dns.sh                # deSEC DNS record management
    ├── toggle-ha.sh                # Switch LA → HA (provision agents)
    ├── toggle-la.sh                # Switch HA → LA (destroy agents)
    └── demo.sh                     # Demo commands
```

## Quick Start

```bash
# Decrypt Hetzner token
export HCLOUD_TOKEN=$(cd nixos/hetzner/secrets && agenix -d hetzner/hcloud-token.age -i ~/.ssh/age)

# Provision in order (ashburn first — home-pi DNS depends on it)
cd nixos/hetzner/scripts
./provision.sh ashburn server    # ~10-15 min
./provision.sh hillsboro server  # ~5 min (cache hits from ashburn)
./provision.sh nuremberg server  # ~5 min (cache hits)

# After all 3 nodes are up, update public DNS
./desec-dns.sh update-all-nodes
```

The provision script automates: VM creation, floating IP allocation, deSEC NS+glue DNS setup, nixos-anywhere deploy, agenix decrypt, headscale cleanup, tailscale connect, service verification.

## Prerequisites

- Hetzner Cloud account + API token (in `secrets/hetzner/hcloud-token.age`)
- `hcloud` CLI, `jq`, `nixos-anywhere` available via flake
- SSH key `john@office` uploaded to Hetzner (`hcloud ssh-key create`)
- Home-pi running Headscale (see `hosts/home-pi.nix`)
- Port forward `6767 → home-pi:6767` on home router
- DNS `headscale.9s.pics` → home public IP (auto-updated by deSEC DDNS on home-pi)
- deSEC account with `9s.pics` domain delegated

### Generating secrets

All secrets are encrypted with [agenix](https://github.com/ryantm/agenix). From `nixos/hetzner/secrets/`:

```bash
# Hetzner API token
agenix -e hetzner/hcloud-token.age -i ~/.ssh/age

# deSEC API token (for DNS management)
echo -n "YOUR_DESEC_TOKEN" | agenix -e hetzner/desec-token.age -i ~/.ssh/age

# Generated secrets
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e hetzner/k3s-token.age -i ~/.ssh/age
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e hetzner/postgres-pdns-password.age -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e hetzner/powerdns-tsig-key.age -i ~/.ssh/age
```

### Headscale preauth key (generate once on home-pi)

```bash
ssh 192.168.0.154 "sudo headscale users create hetzner-nodes"
ssh 192.168.0.154 "sudo headscale preauthkeys create --user 1 --reusable --expiration 87600h"
# Encrypt the output key:
echo -n "hskey-auth-..." | agenix -e nixos/hetzner/secrets/hetzner/headscale-preauth-key.age -i ~/.ssh/age
```

## deSEC DNS Management

The `desec-dns.sh` script manages DNS records for `9s.pics` via the deSEC API. The provision script calls it automatically during deployment.

```bash
cd nixos/hetzner/scripts

# Bootstrap NS delegation + glue records (one per node, called by provision.sh)
./desec-dns.sh bootstrap-dns ashburn 5.161.17.173

# List all records
./desec-dns.sh list

# Manual record management
./desec-dns.sh set-a headscale 1.2.3.4
./desec-dns.sh update-headscale              # Auto-detect public IP
./desec-dns.sh update-all-nodes              # Update all node A records from config file
```

### DNS Bootstrap Flow

During provisioning, each node:
1. **ashburn**: Sets NS records (`ns1/ns2/ns3.9s.pics`) + glue A for `ns1` → floating IP. Truncates the floating IPs config file.
2. **hillsboro**: Appends NS + glue A for `ns2` → floating IP. Appends to config.
3. **nuremberg**: Appends NS + glue A for `ns3` → floating IP. Appends to config.

After all 3 provisioned, `update-all-nodes` reads `desec-dns-floating-ips.conf` and sets node A records (`k3s-ashburn.9s.pics` etc.) pointing to floating IPs.

## Split-IP Firewall

Active by default on all server nodes. Rules applied by `split-ip-firewall.service` (oneshot, runs after network-online.target).

**Primary IP chain (PRIMARY_IN)**:
- ACCEPT established/related, loopback, tailscale0
- ACCEPT SSH (22)
- DROP everything else

**Floating IP chain (FLOATING_IN)**:
- ACCEPT established/related, loopback, tailscale0
- ACCEPT SSH (22), DNS (53 tcp+udp), HTTP/HTTPS (80, 443), k3s API (6443), CNPG (30432)
- ACCEPT game servers: STUN/DERP (3478/udp), TeamSpeak voice (9987/udp), TeamSpeak file (30033/tcp), DERP (8080/tcp)
- SYN rate limiting on HTTP/HTTPS (100/s burst 200)
- DROP everything else

Single-IP fallback: if only one IP detected (e.g., before floating IP attaches), only PRIMARY_IN chain is applied.

## CloudNativePG setup

PostgreSQL runs inside k3s via CloudNativePG (installed automatically by `argocd-bootstrap`). On first boot, the CNPG Cluster CR creates a PostgreSQL instance with `pdns` database and user via `bootstrap.initdb`.

**Important**: CNPG 1.25 generates a random password. The `hetzner-postgres-schema` oneshot waits for PostgreSQL then imports the schema and resets the pdns password to match the agenix secret.

```bash
# Verify PostgreSQL
ssh root@<IP> "pg_isready -h 127.0.0.1 -p 30432 -U pdns -d pdns"
# Verify PowerDNS
ssh root@<IP> "systemctl status pdns"
```

## Nix Binary Cache (Attic on home-pi)

Attic binary cache server runs on home-pi (`atticd` on port 8280/tailscale0). All Hetzner nodes
push built paths and pull from cache for near-instant deploys after the first node is provisioned.

- **Server**: `atticd` systemd service on home-pi, listening on `100.64.0.2:8280` (Tailscale only)
- **Storage**: `/var/lib/attic` on home-pi SD card (188GB free)
- **Clients**: All 3 k3s nodes run `attic watch-store` + configure nix substituter
- **Cache name**: `2143nix`
- **Module**: `nixos/modules/attic-server.nix` (server), inline in `hetzner-k3s-common.nix` (client)

Flow:
```
home-pi (atticd :8280)
  ↑ push (watch-store)        ↑ pull (substituter)
k3s-ashburn (first build)    k3s-hillsboro, k3s-nuremberg
```

- Ashburn builds everything → `attic watch-store` pushes to Pi
- Hillsboro/Nuremberg pull from cache → 90%+ cache hits → near-instant deploys
- All nodes reach the Pi over Tailscale at `100.64.0.2:8280`

## Known Issues

### CNPG 1.25 — `bootstrap.initdb` not `spec.managed`
`spec.managed` was introduced in CNPG 1.26+. The pdns user password must be reset after cluster creation via `hetzner-postgres-schema`.

### `pdnsutil` needs `--config-dir=/run/pdns`
Runtime config with decrypted secrets lives at `/run/pdns/pdns.conf`. Always use `pdnsutil --config-dir=/run/pdns`.

### `postgres-pdns-password` must be owned by `pdns`
If pdns fails to start: `chown pdns:pdns /run/agenix/hetzner/postgres-pdns-password`

### ExternalDNS TSIG secret key naming
The Helm chart (v1.21.1+) expects the RFC2136 credentials secret to have key `tsig-key`, not `rfc2136TsigSecret`. The `k8s-secrets-bootstrap` oneshot uses `tsig-key`. All ArgoCD manifests in 2143-59s reference `tsig-key`.

### ExternalDNS Helm + TSIG args
ExternalDNS Helm chart v1.21.1+ does not pass `--rfc2136-*` args to the deployment container. The `argocd-bootstrap` script patches the deployment post-install with the correct args. Do not remove the `kubectl patch` block after the `helm upgrade` for external-dns.

### ArgoCD ConfigMap (argocd-cm)
The ArgoCD ConfigMap with health checks is applied inline in the bootstrap script (not from a repo file). The health check Lua script uses a permissive default ("Healthy") to avoid stalling wave progression on resources that can't report health (e.g., cert-manager Certificates pending DNS01). Only "Degraded" blocks sync.

### Traefik chart version pin
Traefik chart v35+ has template errors with `hostPort` and `hostNetwork`. The bootstrap pins `--version 34.0.0` and omits hostPort/hostNetwork.

## Provisioning Lessons (from attempts #1-3)

### NixOS boot on Hetzner Cloud
- **Disko layout**: Must include EF02 BIOS boot partition (1M) + EFI partition + ext4 root. Without EF02, GRUB can't install on GPT.
- **GRUB device**: `/dev/sda` (not `nodev`). Sets up both i386-pc and x86_64-efi boot.
- **Kernel modules**: Import `qemu-guest.nix` profile; add `virtio_pci`, `virtio_scsi`, `sd_mod`, `ext4` to `boot.initrd.availableKernelModules`.
- **CPX32 / EU datacenters**: cpx32 VMs in European DCs (nbg1, fsn1) consistently fail to boot NixOS. Nuremberg runs in ashburn location for now.

### agenix identity
- Hetzner VMs have no age identity at first boot. Provision script copies `~/.ssh/age` to `/etc/ssh/age-identity` so post-deploy `nixos-rebuild` can decrypt secrets.

### tailscale connectivity
- `tailscale up` needs `--reset` flag to override existing config.
- Must restart `tailscaled` before `tailscale up` on fresh deploys.
- Never `tailscale logout; tailscale up` — creates duplicate identities. Use `systemctl restart tailscaled-autoconnect`.
- Tailscale DNS names must be consistent across reboots.

### PowerDNS
- pdns 5.0.x renamed many commands: `create-zone` → `zone create`, `set-soa` → `rrset replace`, `generate-tsig-key` → `tsigkey generate`, `set-meta` → `metadata set`.
- PostgreSQL schema imported automatically by `hetzner-postgres-schema` oneshot.
- `pdns` user and database created declaratively by CloudNativePG Cluster CR.

### k3s
- `--node-external-ip` can't be determined at build time. Removed from extraFlags — k3s auto-detects.
- All 3 nodes are independent single-node clusters by design.
- Flannel CNI (not Cilium — broken on NixOS kernel 6.18).

### Split-IP Firewall
- Both IPs detected at runtime — no hardcoded IPs in flake.nix.
- Firewall is a oneshot systemd service, not dynamic. If floating IP changes, restart the service or reboot.
- Graceful fallback: if only one IP detected, only PRIMARY_IN chain applies (SSH+Tailscale only).

### deSEC DNS
- NS records set via `PUT` (full replacement) — each bootstrap call overwrites the NS set, so all 3 must be set.
- Glue A records for ns1/ns2/ns3 are set individually by each node's `bootstrap-dns` call.
- Home-pi runs a DDNS timer updating `headscale.9s.pics` every 5 minutes.

### Script fixes
- `hcloud` CLI: `--output-format json` → `-o json` (newer hcloud versions).
- `hcloud floating-ip assign` takes the floating IP **ID** (numeric), not the IP address.
- Flake ref format for nixos-anywhere: `.#<hostname>` not `.#nixosConfigurations.<hostname>`.
- `nixos-anywhere --build-on-remote` is deprecated: use `--build-on remote` instead.
