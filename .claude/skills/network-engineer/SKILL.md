---
description: Inject network context into any session — device inventory, live ARP/routes/DHCP, server-to-flake mapping, subnet layout
argument-hint: (none — invoked as skill://network-engineer)
allowed-tools: Bash(mikrotik-connect *), Bash(kubectl *), Bash(ssh closet *), Read, Search
tool-hints: |
  This skill injects context. It does NOT modify anything.
  All RouterOS commands are read-only (print, export, monitor, get).
  NEVER run add/remove/set/enable/disable/reboot/shutdown without explicit user approval.
  Prefer live queries over stale static data when confirming current state.
  kubectl is available via `ssh closet 'kubectl ...'` for local cluster queries.
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

fy|

**IPv6 state:**
```
mikrotik-connect r '/ipv6 address print terse'
mikrotik-connect r '/ipv6 dhcp-client print'
mikrotik-connect r '/ipv6 route print terse'
fy|

**Switch port status:**
```
mikrotik-connect u '/interface print terse where running'
mikrotik-connect d '/interface print terse where running'
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
base = 'https://192.168.5.35:30443'
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

After running, summarize: how many hosts are online (bound DHCP + reachable ARP), what services are exposed (dst-nat), which switch ports are live, and the UniFi wireless snapshot (AP status + client count + any weak-signal clients below -80 dBm). Then proceed with the user's actual request.

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

Query live:
```
mikrotik-connect r '/interface bridge host print terse'
mikrotik-connect u '/interface bridge host print terse'
mikrotik-connect d '/interface bridge host print terse'
mikrotik-connect r '/interface print terse'
mikrotik-connect u '/interface print terse'
mikrotik-connect d '/interface print terse'
mikrotik-connect r '/ip arp print terse'
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
```

### Topology

```
Router ←→ Downstairs Switch ←→ Upstairs Switch
           (CRS326)     e7↔e8  (CRS310)
```

### Inter-Device Links

| Link | Speed |
|---|---|
| Router ↔ Downstairs switch | 10GbE SFP+ |
| Downstairs `ether7` ↔ Upstairs `ether8` | 1GbE RJ45 |

### Router (CCR)

| Port (renamed) | Default | Speed | Connected to |
|---|---|---|---|
| `2GWAN` | ether1 | 1GbE | Verizon CR1000B (WAN uplink) |
| `pi` | ether2 | 1GbE | pite (192.168.5.213) |
| `ether3` | ether3 | 1GbE | vpin (192.168.5.252) |
| `ether4` | ether4 | 1GbE | nas 1GbE NIC (192.168.5.176) |
| `ether5` | ether5 | 1GbE | JetKVM (192.168.5.187) |
| `ether7` | ether7 | 1GbE | Front Driveway camera (192.168.1.66) |
| `to-wifi` | ether8 | — | DISABLED |
| `10GsfpLAN` / `ether6` | sfp-sfpplus1 / ether6 | 10GbE + 1GbE | Downstairs switch (bridge ports — see note) |

> **Note:** Router bridge host data splits clients between 10GsfpLAN and ether6.
> This is a RouterOS bridge internal artifact — the physical link is a single
> connection to the downstairs switch. Do not treat these as separate cables.

### Downstairs Switch (CRS326-24G-2S+RM)

| Port | Speed | Connected to |
|---|---|---|
| `sfp-sfpplus1` | 10GbE SFP+ | nas 10GbE NIC (192.168.5.175) |
| `ether5` | 1GbE | office (192.168.5.209) + U7 Pro XGS AP (192.168.5.171) |
| `ether7` | 1GbE | Upstairs switch `ether8` (inter-switch) |

### Upstairs Switch (CRS310-1G-5S-4S+)

| Port | Speed | Connected to |
|---|---|---|
| `sfp-sfpplus2` | 1GbE SFP | closet (192.168.5.35) |
| `ether1` | 1GbE | Front Gate cam (.64), Front Porch cam (.63), NVR (.67) |
| `ether2` | 1GbE | Unknown device (192.168.5.8) |
| `ether8` | 1GbE | Downstairs switch `ether7` (inter-switch) |

Inbound: Verizon DMZs everything to MikroTik. MikroTik dst-nat rules route specific ports to internal hosts.
Domains `john2143.com` and `net.2143.me` resolve to the home public IP.

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

**IPv6** (from Verizon admin panel):
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

Baseline (captured 2026-05-22, live-confirmed 2026-05-23):

| WAN Port(s) | Proto | MikroTik → | Final Target | K8s NodePort | Service |
|------------|-------|-----------|-------------|-------------|---------|
| 80, 443 | TCP | closet:80,443 | traefik LB | 31316, 30908 | HTTP/HTTPS ingress |
| 9987 | UDP | closet:30087 | ts-voice:30087 | 30087 | Teamspeak voice |
| 30033 | TCP | closet:30034 | ts-files:30034 | 30034 | Teamspeak file transfer |
| 5432, 5999 | TCP | closet:5432 | CNPG Postgres | (ClusterIP) | PostgreSQL |
| 25565 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft (k8s) |
| 32565 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft alternate |
| 11753 | TCP | closet:31753 | openrct2-game:31753 | 31753 | OpenRCT2 |
| 6767 | Both | Verizon→home-pi:6767 | home-pi Headscale | (direct) | Headscale control |
| 30478 | UDP | closet:30478 | headscale-stun:30478 | 30478 | Headscale STUN |
| — | — | 192.168.0.0/16 → public IP | Hairpin NAT | — | LAN→WAN→LAN loopback |

**Note:** The Headscale port 6767 forward lives on the Verizon router (192.168.0.1), not the MikroTik. home-pi (192.168.0.154) sits on the WAN subnet (192.168.0.0/24) directly behind the Verizon router. The MikroTik has a secondary DHCP WAN IP at 192.168.0.152 (not to be confused with home-pi).
## Subnet Layout

```
192.168.0.0/24  — 2GWAN (upstream ISP via Verizon, DHCP from 192.168.0.1)
192.168.1.0/24  — bridge (main LAN, router at .1) — cameras + reserved
192.168.5.0/24  — bridge (switch LAN, router at .1) — general devices + IoT
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
| **closet** | 192.168.5.35 (static, permanent ARP) + .202 (DHCP secondary) | k3s server, Longhorn storage, UniFi controller | Ryzen 5 1600, 7.7GB, 4TB USB SSD |
| **nas** | 192.168.5.175-176 (DHCP, dual NIC) | ZFS file server, atticd cache, k3s + Longhorn | i7-3770K, 15GB, 4×8TB HDD ZFS RAIDZ1, 10GbE SFP+ |
| **secu** | 192.168.5.140 (DHCP) | Security camera NVR (FDE) | HP EliteDesk 800 G3, i5-6500T, 7.6GB |
| **pite** | 192.168.5.213 (DHCP) | k3s agent, canary (honeytoken bait) | Raspberry Pi 4B, 1.8GB, 238GB SD |
| **vpin** | 192.168.5.252 (DHCP) | Mullvad exit node | Raspberry Pi (3?), 3.7GB, 59.5GB SD |
| **home-pi** | 192.168.0.154 (DHCP, WAN subnet) | Headscale server, PowerDNS | Raspberry Pi (aarch64) |
| **aman** | DHCP (Tailscale) | Mullvad exit node, Avahi reflector | Raspberry Pi 4B, 3.7GB, 238GB SD |

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
| UniFi Controller | closet (k8s) | `https://192.168.5.35:30443` |


## Cameras (Reolink)

Reolink cameras — ONVIF/RTSP, not UniFi. All cameras on dedicated 1.0/24 camera subnet.
WAN egress blocked for entire 1.0/24 subnet via firewall. secu (192.168.5.140) handles NVR duties.

**IP strategy: Router-side DHCP reservations.**
```
mikrotik-connect r '/ip dhcp-server lease make-static [find host-name=Side]'
```

| Camera | IP | Subnet | Connection | MAC | Hostname |
|--------|-----|--------|-----------|-----|----------|
| Back yard | 192.168.1.60 | 1.0/24 | WiFi, static | 78:93:C3:8E:34:9F | (none) |
| Garage | 192.168.1.61 | 1.0/24 | WiFi, static | EC:71:DB:F4:DC:49 | Garage |
| Front porch | 192.168.1.63 | 1.0/24 | Wired, static | EC:71:DB:89:D8:8B | Front |
| Front Gate | 192.168.1.64 | 1.0/24 | Wired, static | EC:71:DB:65:58:A3 | Front |
| Side yard | 192.168.1.65 | 1.0/24 | WiFi, DHCP resv | 94:B3:F7:18:52:CC | Side |
| Front Driveway | 192.168.1.66 | 1.0/24 | Wired, DHCP resv | EC:71:DB:3E:2F:21 | Front |
| Reolink NVR | 192.168.1.67 | 1.0/24 | Wired, DHCP resv | EC:71:DB:8B:92:93 | NVR |

**Note:** Side yard was previously at 192.168.5.169 (5.0/24) and Front Driveway at 192.168.5.174 (5.0/24) — both now migrated to 1.0/24. Back yard camera (.60) is back online (ARP reachable as of 2026-05-23).

## IoT / Smart Home Devices

Discovered via live DHCP (2026-05-23):

| Device | IP | MAC | Notes |
|--------|-----|-----|-------|
| AiDot lights (×4) | 192.168.5.164, .166, .167, .168 | D0:CF:13:8C:* | Smart bulbs/lighting |
| Akamatis presence sensor | 192.168.5.170 | 94:A9:90:6C:70:88 | mmWave presence sensor |
| Akamatis presence sensor | 192.168.5.165 | 80:F1:B2:52:F0:C8 | mmWave presence sensor |
| WiZ smart light | 192.168.5.132 | D8:A0:11:79:F1:3C | WiZ Connected (hostname: wiz_79f13c) |
| JetKVM | 192.168.5.187 | 30:52:53:09:E1:72 | Server KVM over IP (hostname: serverkvm) |
| K3B-US-PGA0539A | 192.168.5.127 | C8:FF:77:57:E0:3D | Permanent ARP entry at .219 — ARP entry needs cleanup |
| Linux ARM device | 192.168.5.147 | B0:FC:0D:DE:FB:50 | Linux 3.18.19 on armv7l (dhcpcd) |
| John Bedroom Lightswitch | 192.168.5.172 | 00:07:A6:40:E7:4B | Identified via UniFi controller (hostname: John Bedroom Lightswitch, on iot-2707 SSID) |
| Unknown (ARP only) | 192.168.5.8 | 94:83:C4:C4:9C:4D | In ARP reachable but not in DHCP — static IP? |

**Transient devices** (phones/laptops with rotating MACs):
| Device | Typical IPs | MAC fingerprint |
|--------|------------|----------------|
| Peloton | 192.168.5.146 | 54:49:DF:12:BF:49 | Identified via UniFi controller (on main SSID, previously labeled "Android phone") |
| iPhones (×3) | 192.168.5.128, .135, .136 | Private MACs |
| Mac laptop | 192.168.5.130 | AE:03:7C:11:A5:00 |
| Pop!_OS laptop | 192.168.5.221 | D4:D8:53:A7:6A:B1 | System76 laptop (hostname: pop-os) |

## UniFi (APs + Controller)

### Access Points

| Device | IP | Model | MAC | Location | Uplink |
|--------|-----|-------|-----|----------|--------|
| U7 Pro XGS | 192.168.5.171 (DHCP) | U7 Pro XGS | 90:41:B2:D6:74:DB | Office | 10GbE SFP+ (connected to downstairs switch ether5, limited to 1GbE) |
| U7 Lite | 192.168.5.173 (DHCP) | U7 Lite | 1C:0B:8B:50:FF:7E | Blue Room | 1GbE via downstairs switch |

**U7 Pro XGS (Office):**
- WiFi 7 (802.11be) — tri-band (2.4 / 5 / 6 GHz)
- 10GbE SFP+ uplink (connected to downstairs switch ether5, limited to 1GbE by switch port — not upstairs as previously thought)
- Primary high-performance AP
- Hostname: `U7ProXGSOffice`, DHCP class-id: `ubnt`

**U7 Lite (Blue Room):**
- WiFi 7 (802.11be) — dual-band (2.4 / 5 GHz)
- 2.5GbE uplink (limited to 1GbE by downstairs switch port)
- Compact AP for secondary coverage
- Hostname: `U7LiteBlueRoom`, DHCP class-id: `ubnt`

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
https://192.168.5.35:30443
```
Any k3s node IP on port 30443 works — use closet (192.168.5.35) as the canonical target.
The certificate is self-signed; accept the browser warning. John has admin credentials.

Health check (no auth required):
```
curl -sk https://192.168.5.35:30443/status
# {"meta":{"rc":"ok","up":true,"server_version":"10.0.162",...},"data":[]}
```

**API (programmatic access):**
The UniFi REST API lives at `/api/`. The correct login endpoint for this self-hosted (k3s) controller is **`/api/login`** (NOT `/api/auth/login` — that's for UniFi OS consoles). Credentials are stored in agenix at `/run/agenix/unifi-credentials`.

**Python (recommended — handles special characters in passwords):**
```python
import urllib.request, ssl, json, http.cookiejar

# Load credentials from agenix
with open('/run/agenix/unifi-credentials') as f:
    creds = {}
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            creds[k] = v.strip('"')

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
base = 'https://192.168.5.35:30443'

# Login
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(cj),
    urllib.request.HTTPSHandler(context=ctx)
)
data = json.dumps({'username': creds['UNIFI_USERNAME'], 'password': creds['UNIFI_PASSWORD'], 'remember': True}).encode()
opener.open(urllib.request.Request(f'{base}/api/login', data=data,
    headers={'Content-Type': 'application/json'}))

# Query APs
resp = opener.open(urllib.request.Request(f'{base}/api/s/default/stat/device'))
aps = [d for d in json.loads(resp.read())['data'] if d.get('type') == 'uap']
for ap in aps:
    print(f"{ap.get('name')} | {ap.get('model')} | state={ap.get('state')} | clients={ap.get('num_sta',0)} | {ap.get('ip')}")

# Query wireless clients with signal
resp = opener.open(urllib.request.Request(f'{base}/api/s/default/stat/sta'))
for c in json.loads(resp.read())['data']:
    print(f"{c.get('hostname') or c.get('name') or '?'} | {c.get('ip')} | {c.get('signal')} dBm | {c.get('radio_proto')} | ch{c.get('channel')} | {c.get('essid')}")
```

**curl (for passwords without $ * ^ characters):**
```bash
source /run/agenix/unifi-credentials
curl -sk -c /tmp/unifi-jar -X POST "https://192.168.5.35:30443/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}"

# List APs
curl -sk -b /tmp/unifi-jar "https://192.168.5.35:30443/api/s/default/stat/device" | \
  jq '[.data[] | select(.type=="uap")] | .[] | {name,model,state,num_sta,ip}'

# List wireless clients with signal
curl -sk -b /tmp/unifi-jar "https://192.168.5.35:30443/api/s/default/stat/sta" | \
  jq '.data[] | {hostname,ip,signal,radio_proto,channel,essid}'
```

Key API endpoints under `/api/s/default/`:

| Endpoint | Description |
|----------|-------------|
| `/stat/sta` | Wireless clients: signal (dBm), channel, TX/RX rates, AP MAC, uptime |
| `/stat/user` | All clients (wired + wireless) with OUI vendor lookup |
| `/stat/device` | UniFi devices: model, IP, state, uptime, client count |
| `/stat/health` | Site health summary (WAN, LAN, WiFi metrics) |
| `/stat/rogueap` | Rogue AP detection |
| `/rest/wlanconf` | WiFi network (SSID) configuration |

**Via kubectl (k3s pod access):**
```
ssh closet 'kubectl get pods,svc -n default | grep unifi'
ssh closet 'kubectl logs deploy/unifi -n default --tail=100'
ssh closet 'kubectl exec deploy/unifi -n default -- <command>'
```

### Viewing Wireless Clients

Three approaches, from quickest to most detailed:

1. **API (fastest for scripting):** Use `/stat/sta` as shown above. Returns per-client IP, MAC, hostname, connected AP, channel, RSSI (dBm), TX/RX rates, and uptime. Pipe through `jq` for filtering.

2. **Web UI (for visual inspection):** Log into `https://192.168.5.35:30443` → Clients tab → filter by "WiFi". Shows signal strength bars, channel, data rates, and connection history.

3. **Pod logs (for troubleshooting):** `ssh closet 'kubectl logs deploy/unifi -n default --tail=200'` shows device association events, disconnections, and errors.

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

## IPv6 (Known Broken — Prefix Mismatch)

### The Problem

The MikroTik has **stale static IPv6 addresses** that don't match the prefix the ISP
delegates:

| Source | Prefix | Status |
|--------|--------|--------|
| ISP delegates | `2600:4040:25fa:e400::/56` | Real |
| Verizon CR1000B LAN | `2600:4040:25fa:e400::/64` (SLAAC on 192.168.0.0/24) | Real |
| **MikroTik WAN (2GWAN)** | **`2600:4040:2602:f800::2/64`** | **Stale — doesn't exist** |
| **MikroTik LAN (bridge)** | **`2600:4040:2602:f801::1/64`** | **Stale — doesn't exist** |
| **Default route** | **`2600:4040:2602:f800::1`** | **Stale — unreachable** |

The Verizon router hands out `2600:4040:25fa:e400::/64` via SLAAC on its own LAN
(192.168.0.0/24). The MikroTik has statically configured `2600:4040:2602::/48`
addresses — a completely different range the ISP never delegated. The Verizon's
upstream gateway (`fe80::a81:f4ff:fee0:4964`) returns "Destination unreachable"
for any outbound IPv6 packet because the source prefix is unknown.

### Quick Check

```bash
# MikroTik side: what addresses are configured?
mikrotik-connect r '/ipv6 address print terse'

# MikroTik side: is a DHCPv6 client running?
mikrotik-connect r '/ipv6 dhcp-client print'

# Traceroute from a LAN host (e.g. arch) to see where IPv6 dies
ping -6 -c 2 google.com
# Expected: "From 2600:4040:2602:f800::2 Destination unreachable" — the
# MikroTik's WAN address is the one returning the error
```

### The Fix (Applied 2026-05-27)

**Root cause**: Two problems:
1. `accept-router-advertisements=yes-if-forwarding-disabled` combined with `forward=yes`
   meant the MikroTik ignored SLAAC on its WAN interface — it never picked up the real
   prefix from the Verizon router.
2. The Verizon CR1000B does not respond to DHCPv6-PD requests from downstream routers
   (it uses DHCPv6-PD to get its own prefix from the ISP, but does not delegate sub-
   prefixes). So a prefix delegation approach won't work.

**Solution** — NAT66 with ULA on the LAN:

The Verizon router sends RAs with a default route and link-local gateway, but without
Prefix Information Options (no PIO). The MikroTik receives the default route via SLAAC
but doesn't get a global address automatically. The fix:

```
# 1. Remove stale static addresses and routes (2600:4040:2602::/48)
/ipv6 address remove [find address~"2600:4040:2602"]
/ipv6 route remove [find dst-address="::/0"]

# 2. Accept RAs from the Verizon router on the WAN interface
/ipv6 settings set accept-router-advertisements=yes

# 3. Assign a global address on 2GWAN from the Verizon's SLAAC prefix
#    Use EUI-64 to avoid conflicts (MAC-based address)
/ipv6 address add address=2600:4040:25fa:e400:06f4:1cff:fee3:7127/64 \
    interface=2GWAN advertise=no

# 4. Assign a ULA prefix on the bridge for LAN hosts
/ipv6 address add address=fd00:1::1/64 interface=bridge advertise=yes

# 5. NAT66: masquerade all LAN IPv6 traffic out through 2GWAN
/ipv6 firewall nat add chain=srcnat action=masquerade out-interface=2GWAN
```

**How it works**:
- 2GWAN gets a global IPv6 address in the Verizon's `2600:4040:25fa:e400::/64` range
- The Verizon sends a default route via RA (`fe80::7690:bcff:fe79:aa4`), which the
  MikroTik installs as a dynamic SLAAC default route
- LAN hosts get ULA addresses (`fd00:1::/64`) via SLAAC from the MikroTik
- NAT66 masquerade translates ULA traffic to the global WAN address on 2GWAN
- Result: LAN hosts get working IPv6 (~5-8ms) without Verizon cooperation

**Important**: The global address on 2GWAN is static-manual. If the Verizon's delegated
prefix changes (ISP reassigns), this address must be updated. Check with:
```
mikrotik-connect r '/ipv6 address print'
    # 2GWAN should have an address in 2600:4040:25fa:e400::/64
    # bridge should have fd00:1::1/64
```

## Source NAT Rules

```
# Masquerade all outbound except to WAN subnet
chain=srcnat action=masquerade out-interface=2GWAN dst-address=!192.168.0.0/24

# Hairpin NAT for LAN→WAN→LAN loopback
chain=srcnat action=masquerade out-interface=bridge src-address=192.168.0.0/16 dst-address=192.168.5.35
```

## k3s Cluster

**Server:** closet (192.168.5.35) — control-plane, 5 nodes (all Ready, v1.35.x).
Agents: arch (.226), nas (.175), office (.209), pite (.213).

Pod network: `10.42.0.0/24` flannel VXLAN overlay. Key services:

| Service | Type | External IP / NodePort | Notes |
|---------|------|----------------------|-------|
| traefik | LoadBalancer | 192.168.5.35, .226, .175, .209, .213 | HTTP:31316, HTTPS:30908 |
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

## Summary Metrics

| Metric | Count |
|--------|-------|
| NixOS hosts | 9 (8 local + 1 WAN-side home-pi) |
| k3s nodes | 5 (all Ready) |
| Cameras online | 7 of 7 |
| IoT/smart devices | 11 |
| Switch ports active | 8 router, 3 downstairs, 4 upstairs |
| External services | 9 |

## Notable Observations

1. **closet dual IP (.35 + .202):** Static primary + DHCP secondary on same interface. Static .35 is the k3s node IP with permanent ARP. DHCP .202 is a dhcpcd/NetworkManager artifact — harmless.

2. **MikroTik dual WAN IP (.2 + .152):** Static .2 is Verizon DMZ target. DHCP .152 is secondary — may be legacy.

3. **home-pi on WAN subnet:** Connected directly to Verizon router (192.168.0.154), not behind MikroTik NAT. Headscale traffic bypasses the MikroTik entirely. home-pi cannot reach LAN devices unless via Tailscale routes.

4. **Unknown device .172 (00:07:A6:40:E7:4B):** MAC prefix = Eutron S.p.A. (Italian security/industrial). No hostname or client-id.

5. **No MikroTik dst-nat for 6767:** Headscale forward is solely on the Verizon router. MikroTik does not participate.

6. **k3s pod network uses flannel VXLAN:** 10.42.0.0/24 overlay. Nodes communicate via bridge IPs.
## Config Backup & Restore

Full config exports are saved in the dotfiles repo (`~/dotfiles/network-configs/`) for
disaster recovery. These are RouterOS script files (`.rsc`) — plain text, one command
per line. When asked about "the last known-good config" or "what changed", check
`network-configs/mikrotik-export-*.rsc` for the most recent backup.

### Format

The `.rsc` format is RouterOS's native export format. Every line is a valid RouterOS
command that could be typed at the CLI. Example excerpt:

```rsc
# may/27/2026 00:06:06 by RouterOS 7.19.6
# software id = ...
#
/interface bridge
add name=bridge
/interface vlan
add interface=bridge name=vlan10 vlan-id=10
/ip address
add address=192.168.5.1/24 interface=bridge network=192.168.5.0
```

The first two lines are comments (date, version, software ID). Everything after is
executable. **Do not hand-edit** the export for restore — the full dump is atomic and
RouterOS expects to replay it in order.

### Creating a Backup

```bash
# On the MikroTik flash:
mikrotik-connect r '/export file=mikrotik-export-2026-05-27'
# Download to local repo (this is what saves to network-configs/):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 '/export' \
  > network-configs/mikrotik-export-YYYY-MM-DD.rsc

# Same for switches:
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.3 '/export' \
  > network-configs/upstairs-switch-export-YYYY-MM-DD.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.2 '/export' \
  > network-configs/downstairs-switch-export-YYYY-MM-DD.rsc
```

The `mikrotik-connect` wrapper's SSH key is auto-materialized from agenix to
`/run/user/$UID/mikrotik-key`.

### Restoring

**⚠️ Destructive — overwrites the entire running config. Reboot recommended after.**

```bash
# Option A via RouterOS flash (file must already exist there):
mikrotik-connect r '/import file=mikrotik-export-2026-05-27.rsc'
mikrotik-connect r '/system reboot'

# Option B via SSH pipe (streams commands directly):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 \
  < network-configs/mikrotik-export-2026-05-27.rsc
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
