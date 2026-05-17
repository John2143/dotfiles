# Hetzner Enterprise HA Platform

3-node + Home Pi Kubernetes platform on Hetzner Cloud.

**Stack**: NixOS / k3s / Cilium / ArgoCD / PowerDNS (MariaDB Galera) / ExternalDNS (RFC2136) / SeaweedFS / B2 / Longhorn / MongoDB / CloudNativePG / Temporal

**Modes**: LA (3 server nodes, ~$75/mo) or HA (6 nodes, ~$140/mo).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Tailnet (ts.9s.pics) — Headscale on home-pi               │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ k3s-ashburn  │  │k3s-hillsboro │  │k3s-nuremberg │      │
│  │ control-plane│  │ control-plane│  │ control-plane│      │
│  │ pdns + mysql │  │ pdns + mysql │  │ pdns + mysql │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│          │                 │                 │              │
│          └─────────┬───────┴─────────────────┘              │
│                    │                                        │
│           ┌────────┴────────┐                               │
│           │    home-pi      │                               │
│           │ Headscale :6767 │                               │
│           │ Galera node #4  │                               │
│           │ pdns node #4    │                               │
│           └─────────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

All 3 server nodes are fully interchangeable (identical mkServer config). Each runs k3s + PowerDNS + MariaDB Galera. Nodes communicate over the tailnet (Headscale at home-pi) — all DNS, service discovery, and MySQL replication uses Tailscale IPs/DNS.

## Structure

```
nixos/hetzner/
├── flake.nix                     # mkServer/mkAgent/mkHome functions
├── modules/
│   ├── hetzner-disko.nix         # Disk layout (EF02 + EFI + ext4)
│   ├── hetzner-ssh.nix           # SSH + agenix identity
│   ├── hetzner-k3s-common.nix    # k3s + Cilium + ArgoCD + split-IP firewall
│   ├── hetzner-k3s-server.nix    # Adds PowerDNS + Galera on top
│   ├── hetzner-k3s-agent.nix     # Agent node (k3s agent only)
│   ├── hetzner-powerdns.nix      # PowerDNS authoritative server
│   ├── hetzner-powerdns-bootstrap.nix  # Zone creation (oneshot)
│   ├── hetzner-galera.nix        # MariaDB Galera cluster member
│   ├── headscale.nix             # Headscale coordination server
│   ├── tailscale.nix             # Tailscale client (parameterized login-server)
│   └── longhorn-host.nix         # Longhorn storage
├── hosts/
│   ├── home-pi.nix               # Home Pi (Headscale + Galera + pdns)
│   └── home-pi-hardware-configuration.nix
├── secrets/
│   ├── secrets.nix               # agenix public key mapping
│   └── hetzner/*.age             # Encrypted secrets
└── scripts/
    ├── provision.sh              # VM create + nixos-anywhere + post-deploy
    ├── toggle-ha.sh
    ├── toggle-la.sh
    └── demo.sh
```

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
- SSH key `john@arch` uploaded to Hetzner (`hcloud ssh-key create`)
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
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e hetzner/galera-password.age -i ~/.ssh/age
echo -n "$(head -c 24 /dev/urandom | base64)" | agenix -e hetzner/mariadb-root-password.age -i ~/.ssh/age
echo -n "$(head -c 32 /dev/urandom | base64)" | agenix -e hetzner/powerdns-tsig-key.age -i ~/.ssh/age
```

### Headscale preauth key (generate once on home-pi)

```bash
ssh home-pi "sudo headscale users create hetzner-nodes"
ssh home-pi "sudo headscale preauthkeys create --user 1 --reusable --expiration 87600h"
# Encrypt the output key on arch:
echo -n "hskey-auth-..." | agenix -e nixos/hetzner/secrets/hetzner/headscale-preauth-key.age -i ~/.ssh/age
```

## Galera bootstrap

After all 3 nodes are provisioned and on the tailnet, bootstrap the Galera cluster:

```bash
# 1. On home-pi (create the cluster)
ssh 192.168.0.154 "
  sudo systemctl stop mysql
  sudo rm -f /run/mysqld/mysqld.sock
  echo 1 | sudo tee /var/lib/mysql/grastate.dat
  sudo systemctl start mysql
"
# Verify: sudo mysql -e "SHOW STATUS LIKE 'wsrep%'" | grep cluster_size
# Should show: cluster_size=1, cluster_status=Primary

# 2. On each Hetzner node (join the cluster)
ssh root@<IP> "sudo systemctl restart mysql"
# Cluster size grows: 1 → 2 → 3 → 4
```

MariaDB 11.x requires `wsrep_on=1` and `binlog_format=ROW` (set in `hetzner-galera.nix`).

## Provisioning lessons (from attempts #1 and #2)

### NixOS boot on Hetzner Cloud
- **Disko layout**: Must include EF02 BIOS boot partition (1M) + EFI partition + ext4 root. Without EF02, GRUB can't install on GPT.
- **GRUB device**: `/dev/sda` (not `nodev`). Sets up both i386-pc and x86_64-efi boot.
- **Kernel modules**: Import `qemu-guest.nix` profile; add `virtio_pci`, `virtio_scsi`, `sd_mod`, `ext4` to `boot.initrd.availableKernelModules`.
- **CPX32 / EU datacenters**: cpx32 VMs in European DCs (nbg1, fsn1) consistently fail to boot NixOS. All nodes currently use cpx31 in ashburn. This may be a Hypervisor/KVM version difference.

### agenix identity
- Hetzner VMs have no age identity at first boot. The host SSH key (`/etc/ssh/ssh_host_ed25519_key`) doesn't match agenix encryption keys.
- **Fix**: The provision script copies `~/.ssh/age` (arch's age key) to `/etc/ssh/age-identity`. This pre-seeds the identity so the post-deploy `nixos-rebuild` can decrypt all secrets.

### tailscale connectivity
- `tailscale up` needs `--reset` flag to override existing config (left from initial deploy).
- Must restart `tailscaled` before `tailscale up` on fresh deploys.
- Never `tailscale logout; tailscale up` — creates duplicate identities that break Galera DNS. Use `systemctl restart tailscaled-autoconnect` instead.
- Tailscale DNS names must match Galera cluster address. The home-pi DNS is `home-pi-clnydbkx.ts.9s.pics` (not `home-pi.ts.9s.pics`).

### PowerDNS
- pdns 5.0.x renamed many commands: `create-zone` → `zone create`, `set-soa` → `rrset replace`, `generate-tsig-key` → `tsigkey generate`, `set-meta` → `metadata set`.
- MySQL schema must be imported before pdns can start: `mysql -u pdns -ppdns pdns < /nix/store/*pdns*/share/doc/pdns/schema.mysql.sql`.
- pdns user must exist in MySQL with password matching `gmysql-password` in config.

### k3s
- `--node-external-ip` can't be determined at build time (IP not known). Removed from extraFlags — k3s auto-detects.
- Split-IP firewall disabled for initial deploy (blocks SSH). Re-enable after floating IPs verified.
- All 3 nodes are independent single-node clusters (by design — managed separately via mTLS over tailnet).

### Script fixes
- `hcloud` CLI: `--output-format json` → `-o json` (newer hcloud versions).
- `hcloud floating-ip assign` takes the floating IP **ID** (numeric), not the IP address.
- Flake ref format for nixos-anywhere: `.#<hostname>` not `.#nixosConfigurations.<hostname>`.
