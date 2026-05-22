---
description: Inject network context into any session — device inventory, live ARP/routes/DHCP, server-to-flake mapping, subnet layout
argument-hint: (none — invoked as skill://network-engineer)
allowed-tools: Bash(mikrotik-connect *), Read, Search
tool-hints: |
  This skill injects context. It does NOT modify anything.
  All RouterOS commands are read-only (print, export, monitor, get).
  NEVER run add/remove/set/enable/disable/reboot/shutdown without explicit user approval.
  Prefer live queries over stale static data when confirming current state.
---

When this skill is loaded, immediately inject the following context into the conversation.
You are now operating on John's home network. Use this knowledge to answer questions,
diagnose issues, and navigate the infrastructure.


## First-Run Bootstrap

When this skill is first loaded in a session, run these commands to snapshot the network.
This takes ~5 seconds and grounds everything that follows in live state.

**Router snapshot:**
```
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
mikrotik-connect r '/ip arp print terse where status=reachable'
mikrotik-connect r '/ip arp print terse where status=permanent'
mikrotik-connect r '/ip route print terse'
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
```

**Switch port status:**
```
mikrotik-connect u '/interface print terse where running'
mikrotik-connect d '/interface print terse where running'
```

After running, summarize: how many hosts are online (bound DHCP + reachable ARP), what services are exposed (dst-nat), and which switch ports are live. Then proceed with the user's actual request.
## How to Connect to MikroTik Devices

```
mikrotik-connect <alias> <RouterOS command...>
```

| Device     | Alias              | IP            |
|------------|--------------------|---------------|
| Router     | `r`, `router`      | 192.168.1.1   |
| Upstairs   | `u`, `upstairs`    | 192.168.5.3   |
| Downstairs | `d`, `downstairs`  | 192.168.5.2   |

All use `admin@` with ed25519 key auth (auto-materialized from agenix to `/run/user/$UID/mikrotik-key`).
The `mikrotik-connect` wrapper works from both bash and fish.

RouterOS syntax: `/path command arg=value`. Common patterns:
- Display: `/ip route print`, `/ip address print`, `/interface print`
- Filter: `/ip firewall filter print where chain=input`
- Export: `/export` (whole config), `/ip firewall export` (section)
- Terse (scriptable): `/ip route print terse`
- Count: `/ip route print count-only`

## WAN Topology (Double NAT)

```
Internet
  └─ Verizon router (192.168.0.1)
       ├─ Port 80/443 → DMZ to 192.168.0.2 (MikroTik)
       └─ DMZ host: 192.168.0.2
            └─ MikroTik router (WAN: 192.168.0.2, LAN: 192.168.1.1 + 192.168.5.1)
                 ├─ dst-nat rules → internal services
                 └─ LAN subnets (1.0/24, 5.0/24)
```

Inbound: Verizon DMZs everything to MikroTik. MikroTik dst-nat rules route specific ports to internal hosts.
Domains `john2143.com` and `net.2143.me` resolve to the home public IP.

## Port Forwarding (dst-nat)

**ALWAYS check live dst-nat first** — ports change as services move:
```
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
```

Baseline (captured 2026-05-22, corrected):

| WAN Port(s) | Proto | MikroTik → | Final Target | K8s NodePort | Service |
|------------|-------|-----------|-------------|-------------|---------|
| 80, 443 | TCP | closet:80,443 | traefik LB | 31316, 30908 | HTTP/HTTPS ingress |
| 9987 | UDP | closet:30087 | ts-voice:30087 | 30087 | Teamspeak voice |
| 30033 | TCP | closet:30034 | ts-files:30034 | 30034 | Teamspeak file transfer |
| 5432, 5999 | TCP | closet:5432 | CNPG Postgres | (ClusterIP) | PostgreSQL |
| 25565 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft (k8s) |
| 25555 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft alternate |
| 11753 | TCP | closet:31753 | openrct2-game:31753 | 31753 | OpenRCT2 |
| 6767 | Both | hetzner:6767 | home-pi Headscale | (direct) | Headscale control |
| 30478 | UDP | closet:30478 | headscale-stun:30478 | 30478 | Headscale STUN |
| — | — | 192.168.0.0/16 → public IP | Hairpin NAT | — | LAN→WAN→LAN loopback |
## Subnet Layout

```
192.168.0.0/24  — 2GWAN (upstream ISP via Verizon, DHCP from 192.168.0.1)
192.168.1.0/24  — bridge (main LAN, router at .1)
192.168.5.0/24  — bridge (switch LAN, router at .1)
192.168.88.0/24 — bridge (legacy factory-default, router at .254, unused)
```

Router bridges all subnets. Inter-subnet routing is automatic (no NAT between 1.0/24 and 5.0/24).

## Device Inventory — NixOS Hosts

All hosts run NixOS (except mac which is nix-darwin). Managed from `~/dotfiles` via `nh os switch .`.

### Local (Home Network)

| Hostname | IP | Role | Hardware |
|----------|----|------|----------|
| **office** | 192.168.5.209 (DHCP) | Primary admin workstation, k3s agent, GPU compute (vLLM) | i9-14900K, 64GB, RX 7900 XT, RTL8125 2.5GbE |
| **arch** | 192.168.5.226 (DHCP) | GenAI workstation, k3s, GPU compute (ollama/vllm) | i9-9900K, 31GB, GTX 1080 Ti |
| **closet** | 192.168.5.35 (static) | k3s server, Longhorn storage | Ryzen 5 1600, 7.7GB, 4TB USB SSD |
| **nas** | 192.168.5.175-176 (DHCP, dual NIC) | ZFS file server, atticd cache, k3s + Longhorn | i7-3770K, 15GB, 4×8TB HDD ZFS RAIDZ1, 10GbE SFP+ |
| **secu** | 192.168.5.140 (DHCP) | Security camera NVR (FDE) | HP EliteDesk 800 G3, i5-6500T, 7.6GB |
| **pite** | 192.168.5.213 (DHCP) | k3s agent, canary (honeytoken bait) | Raspberry Pi 4B, 1.8GB, 238GB SD |
| **vpin** | 192.168.5.252 (DHCP) | Mullvad exit node | Raspberry Pi (3?), 3.7GB, 59.5GB SD |
| **aman** | DHCP (Tailscale) | Mullvad exit node, Avahi reflector | Raspberry Pi 4B, 3.7GB, 238GB SD |
| **home-pi** | DHCP (Tailscale) | Headscale server, PowerDNS | Raspberry Pi (aarch64) |

### Hetzner Cloud (Tailscale only, `ts.9s.pics`)

| Hostname | Region | Role |
|----------|--------|------|
| **k3s-ashburn** | Ashburn, VA | k3s server + PostgreSQL (CNPG) + PowerDNS |
| **k3s-hillsboro** | Hillsboro, OR | k3s server + PostgreSQL + PowerDNS |
| **k3s-nuremberg** | Nuremberg, DE | k3s server + PostgreSQL + PowerDNS |
| **k3s-*-agent** | (same regions) | k3s agents (HA toggle, provisioned on demand) |

### Other

| Hostname | Role | Notes |
|----------|------|-------|
| **mac** | Work laptop (nix-darwin) | LLM API keys only, no personal secrets |
| **security** | Unknown | Age key exists but unreachable — may be retired |
| **term** | Unknown | No age key, shares security's config — likely never deployed |

### Key Services

| Service | Host | Port/URL |
|---------|------|----------|
| k3s API | closet | `192.168.5.35:6443` |
| Attic Nix cache | nas | `http://nas:8280` |
| Headscale | home-pi | `headscale.9s.pics:6767` |
| Home Assistant | (TBD) | `home.ts.2143.me` |
| ArgoCD | k3s-ashburn | `argocd.ts.2143.me` |
| RustFS (S3) | (TBD) | `files.john2143.com` |


## Cameras and UniFi

| Device | IP | MAC | Notes |
|--------|-----|-----|-------|
| UniFi NVR | 192.168.5.163 (DHCP) | EC:71:DB:8B:92:93 | UniFi Protect recorder |
| Front (doorbell?) | 192.168.5.174 (DHCP) | EC:71:DB:3E:2F:21 | hostname=Front |
| Camera? | 192.168.5.197 (static) | EC:71:DB:8B:92:93 | Same MAC as NVR — second NIC? |
| Camera? | 192.168.5.154 (static) | EC:71:DB:8B:92:93 | Same MAC as NVR |
| Camera? | 192.168.5.152 (static) | EC:71:DB:0B:3C:76 | Ubiquiti MAC prefix |
| Camera? | 192.168.5.150 (static) | 90:41:B2:D6:74:DB | |
| Camera? | 192.168.5.149 (static) | 1C:0B:8B:50:FF:7E | |
| Camera? | 192.168.5.151 (static) | 94:B3:F7:18:52:CC | |
| Camera? | 192.168.5.219 (static) | C8:FF:77:57:E0:3D | |

All cameras wired through the upstairs/downstairs switches. UniFi NVR records feeds.
`secu` (192.168.5.140) has "Security camera NVR" in its NixOS role but no recognizable NVR package in its config — possibly Frigate via container, or Home Assistant handles cameras directly. Verify before assuming.
## Live Network State

When you need to confirm what's actually on the network RIGHT NOW, run these read-only queries:

### Active DHCP Leases (who's alive)
```
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
```

### ARP Table (L2 neighbors)
```
mikrotik-connect r '/ip arp print terse where status=reachable'
mikrotik-connect r '/ip arp print terse where status=permanent'
```

### Routes
```
mikrotik-connect r '/ip route print terse'
```

### Uplink Status
```
mikrotik-connect r '/interface print terse where running'
mikrotik-connect r '/ip address print terse'
```

### Firewall Rules
```
mikrotik-connect r '/ip firewall filter print'
mikrotik-connect r '/ip firewall nat print'
```

### Switch Port Status (upstairs/downstairs)
```
mikrotik-connect u '/interface print terse where running'
mikrotik-connect d '/interface print terse where running'
```

### Full Config Dump
```
mikrotik-connect r /export
```

## Intelligent Triage

When answering a question or diagnosing a problem:

1. **Static knowledge is sufficient** if the question is "what is X's IP?" or "where is Y running?" — use the tables above.
2. **Run a live query** if the question is "is X online right now?" or "what's the current ARP/route state?" — use DHCP leases (bound=alive) or ARP (reachable=alive) from the router.
3. **Don't re-fetch** data you already have in the current session. One ARP scan per conversation is enough.
4. **Correlate MAC addresses** between ARP and DHCP to identify devices without hostnames.
5. **Cross-reference with NixOS configs** when you need to understand what a host *should* be running vs. what it *is* running.

## Safety

- All RouterOS commands through this skill are **read-only** (`print`, `export` without `file=`, `monitor`, `get`).
- **NEVER** run add/remove/set/enable/disable/move/reset/reboot/shutdown without explicit user approval.
- **NEVER** run `nixos-rebuild switch` or `home-manager switch` without explicit user approval.
- When in doubt whether a command is read-only, show it to the user and ask.
- `export file=...` writes to device flash — it IS mutating.
