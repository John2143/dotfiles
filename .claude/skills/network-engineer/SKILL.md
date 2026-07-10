---
description: Inject network context into any session — device inventory, live ARP/routes/DHCP, server-to-flake mapping, subnet layout
argument-hint: (none — invoked as skill://network-engineer)
allowed-tools: Bash(mikrotik-connect *), Bash(kubectl *), Bash(ssh closet *), Read, Search, Edit
tool-hints: |
  This skill injects context. It does NOT modify anything.
  All RouterOS commands are read-only (print, export, monitor, get).
  NEVER run add/remove/set/enable/disable/reboot/shutdown without explicit user approval.
  Prefer live queries over stale static data when confirming current state.
  kubectl is available via `ssh closet 'kubectl ...'` for local cluster queries.
  This skill is allowed to update its own SKILL.md file when the user asks for documentation changes.
---

## Usage

**Invocation:** `/skill:network-engineer`

This skill takes no arguments. It injects network context (device inventory, subnets, port forwarding, wireless state) into the current session. On first invocation in a session, it captures live snapshots from the router, switches, and UniFi controller.

**Examples:**
- `/skill:network-engineer` — Inject network context and capture live state

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
mikrotik-connect r '/routing bgp session print'
mikrotik-connect r '/routing bgp connection print'
```

**IPv6 state:**
```
mikrotik-connect r '/ipv6 address print terse'
mikrotik-connect r '/ipv6 dhcp-client print'
mikrotik-connect r '/ipv6 route print terse'
```

**Switch port status:**
```
mikrotik-connect c '/interface print terse where running'
mikrotik-connect u '/interface print terse where running'
mikrotik-connect o '/interface print terse where running'
mikrotik-connect uc '/interface print terse where running'
```

**Hardware identity check (confirm model/serial matches inventory):**
```
mikrotik-connect r '/system routerboard print'
mikrotik-connect c '/system routerboard print'
mikrotik-connect u '/system routerboard print'
mikrotik-connect o '/system routerboard print'
mikrotik-connect uc '/system routerboard print'
```

**UniFi wireless snapshot (credentials from agenix):**
```
python3 << 'PYEOF'
import urllib.request, ssl, json, http.cookiejar
with open('/run/agenix/unifi-credentials') as f:
    creds = {}
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            creds[k] = v.strip('"')
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
base = 'https://192.168.5.10:30443'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))
data = json.dumps({'username': creds['UNIFI_USERNAME'], 'password': creds['UNIFI_PASSWORD'], 'remember': True}).encode()
opener.open(urllib.request.Request(f'{base}/api/login', data=data, headers={'Content-Type': 'application/json'}))
resp = opener.open(urllib.request.Request(f'{base}/api/s/default/stat/device'))
aps = [d for d in json.loads(resp.read())['data'] if d.get('type') == 'uap']
print(f"APs: {len(aps)}")
for ap in aps:
    print(f"  {ap.get('name','?'):25s} {ap.get('model','?'):10s} state={ap.get('state')} clients={ap.get('num_sta',0)} uptime={ap.get('uptime',0)}s ip={ap.get('ip','?')}")
resp = opener.open(urllib.request.Request(f'{base}/api/s/default/stat/sta'))
clients = json.loads(resp.read())['data']
print(f"Wireless clients: {len(clients)}")
for c in sorted(clients, key=lambda c: c.get('signal', -100)):
    h = c.get('hostname') or c.get('name') or '?'
    print(f"  {h:30s} {c.get('ip','?'):15s} {str(c.get('signal','?')):4s} dBm  {c.get('radio_proto','?'):6s} ch{c.get('channel','?')}  {c.get('essid','?')}")
PYEOF
```

**Tailscale snapshot (tailnet state):**
```bash
sudo tailscale status
```

After running, summarize: how many hosts are online (bound DHCP + reachable ARP), what services are exposed (dst-nat), which switch ports are live, the UniFi wireless snapshot (AP status + client count + any weak-signal clients below -80 dBm), and the Tailscale tailnet (node count, online/offline status). Then proceed with the user's actual request.

## How to Connect to MikroTik Devices

```
mikrotik-connect <alias> <RouterOS command...>
```

| Device     | Alias              | IP            |
|------------|--------------------|---------------|
| Router     | `r`, `router`      | 192.168.1.1   |
| Core       | `c`, `core`        | 192.168.5.4   |
| Upstairs   | `u`, `upstairs`    | 192.168.5.3   |
| Office     | `o`, `office`      | 192.168.5.2   |
| Upstairs-Core | `uc`, `upstairs-core` | 192.168.5.5   |

All use `admin@` with ed25519 key auth (auto-materialized from agenix to `/run/user/$UID/mikrotik-key`).
The `mikrotik-connect` wrapper works from both bash and fish.

RouterOS syntax: `/path command arg=value`. Common patterns:
- Display: `/ip route print`, `/ip address print`, `/interface print`
- Filter: `/ip firewall filter print where chain=input`
- Export: `/export` (whole config), `/ip firewall export` (section)
- Terse (scriptable): `/ip route print terse`
- Count: `/ip route print count-only`

## Verifying Device Identity

When connecting to any MikroTik device, run `/system routerboard print` on first connect and cross-check model + serial against the known inventory. This prevents operating on the wrong box.

| Device | Alias | Model | S/N | Firmware |
|--------|-------|-------|-----|----------|
| Router | r | RB5009UPr+S+ | HKG0AWJZPCK | 7.19.6 |
| Core | c | CRS305-1G-4S+ r2 | HMC0B8ZZ7F2 | 7.20.8 |
| Upstairs | u | CRS310-8G+2S+ | HKG0AVERD3V | 7.19.6 |
| Office | o | CRS310-8G+2S+ | HKG0AJ14YM5 | 7.19.6 |
| Upstairs-Core | uc | CRS305-1G-4S+ r2 | HMB0BED9WV8 | 7.20.8 |

**Note:** RouterOS version (from `/system resource print`) is NOT the same as Routerboard model (from `/system routerboard print`). Always check both to confirm identity.

## WAN Topology (Double NAT)

```
Internet
  └─ Verizon router (192.168.0.1)
       ├─ DMZ → 192.168.0.2 (MikroTik, static WAN)
       ├─ Port 6767 → 192.168.0.154 (home-pi Headscale)
       └─ DHCP: 192.168.0.152 (MikroTik secondary WAN), .154 (home-pi)
            │
            ├─ home-pi (192.168.0.154) — on WAN subnet, not behind MikroTik
            │
            └─ MikroTik router (WAN: 192.168.0.2 + .152, LAN: 192.168.1.1 + 192.168.5.1)
                 ├─ dst-nat rules → internal services
                 └─ LAN subnets (1.0/24, 5.0/24)
```
## Physical Topology — Port-to-Port Mapping

> **Snapshot from 2026-06-10 (post CRS305 install).** Cables move, ports change.
> Always re-query live state if the answer depends on what's connected *right now*.
> The commands below are the canonical way to refresh this data.

Query live (re-discovery after cable changes):
```
# MNDP — best first guess at physical neighbors
mikrotik-connect r '/ip neighbor print'
mikrotik-connect c '/ip neighbor print'
mikrotik-connect u '/ip neighbor print'
mikrotik-connect o '/ip neighbor print'
mikrotik-connect uc '/ip neighbor print'

# Bridge host tables — MAC-to-port (can be misleading)
mikrotik-connect r '/interface bridge host print terse'
mikrotik-connect c '/interface bridge host print terse'
mikrotik-connect u '/interface bridge host print terse'
mikrotik-connect o '/interface bridge host print terse'
mikrotik-connect uc '/interface bridge host print terse'

# Interface names and status
mikrotik-connect r '/interface print terse'
mikrotik-connect c '/interface print terse'
mikrotik-connect u '/interface print terse'
mikrotik-connect o '/interface print terse'
mikrotik-connect uc '/interface print terse'

# Cross-reference MACs to IPs/hostnames
mikrotik-connect r '/ip arp print terse'
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
```
### Verifying Port Mappings

**Neither bridge host tables nor MNDP are infallible.** MNDP packets (and LLDP)
traverse bridges just like any other traffic. A device on the office switch
will have its MNDP packets forwarded through the core switch's bridge and appear on
a different port than the one it's actually plugged into.

The `INTERFACE` column shows the port the packet egressed through, not necessarily
the port the device is directly connected to. The only definitive method is physical
inspection.

Example: U7Lite is physically on **router ether6** (directly connected), not on the office switch.
shows it on **router ether6** because the router's bridge forwarded the discovery
packet out that port.

Use these to narrow down the candidate port, then confirm physically:
```
mikrotik-connect r '/ip neighbor print'
mikrotik-connect c '/ip neighbor print'
mikrotik-connect u '/ip neighbor print'
mikrotik-connect o '/ip neighbor print'
mikrotik-connect uc '/ip neighbor print'
```

To identify unknown devices by MAC → IP → hostname:
```
mikrotik-connect r '/ip arp print terse'
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
```

### Topology

```
Router (RB5009) —10G— Core Switch (CRS305) —10G— Upstairs-Core (CRS305) —10G— Upstairs Switch (CRS310)
                          │                                              (in upstairs closet)
                          ├─10G→ NAS
                          └─10G→ Office Switch (CRS310)
                                 (in office)
```
### Live MNDP Baseline (2026-06-14)

```
Router (RB5009):
  → WAN
  → upstairs-core                  (MAC D0:EA:11:6B:75:F3, via core bridge)

Core Switch (CRS305):
  ether1        → Router pi/ether2          (MAC 04:F4:1C:E3:71:28, 1G management)
  sfp-sfpplus1  → nas 10GbE NIC             (MAC E8:4D:D0:C1:54:20, .175)
  sfp-sfpplus2  → Upstairs-Core sfp-sfpplus2 (MAC D0:EA:11:6B:75:F5, 10G backhaul)
  sfp-sfpplus3  → Office 10GsfpLAN          (MAC ???, 10G)
  sfp-sfpplus4  → Router 10GsfpLAN          (MAC 04:F4:1C:E3:71:2F, 10G uplink)

Upstairs-Core Switch (CRS305):
  ether1        → GL-KVM                           (192.168.5.8, PoE)
  sfp-sfpplus1  → closet 10G NIC                 (192.168.5.36)
  sfp-sfpplus2  → Core sfp-sfpplus2               (10G backhaul)
  sfp-sfpplus3  → arch I226 2.5G NIC              (192.168.5.76)
  sfp-sfpplus4  → Upstairs sfp-sfpplus1           (10G uplink)

Office Switch (CRS310):
  sfp-sfpplus2  → Core sfp-sfpplus3               (10G uplink)
  sfp-sfpplus1  → U7ProXGSOffice                  (10GbE, 192.168.5.171)
  ether1        → pite                            (192.168.5.213)


Upstairs Switch (CRS310):
  sfp-sfpplus1  → Upstairs-Core sfp-sfpplus4       (uplink, 10G)
  ether1        → Reolink NVR                      (192.168.1.67, PoE)
  ether6        → Brother printer                  (192.168.5.6)
  sfp-sfpplus2  → NOT RUNNING (was old core uplink)



## Verizon Router (Upstream CR1000B)

The upstream gateway is a **Verizon CR1000B** (firmware 3.6.0.2_BD). It handles the ISP
connection and DMZs all inbound traffic to the MikroTik. It also hosts the Headscale
port forward (6767 → home-pi).

| Property | Value |
|----------|-------|
| Model | CR1000B |
| Firmware | 3.6.0.2_BD |
| LAN | 192.168.0.1/24 |
| DHCP pool | 192.168.0.100-169 |
| DMZ target | 192.168.0.2 (MikroTik) |
| WAN IPv4 | DHCP from ISP (108.56.153.x) |


**IPv6** (from Verizon admin panel), changes often:
- **WAN method**: DHCPv6-PD
- **Delegated prefix**: `2600:4040:25fa:e400::/56` (expires ~100 min, renews automatically)
- **Router IPv6 address**: `2600:4040:25fa:e4ff::1/56`
- **Default gateway**: `fe80::a81:f4ff:fee0:4964` (link-local on the coax WAN interface)
- **LAN method**: Stateless (SLAAC)
- **LAN prefix**: `2600:4040:25fa:e400::/64` (advertised on 192.168.0.0/24 LAN subnet)

The Verizon router does SLAAC on its LAN (192.168.0.0/24), handing out addresses
from `2600:4040:25fa:e400::/64`. Devices directly on the Verizon LAN (like
home-pi at 192.168.0.154) get working IPv6 this way.

The MikroTik sits at 192.168.0.2 on this subnet and SHOULD accept a SLAAC address
and request a prefix delegation (PD) via DHCPv6 for its own LAN. **Currently the
MikroTik has stale static IPv6 addresses** (`2600:4040:2602::/48`) that don't match
the Verizon's delegated prefix — this is why IPv6 doesn't work on the LAN side.
See the `## IPv6` section for the fix.

## Port Forwarding (dst-nat)

**ALWAYS check live dst-nat first** — ports change as services move:
```
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
```

Baseline (captured 2026-05-29, live-confirmed 2026-05-29):

| WAN Port(s) | Proto | MikroTik → | Final Target | K8s NodePort | Service |
|------------|-------|-----------|-------------|-------------|---------|
| 80, 443 | TCP | **kube-vip VIP (.10):80,443** | traefik LB | 31316, 30908 | HTTP/HTTPS ingress |
| 9987 | UDP | **VIP (.10):30087** | ts-voice:30087 | 30087 | Teamspeak voice |
| 30033 | TCP | **VIP (.10):30034** | ts-files:30034 | 30034 | Teamspeak file transfer |
|| 5432 | TCP | **closet (.36):5432** | Postgres (NixOS bare-metal) | — | PostgreSQL |
| 25565 | TCP | nas (.175):32565 | minecraft-game:32565 | 32565 | Minecraft (k8s) |
| 32565 | TCP | nas (.175):32565 | minecraft-game:32565 | 32565 | Minecraft alternate |
| 11753 | TCP | **VIP (.10):31753** | openrct2-game:31753 | 31753 | OpenRCT2 |
| 6767 | Both | Verizon→home-pi:6767 | home-pi Headscale | (direct) | Headscale control |
| 30478 | UDP | **VIP (.10):30478** | headscale-stun:30478 | 30478 | Headscale STUN/DERP |
| 18080 | TCP | arch (.76):18080 | Monero P2P (bare-metal) | — | Monero |
| 25 | TCP | **VIP (.10):25** | stalwart-mail:25 (k8s) | — | SMTP (Stalwart) |
| 587 | TCP | **VIP (.10):587** | stalwart-mail:587 (k8s) | — | Submission (Stalwart) |
| 993 | TCP | **VIP (.10):993** | stalwart-mail:993 (k8s) | — | IMAPS (Stalwart) |

**Note:** The Headscale port 6767 forward lives on the Verizon router (192.168.0.1), not the MikroTik. home-pi (192.168.0.154) sits on the WAN subnet (192.168.0.0/24) directly behind the Verizon router. The MikroTik has a secondary DHCP WAN IP at 192.168.0.152 (not to be confused with home-pi).
## Subnet Layout

```
192.168.0.0/24  — 2GWAN (upstream ISP via Verizon, DHCP from 192.168.0.1)
192.168.1.0/24  — bridge (main LAN, router at .1) — cameras + reserved
192.168.5.0/24  — bridge (switch LAN, router at .1) — general devices + IoT
192.168.88.0/24 — bridge (legacy factory-default, router at .254, unused)
```

Router bridges all subnets. Inter-subnet routing is automatic (no NAT between 1.0/24 and 5.0/24).

## Cameras (Reolink)

Reolink cameras — ONVIF/RTSP, not UniFi. All cameras on dedicated 1.0/24 camera subnet.
WAN egress blocked for entire 1.0/24 subnet via firewall. secu (192.168.5.140) handles NVR duties.

**IP strategy: Router-side DHCP reservations.**
```
mikrotik-connect r '/ip dhcp-server lease make-static [find host-name=Side]'
```

## UniFi (APs + Controller)

### Access Points

| Device | IP | Model | MAC | Location | Uplink |
|--------|-----|-------|-----|----------|--------|
| U7 Pro XGS | 192.168.5.171 (DHCP) | U7 Pro XGS | 90:41:B2:D6:74:DB | Office | 10GbE (connected to office switch sfp-sfpplus1) |
| U7 Lite | 192.168.5.173 (DHCP) | U7 Lite | 1C:0B:8B:50:FF:7E | Blue Room | 1GbE (connected to router ether6) |

APs discover the controller via L2 broadcast (same bridge segment) — no special DNS or routing needed.
Device communication uses the `unifi-inform` service (LoadBalancer, TCP 8080).

### Controller

UniFi controller runs in k3s on closet (namespace: default), managed via ArgoCD:

| Resource | Details |
|----------|---------|
| **Pod** | `unifi-*` (1 replica, deployment) |
| **MongoDB pod** | `unifi-mongodb-*` (database backend) |
| **Web UI (NodePort)** | `unifi-web` → internal 8443/TCP, **NodePort 30443** on every k3s node |
| **Device inform (LB)** | `unifi-inform` → 8080/TCP, external IPs on closet, arch, nas |
| **L2 discovery (LB)** | `unifi-discovery` → 10001/UDP, external IPs on closet, arch, nas |
| **Version** | 10.0.162 (as of 2026-05-23) |

### Accessing the UniFi Controller

**Web UI (primary method):**
```
https://192.168.5.10:30443
```
Any k3s node IP on port 30443 works — use closet (192.168.5.10) as the canonical target.
The certificate is self-signed; accept the browser warning. John has admin credentials.

Health check (no auth required):
```
curl -sk https://192.168.5.10:30443/status
# {"meta":{"rc":"ok","up":true,"server_version":"10.0.162",...},"data":[]}
```

**API (programmatic access):**
The UniFi REST API lives at `/api/`. The correct login endpoint for this self-hosted (k3s) controller is **`/api/login`** (NOT `/api/auth/login` — that's for UniFi OS consoles). Credentials are stored in agenix at `/run/agenix/unifi-credentials`.
**Via kubectl (k3s pod access):**
```
ssh closet 'kubectl get pods,svc -n default | grep unifi'
ssh closet 'kubectl logs deploy/unifi -n default --tail=100'
ssh closet 'kubectl exec deploy/unifi -n default -- <command>'
```


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
mikrotik-connect r '/routing bgp session print'
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

### Switch Port Status (all switches)
```
mikrotik-connect c '/interface print terse where running'
mikrotik-connect u '/interface print terse where running'
mikrotik-connect o '/interface print terse where running'
mikrotik-connect uc '/interface print terse where running'
```

### Full Config Dump
```
mikrotik-connect r /export
```

## IPv6 (NAT66 + ULA — Working 2026-05-29)
NAT66 with ULA (`fd00:1::/64`) masquerades LAN IPv6 through 2GWAN. Fix applied 2026-05-27.

**Quick check:**
```bash
# MikroTik side: what addresses are configured?
mikrotik-connect r '/ipv6 address print terse'

# MikroTik side: is a DHCPv6 client running?
mikrotik-connect r '/ipv6 dhcp-client print'

# Traceroute from a LAN host (e.g. arch) to see where IPv6 dies
ping -6 -c 2 google.com
```
2GWAN should have an address in 2600:4040:25fa:e400::/64
bridge should have fd00:1::1/64

## Source NAT Rules

```
# Masquerade all outbound except to WAN subnet
chain=srcnat action=masquerade out-interface=2GWAN dst-address=!192.168.0.0/24

# Hairpin NAT removed 2026-05-29 — dynamic public IP makes it impractical.
# Access services directly via internal IPs (192.168.5.10 for k3s, .36 for Postgres).
```

## k3s Cluster

**Control plane:** 3-node HA (closet, arch, nas) with embedded etcd. **kube-vip VIP `192.168.5.10`** provides a floating IP for the API server — any control-plane node can hold it. **Dual-stack** (IPv4 + IPv6) with static ULA addresses (`fd00:1::/64`) for stable node-ip.
Agents: office (.209), pite (.213) — 5 nodes total.

Pod network: `10.42.0.0/24` (IPv4) + `fd42:42:42::/56` (IPv6) flannel VXLAN. Key services:

| Service | Type | External IP / NodePort | Notes |
|---------|------|----------------------|-------|
| traefik | LoadBalancer | 192.168.5.10, fd00:1::35/226/175 | HTTP:31316, HTTPS:30908 |
| unifi-web | NodePort | :30443 | UniFi controller web UI |
| unifi-inform | LB | :8080 (closet, arch, nas) | UniFi device adoption |
| unifi-discovery | LB | :10001/UDP (closet, arch, nas) | UniFi L2 discovery |
| ts-voice | NodePort | :30087/UDP | Teamspeak voice |
| ts-files | NodePort | :30034/TCP | Teamspeak file transfer |
| minecraft-game | NodePort | :32565/TCP | Minecraft |
| openrct2-game | NodePort | :31753/TCP | OpenRCT2 |
| headscale-stun | NodePort | :30478/UDP | STUN for Headscale DERP |

Query live: `ssh closet 'kubectl get nodes,pods,svc -A'`

## DNS

| Role | Server | Zone |
|------|--------|------|
| Public DNS | External provider | john2143.com, net.2143.me → home public IP |
| Tailnet DNS | home-pi (PowerDNS) | ts.9s.pics (authoritative) |
| LAN DNS | MikroTik (static only) | router.lan → 192.168.5.1 |
| mDNS/Avahi | aman (reflector) | .local across subnets |

## Notable Observations

1. **home-pi on WAN subnet:** Connected directly to Verizon router (192.168.0.154), not behind MikroTik NAT. Headscale traffic bypasses the MikroTik entirely. home-pi cannot reach LAN devices unless via Tailscale routes.

2. **kube-vip VIP 192.168.5.10:** Floating IP for k3s API. Advertised via BGP (migrated from ARP 2026-06-17) to MikroTik AS 65001. The leader pod adds the VIP to loopback and announces a `/32` route. Standby pods maintain BGP sessions but don't advertise. The VIP NEVER appears as a secondary address on physical interfaces — this prevents Flannel VXLAN FDB corruption. Config: `argo/workloads/kube-vip/daemonset.yaml`. AS layout: kube-vip nodes AS 65000, MikroTik AS 65001. See BGP section.

3. **ULA IPv6 (fd00:1::/64):** Site-local IPv6 on MikroTik bridge. All 3 k3s servers have static ULA addresses (.36, .76, .175) for stable dual-stack node-ip. Survives ISP prefix delegation changes.
4. **k3s pod network uses flannel VXLAN:** 10.42.0.0/24 + fd42:42:42::/56 dual-stack overlay.

## BGP (kube-vip — since 2026-06-17)

kube-vip floats the VIP 192.168.5.10 via BGP instead of ARP. This prevents VXLAN FDB corruption that previously caused cross-node pod network outages.

### Topology

```
kube-vip pods (AS 65000, hostNetwork, port 179)
  arch    (192.168.5.76)  ──┐
  closet  (192.168.5.36)  ──┼── BGP peering ── MikroTik (AS 65001, 192.168.5.1)
  nas     (192.168.5.175) ──┘         │
                                      │ /32 route
                                      ▼
                              192.168.5.10/32 → leader's real IP
```

The leader pod wins a Kubernetes lease (`kube-system/kube-vip`), adds the VIP to loopback, and announces it via BGP. Standby pods maintain idle sessions. If the leader dies, a new leader wins the lease and re-announces — failover takes 5-15 seconds.

### Live Status

```bash
# Check BGP sessions
mikrotik-connect r '/routing bgp session print'
# Look for: state=established. Leader has prefix-count=1, standbys have prefix-count=0.

# Check VIP route
mikrotik-connect r '/ip route print where dst-address=192.168.5.10/32'
# Shows gateway=<leader-ip>, DAb flags (dynamic, active, bgp)

# Which node is leader?
ssh closet.local 'kubectl get lease -n kube-system kube-vip -o jsonpath="{.spec.holderIdentity}"'

# Verify VIP on leader's loopback
ssh <leader>.local 'ip addr show lo | grep 192.168.5.10'
# Should show: inet 192.168.5.10/32 scope host lo
```

### Adding/Removing Nodes

**Add a control-plane node to BGP:**
```bash
# 1. Add BGP connection on MikroTik
mikrotik-connect r '/routing bgp connection add name=kube-vip-<node> as=65001 local.address=192.168.5.1 local.role=ebgp remote.address=192.168.5.<IP> remote.as=65000'

# 2. Ensure firewall port 179 is open on the new node's NixOS config
#    (dotfiles/nixos/<node>-configuration.nix)

# 3. The kube-vip DaemonSet uses nodeAffinity for control-plane nodes,
#    so the pod will auto-deploy. It reads bgp_peers from env var.
```

**Remove a node:**
```bash
mikrotik-connect r '/routing bgp connection remove [find name=kube-vip-<node>]'
```

### Troubleshooting

```bash
# BGP session won't establish?
ssh <node>.local 'ss -tlnp | grep 179'           # Is kube-vip listening?
ssh <node>.local 'iptables -L INPUT -n | grep 179' # Firewall open?
ssh closet.local 'kubectl logs -n kube-system -l app=kube-vip --tail=30' | grep -i bgp

# VIP unreachable?
# Check leader lease, BGP route, loopback VIP (three commands above).

# Force leader failover (test only):
ssh closet.local 'kubectl delete lease -n kube-system kube-vip'

# VXLAN FDB contaminated again? (shouldn't happen with BGP, but check):
for node in closet arch nas; do
  ssh closet.local "kubectl debug node/$node -it --profile=sysadmin --image=nicolaka/netshoot:latest -- nsenter -t 1 -n -- bridge fdb show dev flannel.1 | grep '192.168.5.10'"
done
# Should return nothing. If not, see headscale-flannel-fix plan.
```

### Configs Location

| Component | File |
|-----------|------|
| kube-vip DaemonSet (args, env) | `argo/workloads/kube-vip/daemonset.yaml` |
| MikroTik BGP connections | on router (`mikrotik-connect r /routing bgp connection print`) |
| Firewall port 179 | `dotfiles/nixos/<host>-configuration.nix` → `networking.firewall.allowedTCPPorts` |
| MikroTik dst-nat (VIP targets) | on router (`mikrotik-connect r /ip firewall nat print where chain=dstnat`) |
## Config Backup & Restore
Full config exports are saved in the dotfiles repo (`~/dotfiles/network-configs/`) for
disaster recovery. These are RouterOS script files (`.rsc`) — plain text, one command
per line. When asked about "the last known-good config" or "what changed", check
`~/dotfiles/network-configs/mikrotik-export-*.rsc` for the most recent backup.

### Creating a Backup

```bash

# Compact export (non-default settings only, human-readable):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 '/export' > ~/dotfiles/network-configs/router.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.4 '/export' > ~/dotfiles/network-configs/core.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.3 '/export' > ~/dotfiles/network-configs/upstairs.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.2 '/export' > ~/dotfiles/network-configs/office.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.5 '/export' > ~/dotfiles/network-configs/upstairs-core.rsc

# Verbose export (all settings including protocol-mode, bridges, defaults):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 '/export verbose' > ~/dotfiles/network-configs/router.verbose.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.4 '/export verbose' > ~/dotfiles/network-configs/core.verbose.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.3 '/export verbose' > ~/dotfiles/network-configs/upstairs.verbose.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.2 '/export verbose' > ~/dotfiles/network-configs/office.verbose.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.5 '/export verbose' > ~/dotfiles/network-configs/upstairs-core.verbose.rsc
```

The `mikrotik-connect` wrapper's SSH key is auto-materialized from agenix to
`/run/user/$UID/mikrotik-key`.

### Restoring

**Destructive — overwrites the entire running config. Reboot recommended after.**

```bash
# Via SSH pipe (streams commands directly):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 < ~/dotfiles/network-configs/router.rsc
```
**Never import a switch config onto the router or vice versa** — the interface names
and hardware topology are different.

## Intelligent Triage

When answering a question or diagnosing a problem:

1. **Static knowledge is sufficient** if the question is "what is X's IP?" or "where is Y running?" — use the tables above.
2. **Run a live query** if the question is "is X online right now?" or "what's the current ARP/route state?" — use DHCP leases (bound=alive) or ARP (reachable=alive) from the router.
3. **Don't re-fetch** data you already have in the current session. One ARP scan per conversation is enough.
4. **Correlate MAC addresses** between ARP and DHCP to identify devices without hostnames.
5. **Cross-reference with NixOS configs** when you need to understand what a host *should* be running vs. what it *is* running.
6. **For wireless-specific questions** (signal strength, AP association, channel utilization), use the UniFi controller API or web UI — the MikroTik router has no visibility into WiFi client details.
7. **k3s queries** go through `ssh closet 'kubectl ...'` when the local kubeconfig context for closet is unavailable (the default kubeconfig context points to the DigitalOcean cluster).

## Safety

- All RouterOS commands through this skill are **read-only** (`print`, `export` without `file=`, `monitor`, `get`).
- **NEVER** run add/remove/set/enable/disable/move/reset/reboot/shutdown without explicit user approval.
- **NEVER** run `nixos-rebuild switch` or `home-manager switch` without explicit user approval.
- When in doubt whether a command is read-only, show it to the user and ask.
- `export file=...` writes to device flash — it IS mutating.
- UniFi API writes (POST/PUT/DELETE beyond `/api/login`) mutate controller state. Only use read-only GET endpoints unless the user explicitly asks for configuration changes.
