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
base = 'https://192.168.6.25:8443'
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
  ether1        → pite                            (192.168.5.9)


Upstairs Switch (CRS310):
  sfp-sfpplus1  → Upstairs-Core sfp-sfpplus4       (uplink, 10G)
  ether1        → Reolink NVR                      (192.168.1.67, PoE)
  ether6        → Brother printer                  (192.168.5.6)
  sfp-sfpplus2  → bigp Proxmox 10G NIC       (192.168.5.19; VM big .68 shares this link)



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

Baseline (captured 2026-05-29; **post-MetalLB migration, live-confirmed 2026-08-04**):

| WAN Port(s) | Proto | MikroTik → | Final Target | K8s NodePort | Service |
|------------|-------|-----------|-------------|-------------|---------|
| 80, 443 | TCP | **MetalLB .6.11:80,443** | traefik (k8s LB) | 31316, 30908 | HTTP/HTTPS ingress |
| 9987 | UDP | **MetalLB .6.15:9987** | ts-voice | 30087 | Teamspeak voice |
| 30033 | TCP | **MetalLB .6.16:30033** | ts-files | 30034 | Teamspeak file transfer |
| 5432 | TCP | **closet (.36):5432** | Postgres (NixOS bare-metal) | — | PostgreSQL |
| 25565 | TCP | nas (.175):32565 | minecraft-game:32565 | 32565 | Minecraft (k8s) |
| 32565 | TCP | nas (.175):32565 | minecraft-game:32565 | 32565 | Minecraft alternate |
| 11753 | TCP | **MetalLB .6.17:11753** | openrct2-game | 31753 | OpenRCT2 |
| 6767 | Both | Verizon→home-pi:6767 | home-pi Headscale | (direct) | Headscale control |
| 30478 | UDP | **MetalLB .6.18:3478** | headscale-stun | — | Headscale STUN/DERP |
| 18080 | TCP | arch (.76):18080 | Monero P2P (bare-metal) | — | Monero |
| 25 | TCP | **MetalLB .6.13:25** | stalwart-mail | — | SMTP (Stalwart) |
| 587 | TCP | **MetalLB .6.13:587** | stalwart-mail | — | Submission (Stalwart) |
| 993 | TCP | **MetalLB .6.13:993** | stalwart-mail | — | IMAPS (Stalwart) |
| 7881 | TCP | **MetalLB .6.22:7881** | LiveKit WebRTC signal | — | LiveKit |
| 50000-60000 | UDP | **MetalLB .6.22:50000-60000** | LiveKit WebRTC media | — | LiveKit media |
| 3478 | TCP/UDP | **MetalLB .6.21:3478** | Coturn TURN | — | TURN |
| 5349 | TCP | **MetalLB .6.21:5349** | Coturn TURN TLS | — | TURN TLS |
| 7233 | TCP | **MetalLB .6.20:7233** | Temporal gRPC mTLS | — | Temporal |
| 4143 | TCP | closet (.36):4143 | Linkerd multicluster gateway | — | Linkerd MCS |

**No dst-nat (LAN-only):** mimir-lb `.6.23:8080`, loki-push-lb `.6.24:3100`, unifi-web `.6.25:8443`.

**Note:** The Headscale port 6767 forward lives on the Verizon router (192.168.0.1), not the MikroTik. home-pi (192.168.0.154) sits on the WAN subnet (192.168.0.0/24) directly behind the Verizon router. The MikroTik has a secondary DHCP WAN IP at 192.168.0.152 (not to be confused with home-pi).
**Migration (2026-08-04):** all k8s dst-nat targets moved from the kube-vip VIP `.10` to MetalLB `.6.x` LB IPs. **Fix (2026-08-03):** the 5432 dst-nat rule was re-pointed from a dead target (`.35`) to closet `.36` — postgres answers on `.36`. Note: RouterOS 7.19 `find`/`where` on port/protocol properties (`dst-port`, `to-ports`, `protocol`) matches nothing — select rules by **rule number from a fresh `print`** (`set <number> ...`) or via `find to-addresses=...` instead.
## Subnet Layout

```
192.168.0.0/24  — 2GWAN (upstream ISP via Verizon, DHCP from 192.168.0.1)
192.168.1.0/24  — bridge (main LAN, router at .1) — cameras + reserved
192.168.5.0/24  — bridge (switch LAN, router at .1) — general devices + IoT
192.168.88.0/24 — bridge (legacy factory-default, router at .254, unused)
```

Router bridges all subnets. Inter-subnet routing is automatic (no NAT between 1.0/24 and 5.0/24).

### DHCP Allocation (192.168.5.0/24)

One server (`dchp1`) on bridge, **30m leases**. Pool `dhcp` = **192.168.5.50 – 192.168.5.254** (205 addrs, ~28 used). Everything **below .50 is never served by DHCP** — the safe static range.

- Static infra below pool: .1 router, .2 office, .3 upstairs, .4 core, .5 upstairs-core, .6 Brother printer, .8 GL-KVM, .9 pite, .10 API VIP (MetalLB kubernetes-api), .19 bigp (Proxmox), .36 closet, .76 arch, .140 secu, .175 nas (static lease)
- Static reservations inside the pool: .127 (UPS), .165/.170 (presence sensors) — the server won't re-lease those
- Cameras on 1.0/24 use static leases via `make-static` (no pool covers 1.0/24)
- Rule of thumb: "is 192.168.5.X safe to assign statically?" → X < 50 has zero DHCP overlap; still check ARP/leases for the current holder of X

## Cameras (Reolink)

Reolink cameras — ONVIF/RTSP, not UniFi. All cameras on dedicated 1.0/24 camera subnet.
WAN egress blocked for entire 1.0/24 subnet via firewall. secu (192.168.5.140) handles NVR duties.

**IP strategy: Router-side DHCP reservations.**
```
mikrotik-connect r '/ip dhcp-server lease make-static [find host-name=Side]'
```

## Proxmox (bigp) + big VM

| Host | IP | MAC | Role | Notes |
|------|-----|-----|------|-------|
| bigp | 192.168.5.19 (static, below DHCP pool) | 2C:EA:7F:E7:13:98 (Dell) | Proxmox hypervisor | PVE 9.2.2 / Debian 13. Ports 22, 3128 (spiceproxy), 8006 (pveproxy). Upstairs closet, 10G link. |
| big | 192.168.5.68 (DHCP) | BC:24:11:19:22:F9 (Dell) | NixOS VM on bigp | k3s worker, tailscale node `big`. Shares bigp's physical port. |

- **bigp and big share one physical link** (big = VM bridged onto bigp's NIC → upstairs switch sfp-sfpplus2). Different SSH host keys is expected (VM ≠ hypervisor); don't read it as two machines.
- Likely iDRAC: 192.168.5.254 (`idrac-6V3QK93`, 2C:EA:7F:7B:12:75) — Dell OUI matches bigp; confirm association.
- PVE API (`/api2/json/*`) needs a ticket; 8006 cert is self-signed (`curl -k`).

## UniFi (APs + Controller)

### Access Points

| Device | IP | Model | MAC | Location | Uplink |
|--------|-----|-------|-----|----------|--------|
| U7 Pro XGS | 192.168.5.171 (DHCP) | U7 Pro XGS | 90:41:B2:D6:74:DB | Office | 10GbE (office switch sfp-sfpplus1) |
| U7 Lite | 192.168.5.173 (DHCP) | U7 Lite | 1C:0B:8B:50:FF:7E | Blue Room | 1GbE (router ether6) |
| U7-Mesh | 192.168.5.198 (DHCP) | U7-Mesh | 8C:ED:E1:EC:89:CA | — | Wireless mesh |

APs normally discover the controller via L2 broadcast (UDP 10001) — but **broadcast discovery does NOT reach this containerized controller** (kube-proxy can only DNAT unicast to the LB IPs; broadcasts are dropped at the nodes). Always use manual `set-inform` to (re)point an AP.
Device communication uses the `unifi-inform` LoadBalancer service (TCP 8080) on
the MetalLB IP **192.168.6.10** (BGP-announced).
**Post-migration (2026-08-04): inform = `192.168.6.10`** — use it for `set-inform`; `.10` is now the MetalLB-announced k3s API VIP (6443 only, no inform LB bound there).

To re-point an AP after controller rebuild:
```bash
ssh ubnt@<ap-ip>
set-inform http://192.168.6.10:8080/inform
```


### Controller

UniFi controller runs in k3s (namespace: default), managed via ArgoCD. Currently schedules on node **arch** (preferred nodeAffinity on workload-type; moved 2026-08-04 during the MetalLB INFORM_HOST rollout); historically on big/closet.
Single deployment with MongoDB as a sidecar container — no separate MongoDB pod.

| Resource | Details |
|----------|---------|
| **Pod** | `unifi-*` (1 replica, 2 containers: unifi + mongodb) |
| **Image** | `lscr.io/linuxserver/unifi-network-application:10.4.57-ls136` |
| **MongoDB** | Sidecar (`mongo:7.0`), dedicated PVC `unifi-mongodb-data` (5Gi, Longhorn 3 replicas) |
| **Web UI (LB)** | `unifi-web` → 8443/TCP, **MetalLB `192.168.6.25`** (NodePort 30443 kept) |
| **Device inform (LB)** | `unifi-inform` → 8080/TCP, **MetalLB `192.168.6.10`** (NodePort kept) |
| **L2 discovery (LB)** | `unifi-discovery` → 10001/UDP, **MetalLB `192.168.6.12`** (NodePort kept) |
| **Config PVC** | `unifi-data` (10Gi, Longhorn 3 replicas) |
| **Version** | 10.4.57 (2026-07-18) |
| **VM pitfall** | mongodb sidecar crash-looping with exitCode **132 (SIGILL)** = VM CPU type lacks AVX (mongo 7.0 requires it). Fix: set the Proxmox VM CPU type to `host` or `x86-64-v2/v3`. Hit 2026-08-03 on big. |

### Accessing the UniFi Controller

**Web UI (primary method):**
```
https://192.168.6.25:8443
```
Any k3s node IP on port 30443 (NodePort) also works. Certificate is self-signed. Admin account is local (no Ubiquiti SSO).

Health check (no auth required):
```
curl -sk https://192.168.6.25:8443/status
# {"meta":{"rc":"ok","up":true,"server_version":"10.4.57","uuid":"...","data":[]}
```

**API (programmatic access):**
Login endpoint is **`/api/login`** (NOT `/api/auth/login` — that's for UniFi OS consoles). Credentials: `/run/agenix/unifi-credentials` (updated post-reset).
If `/api/login` returns **HTTP 400**, the controller pod may be crash-looping (see VM pitfall) — check `ssh closet 'kubectl get pods -n default | grep unifi'` before debugging the script.

**Via kubectl:**
```
ssh closet.local 'kubectl get pods,svc -n default | grep unifi'
ssh closet.local 'kubectl logs deploy/unifi -n default -c unifi --tail=100'
ssh closet.local 'kubectl exec deploy/unifi -n default -c unifi -- <command>'
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

**Control plane:** 3-node HA (closet, arch, nas) with embedded etcd. **MetalLB** (BGP + frr-k8s, since 2026-08-04) announces the API VIP `192.168.5.10` (Service `kubernetes-api` + custom EndpointSlice over closet/arch/nas, port 6443) and all LoadBalancer service IPs on the `192.168.6.0/24` service pool. **Dual-stack** (IPv4 + IPv6) with static ULA addresses (`fd00:1::/64`) for stable node-ip.
Agents: office (.209, wifi — never a BGP speaker), pite (.9), big (.68, NixOS VM on bigp, joined 2026-07-29) — 6 nodes total.

Pod network: `10.42.0.0/16` (IPv4) + `fd42:42:42::/56` (IPv6) flannel VXLAN. Key services (LB IPs are MetalLB-announced, live 2026-08-04):

| Service | Type | External IP | Notes |
|---------|------|-------------|-------|
| kubernetes-api | LoadBalancer | 192.168.5.10:6443 | k3s API (MetalLB, custom EndpointSlice) |
| traefik | LoadBalancer | 192.168.6.11 | HTTP/HTTPS ingress (annotation-pinned) |
| stalwart | LoadBalancer | 192.168.6.13 | SMTP/IMAP (25/587/993) |
| unifi-inform | LoadBalancer | 192.168.6.10:8080 | UniFi device adoption |
| unifi-discovery | LoadBalancer | 192.168.6.12:10001/UDP | UniFi L2 discovery |
| unifi-web | LoadBalancer | 192.168.6.25:8443 | UniFi controller web UI |
| ts-voice | LoadBalancer | 192.168.6.15:9987/UDP | Teamspeak voice |
| ts-files | LoadBalancer | 192.168.6.16:30033 | Teamspeak file transfer |
| openrct2-game | LoadBalancer | 192.168.6.17:11753 | OpenRCT2 |
| headscale-stun | LoadBalancer | 192.168.6.18:3478/UDP | STUN for Headscale DERP |
| mosquitto | LoadBalancer | 192.168.6.19:1883 | MQTT |
| temporal-frontend | LoadBalancer | 192.168.6.20:7233 | Temporal gRPC |
| coturn | LoadBalancer | 192.168.6.21:3478,5349 | TURN (scaled to 0 — dormant) |
| livekit | LoadBalancer | 192.168.6.22:7881,50000-60000 | LiveKit (scaled to 0 — dormant) |
| mimir-lb | LoadBalancer | 192.168.6.23:8080 | Mimir push/query (LAN-only) |
| loki-push-lb | LoadBalancer | 192.168.6.24:3100 | Loki push (LAN-only) |
| minecraft-game | NodePort | :32565/TCP | Minecraft (unchanged, nodePort path) |

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

2. **MetalLB BGP (migrated from kube-vip 2026-08-04):** MetalLB (v0.16.1, frr-k8s) announces the k3s API VIP `192.168.5.10` (Service `kubernetes-api` + custom EndpointSlice) and all `.6.x` LoadBalancer IPs via BGP to MikroTik AS 65001. **5 speaker peers** (arch/closet/nas/big/pite; office is wifi — excluded). No leader lease, no loopback VIP — kube-proxy DNATs every announced IP to service endpoints on all nodes. Config: `argo/workloads/metallb/*.yaml`. AS layout: MetalLB nodes AS 65000, MikroTik AS 65001. See BGP section.

3. **ULA IPv6 (fd00:1::/64):** Site-local IPv6 on MikroTik bridge. All 3 k3s servers have static ULA addresses (.36, .76, .175) for stable dual-stack node-ip. Survives ISP prefix delegation changes.
4. **k3s pod network uses flannel VXLAN:** 10.42.0.0/16 + fd42:42:42::/56 dual-stack overlay.

5. **Tailnet service DNS (since 2026-08-05):** `*.ts.2143.me` service names (cameras, home, temporal, …) resolve via headscale MagicDNS `extra_records` to the traefik LB `192.168.6.11`; `192.168.6.0/24` is reachable from the tailnet via the subnet route advertised by arch + closet (approved in headscale). Device names (arch/closet/nas/…) are MagicDNS-generated and unaffected.

## BGP (MetalLB + frr-k8s — since 2026-08-04)

MetalLB (v0.16.1) announces the k3s API VIP `192.168.5.10` and every LoadBalancer service IP on `192.168.6.0/24` via BGP to the MikroTik (AS 65001). frr-k8s runs one FRR daemon per node; every **speaker node** advertises **all** service prefixes — no leader lease, no loopback VIP. The router installs each `/32` with 5 next-hops (one active path, the rest as failover backups — RouterOS 7.19 picks a single active path, not ECMP). Traffic lands on the node with the active route, and kube-proxy DNATs it to the service's endpoints.

### Topology

```
MetalLB speakers (AS 65000, hostNetwork, port 179)
  arch    (192.168.5.76)   ──┐
  closet  (192.168.5.36)   ──┼── BGP peering ── MikroTik (AS 65001, 192.168.5.1)
  nas     (192.168.5.175)  ──┤
  big     (192.168.5.68)   ──┤
  pite    (192.168.5.9)    ──┘
office (.209) is wifi — intentionally NOT a speaker.

Each speaker advertises every allocated /32 (.5.10 API VIP + all .6.x LB IPs).
```

### Live Status

```bash
# MetalLB's view of the 5 sessions (all should be Established):
ssh closet.local 'kubectl get bgpsessionstates -n metallb-system'

# Router's view (5 lines with E flag, names ~"metallb*"):
mikrotik-connect r '/routing bgp session print'

# A service route (5 gateways, one active DAb):
mikrotik-connect r '/ip route print where dst-address=192.168.6.11/32'

# FRR's own view (per node):
kubectl --context closet-as-developer exec -n metallb-system ds/metallb-frr-k8s -c frr -- vtysh -c 'show bgp summary'

# Current allocations:
ssh closet.local 'kubectl get svc -A | grep 192.168.6'
```

### Adding/Removing Nodes

**Add a node as BGP speaker (wired worker or control-plane):**
```bash
# 1. Add the peer to argo/workloads/metallb/bgppeer.yaml
#    (myASN 65000, peerASN 65001, peerAddress 192.168.5.1) — commit + push + sync.

# 2. Add the BGP connection on the MikroTik:
mikrotik-connect r '/routing bgp connection add name=metallb-<node> as=65001 local.address=192.168.5.1 local.role=ebgp remote.address=192.168.5.<IP> remote.as=65000'

# 3. Ensure firewall port 179 is open on the node's NixOS config
#    (dotfiles/nixos/<node>-configuration.nix).
```

**Remove a node:** drop its entry from `bgppeer.yaml` (commit + sync) and remove the router connection (`remove [find name=metallb-<node>]`). If office ever gets wired: untaint `wifi`, add the peer + router connection — it becomes a 6th speaker automatically.

### Troubleshooting

```bash
# BGP session won't establish?
ssh closet.local 'kubectl get bgpsessionstates -n metallb-system'    # which peer is down?
ssh closet.local 'kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker --tail=30'
ssh closet.local 'kubectl exec -n metallb-system ds/metallb-frr-k8s -c frr -- vtysh -c "show bgp summary"'

# Service IP unreachable?
# 1. Does it have endpoints? MetalLB will NOT announce a svc with zero endpoints.
ssh closet.local "kubectl get endpointslices -A -l kubernetes.io/service-name=<svc>"
# 2. Is the /32 in the router's table?
mikrotik-connect r '/ip route print where dst-address=192.168.6.X/32'
# 3. Kube-proxy DNAT (speaker nodes need no .6.x FIB route — PREROUTING DNAT precedes routing):
ssh <node>.local 'iptables -t nat -L KUBE-SERVICES -n | grep 192.168.6.X'
```

**RouterOS 7.19 quirks:**
- `find`/`where` on port/protocol properties (`dst-port`, `to-ports`, `protocol`) matches nothing — select nat rules by **rule number from a fresh `print`** (`set <number> ...`).
- BGP session objects persist under their original connection name after the connection is removed (RouterOS reuses session objects by remote IP) — verify by remote address / uptime, not name.

### Configs Location

| Component | File |
|-----------|------|
| MetalLB chart app (frr-k8s enabled) | `argo/apps/metallb.yaml` |
| Pool / peers / advertisement | `argo/workloads/metallb/{ipaddresspool,bgppeer,bgpadvertisement}.yaml` |
| k8s API VIP Service + EndpointSlice | `argo/workloads/metallb/kubernetes-api-lb.yaml` |
| MikroTik BGP connections | on router (`mikrotik-connect r /routing bgp connection print`) |
| Firewall port 179 | `dotfiles/nixos/<host>-configuration.nix` → `networking.firewall.allowedTCPPorts` |
| MikroTik dst-nat (.6.x targets) | on router (`mikrotik-connect r /ip firewall nat print where chain=dstnat`) |
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
8. **Validate LB/BGP paths from OUTSIDE the system under test.** Cluster nodes DNAT `.6.x` traffic locally (kube-proxy PREROUTING precedes routing), so `curl` from office/big/pite proves nothing about the router path. Use a non-cluster device: an AP, the WAN, or a LAN host whose route actually crosses the router. (Home-pi on 192.168.0.x is NOT such a host — the Verizon router has no route to `.6.0/24`; its timeouts say nothing.)
9. **Check BOTH ends before declaring a path broken.** A `syn-sent` in the router's connection table means the router saw the packet — it does NOT mean forwarding failed. Verify the receiving side (e.g. `cat /proc/net/nf_conntrack` on the speaker node for the VIP:port) before concluding breakage. In 2026-08-04's migration this exact trap caused a false "router forwarding broken" alarm.
10. **ICMP on a MetalLB BGP VIP always times out** — no interface owns the VIP and kube-proxy only DNATs TCP/UDP. A failed `ping` to `.6.x` is expected, not a symptom.

## Safety

- All RouterOS commands through this skill are **read-only** (`print`, `export` without `file=`, `monitor`, `get`).
- **NEVER** run add/remove/set/enable/disable/move/reset/reboot/shutdown without explicit user approval.
- **NEVER** run `nixos-rebuild switch` or `home-manager switch` without explicit user approval.
- When in doubt whether a command is read-only, show it to the user and ask.
- `export file=...` writes to device flash — it IS mutating.
- UniFi API writes (POST/PUT/DELETE beyond `/api/login`) mutate controller state. Only use read-only GET endpoints unless the user explicitly asks for configuration changes.
