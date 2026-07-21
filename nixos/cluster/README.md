# Hetzner Enterprise HA Platform

3-node + Home Pi Kubernetes platform on Hetzner Cloud.
**Stack**: NixOS / k3s / Flannel / ArgoCD / deSEC DNS / SeaweedFS / B2 / Longhorn / MongoDB / CloudNativePG (PostgreSQL) / Temporal

**Modes**: LA (3 server nodes, ~$75/mo) or HA (6 nodes, ~$140/mo).

## Architecture




## Kubernetes Infrastructure Tailnet

**Headscale instance**: `headscale.9s.pics:6767` on home-pi (v0.28.0)
**Base domain**: `ts.9s.pics`
**Policy**: Deny-by-default ACL — only `tag:kube-control` nodes can reach each other on TCP/6443 + internet access for DERP relays
**Nodes**: home-pi + tagged cloud control-plane nodes (`hetzner-ashburn-k3s`, `hetzner-hillsboro-k3s`, `do-nyc-k3s`)
**Home API access**: home-pi advertises `192.168.5.10/32` (k3s VIP); cloud nodes reach `https://192.168.5.10:6443` via the route
**Enrollment**: One-use preauth key with `tag:kube-control`, created per deployment by `create_kubecontrol_preauth_key()` in `post_deploy.py`
**Teardown**: `headscale nodes delete -i <ID>` via `delete_headscale_node()` before cloud resource destruction

### Linkerd multicluster notes
- Service-mirror deployments MUST use `hostNetwork: true` to resolve MagicDNS names (`*.ts.9s.pics`)
- Kubeconfig secrets use MagicDNS FQDNs: `https://<hostname>.ts.9s.pics:6443`
- Home cluster API: `https://192.168.5.10:6443` (VIP, TLS SAN added to k3s certs)

### Availability dependency
home-pi is a single point of failure for MagicDNS resolution and the 192.168.5.10 route. During home-pi downtime (power loss, ISP outage):
- Existing peer-to-peer WireGuard tunnels between cloud nodes survive (kernel-level, no coordination needed)
- MagicDNS names (`*.ts.9s.pics`) stop resolving
- The home k8s VIP becomes unreachable from cloud nodes
- Cloud-to-home Linkerd multicluster will be offline during home-pi outages


### Per-Node IP Topology (Split-IP Firewall)

```
Primary IP (Hetzner DHCP) — locked down
  ├─ SSH (22)
  ├─ Tailscale (tailscale0)
  └─ All other ports DROP

Floating IP (Hetzner Cloud, movable between nodes)

  ├─ Game servers (3478, 9987, 30033, 8080)
  └─ All other ports DROP
```

**Note**: k3s API (6443) is no longer exposed publicly — API access is via Tailscale only.

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
│   ├── hetzner-k3s-server.nix      # k3s + ArgoCD + SSH + floating IP health
│   ├── hetzner-k3s-agent.nix       # Agent node (k3s agent only)
│   ├── hetzner-split-ip-firewall.nix   # Per-IP iptables (primary locked, floating open)
│   ├── headscale.nix               # Headscale coordination server
│   ├── tailscale.nix               # Tailscale client (parameterized login-server)
│   └── longhorn-host.nix           # Longhorn storage prerequisites
├── hosts/
│   ├── home-pi.nix                 # Home Pi (Headscale + deSEC DDNS)
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

# Provision (any order — DNS is handled by deSEC, not home-pi PowerDNS)
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
1. **ashburn**: Sets NS records (`ns1/ns2/ns3.9s.pics`) + glue A for `ns1` → floating IP.
2. **hillsboro**: Appends NS + glue A for `ns2` → floating IP.
3. **nuremberg**: Appends NS + glue A for `ns3` → floating IP.



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

PostgreSQL runs inside k3s via CloudNativePG (installed automatically by `argocd-bootstrap`). The CNPG Cluster CR creates a PostgreSQL instance with the `temporal` database and user.

```bash
# Verify PostgreSQL
ssh root@<IP> "pg_isready -h 127.0.0.1 -p 5432 -U temporal -d temporal"

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
hetzner-ashburn-k3s             hetzner-hillsboro-k3s, do-nyc-k3s
```

- Ashburn builds everything → `attic watch-store` pushes to Pi
- Hillsboro / NYC pull from cache → 90%+ cache hits → near-instant deploys

## Known Issues


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

## Kubernetes Pod Troubleshooting (2026-05-25)

This section documents pod startup failures encountered during the initial "all pods running" sweep,
with root causes and permanent fixes applied to the GitOps repo.

### crowdsec-firewall-bouncer: ImagePullBackOff

**Symptom**: `crowdsecurity/firewall-bouncer:latest` fails to pull across all 3 nodes.

**Root cause**: No official iptables firewall bouncer Docker image exists. CrowdSec publishes
per-service bouncer images (cloudflare, fastly, aws-waf, stormshield, etc.) but the iptables
firewall bouncer is a host binary, not a container. The image name `crowdsecurity/firewall-bouncer`
and `crowdsecurity/crowdsec-firewall-bouncer` both 404 on Docker Hub.

**Fix**: Removed the `crowdsec-firewall-bouncer` DaemonSet from GitOps entirely. The
`hetzner-split-ip-firewall.nix` already applies iptables filtering at the NixOS level, making
a CrowdSec bouncer redundant in this architecture.

**File**: `base/crowdsec/firewall-bouncer-config.yaml` (deleted)

### mongo: CreateContainerConfigError / ContainerCreating

**Symptom**: MongoDB pods stuck in `CreateContainerConfigError` (missing `password` key in
`mongo-creds` Secret) or `ContainerCreating` (missing `mongo-encryption-key` Secret).

**Root cause — Phase 1 (secrets)**:
The GitOps repo contained empty placeholder secrets (`mongo-creds` and `mongo-encryption-key`)
with `argocd.argoproj.io/compare-options: IgnoreExtraneous`. When ArgoCD synced, these
placeholders overwrote the real secrets injected by `k8s-secrets-bootstrap`. The `IgnoreExtraneous`
annotation prevents drift detection but does NOT prevent selfHeal overwrite — the empty secret
shell still takes precedence.

**Fix — Phase 1**: Deleted `base/mongodb/encryption-secret.yaml` from GitOps. Secrets injected
only at runtime via `k8s-secrets-bootstrap` must NOT exist in GitOps at all — even as empty shells.

**Root cause — Phase 2 (encryption flags)**:
After secrets were fixed, pods failed with `Error: unrecognised option '--enableEncryption'`.
`mongo:7` is Community Edition. `--enableEncryption` and `--encryptionKeyFile` are
Enterprise-only features. The deployment also mounted `mongo-encryption-key` as a volume,
which referenced a secret no longer created.

**Fix — Phase 2**: Removed `--enableEncryption` and `--encryptionKeyFile` from deployment args.
Removed `mongo-encryption-key` volume mount and volume definition.

**File**: `base/mongodb/deployment.yaml`

### mongo-backup: ContainerCreating → Error (rclone)

**Symptom**: MongoDB backup CronJob pods failing with `rclone: not found`, then after adding
`apt-get install rclone`, failing with `didn't find section in config file`.

**Root cause**: The `mongo:7` Docker image doesn't include `rclone`. Even if installed at runtime,
the backup requires a full rclone configuration with:
- B2 backend (application key ID + password)
- Crypt overlay (crypt password + salt)
- Properly named remotes matching the script (`b2-crypt:mongo-backups/`)

The only available agenix secret is `rclone-b2-password` (the application key). The key ID,
bucket name, and crypt credentials are not yet provisioned.

**Fix**: Removed `base/mongodb/backup-cronjob.yaml` from GitOps. To re-enable:
1. Create a custom Docker image with `mongo` + `rclone` pre-installed
2. Provision agenix secrets for: B2 application key ID + crypt password
3. Build a complete `rclone.conf` with `[b2]` backend + `[b2-crypt]` crypt overlay
4. Mount the config at `/etc/rclone/rclone.conf` (or set `RCLONE_CONFIG` env var)

### GitOps Placeholder Secrets — Anti-Pattern

**Pattern identified**: Empty secrets in GitOps with `IgnoreExtraneous` annotation are an
anti-pattern. Even without a `data:` field, ArgoCD selfHeal will reconcile these secrets
and overwrite runtime-injected values.

**Correct pattern**:
- Secrets that vary per cluster or are runtime-generated MUST NOT exist in GitOps
- All runtime secrets injected by `k8s-secrets-bootstrap` (oneshot Job or NixOS post-deploy)
- The `k8s-secrets-bootstrap` script owns creation and refresh of these secrets

**Previous instance of same bug**: `base/cloudnativepg/cluster.yaml` had placeholder
`temporal-postgres-password` secret (fixed prior to this sweep).

### MongoDB Community Edition Restrictions

- `--enableEncryption` — not available in Community Edition
- `--encryptionKeyFile` — not available in Community Edition
- Encryption-at-rest is Enterprise-only
- The `mongo:7` Docker image is Community Edition

### Longhorn Single-Node Volumes

- Each node needs `node.longhorn.io/create-default-disk=true` label
- Without this label, Longhorn refuses to schedule replicas on single-node clusters
- PVCs stay in Pending state indefinitely
- Applied by provision script or k8s-secrets-bootstrap post-deploy
