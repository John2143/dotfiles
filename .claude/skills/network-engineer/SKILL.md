---
description: Inject network context into any session — device inventory, live ARP/routes/DHCP, server-to-flake mapping, subnet layout
argument-hint: (none — invoked as skill://network-engineer)
allowed-tools: Bash(mikrotik-connect *), Bash(kubectl *), Bash(ssh *), Bash(curl *), Read, Search, Edit
tool-hints: |
  This skill injects context. It does NOT modify anything.
  All RouterOS commands are read-only (print, export, monitor, get).
  NEVER run add/remove/set/enable/disable/reboot/shutdown without explicit user approval.
  Prefer live queries over stale static data when confirming current state.
  kubectl is available via `ssh closet 'kubectl ...'` for local cluster queries —
  and ALWAYS query all namespaces (`-A`), never just `-n default`.
  BEFORE proposing any new WAN port, confirm no dstnat rule's dst-port range covers it:
  DNAT runs before the input filter and will silently steal the packet.
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
```

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

The MikroTik sits at 192.168.0.2 on this subnet and accepts a SLAAC address plus a
DHCPv6 prefix delegation for its own LAN. **Verified working 2026-09-17** — 2GWAN holds
current Verizon-prefix addresses (`2600:4040:25fa:e400:6f4:1cff:fee3:7127/64` plus a second
`2600:4040:25fc:8d00::/64`), and the bridge advertises ULA `fd00:1::1/64` to the LAN.
(The older "stale static `2600:4040:2602::/48`" note is obsolete — re-check live with
`/ipv6 address print terse` before trusting either.) See the `## IPv6` section.

## Port Forwarding (dst-nat)

**ALWAYS check live dst-nat first** — ports change as services move:
```
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
```

Baseline — **live-verified 2026-09-17** (targets re-measured; several had drifted from the
2026-08-04 snapshot):

| WAN Port(s) | Proto | MikroTik → (live target) | Service | Notes |
|------------|-------|--------------------------|---------|-------|
| 80, 443 | TCP | `.6.11:80,443` | kube-system/traefik | HTTP/HTTPS ingress |
| 25, 587, 993 | TCP | `.6.13:25,587,993` | stalwart/stalwart-stalwart | SMTP / submission / IMAPS |
| 9987 | UDP | `.6.15:9987` | default/ts-voice | Teamspeak voice |
| 30033 | TCP | `.6.16:30033` | default/ts-files | Teamspeak file transfer |
| 11753 | TCP | `.6.17:11753` | default/openrct2-game | OpenRCT2 |
| 30478 | UDP | `.6.18:3478` | default/headscale-stun | Headscale STUN/DERP |
| 7233 | TCP | `.6.20:7233` | default/temporal-frontend | Temporal gRPC mTLS |
| 7881 | TCP | `.6.22:7881` | matrix/livekit-server-rtc | LiveKit WebRTC signal |
| 3478 | TCP+UDP | `.6.14:3478` | steam-lobby/coturn | TURN (live) |
| 45000-45063 | UDP | `.6.14:45000-45063` | steam-lobby/coturn | TURN relay range (live) |
| 5349 | TCP | `.6.21:5349` | matrix/coturn — ⚠️ but `.6.21` publishes `3478 + 49152-49215`, **not** 5349 | likely dead |
| **51820** | **UDP** | **the router itself (`wg-remote`)** | WireGuard remote access | **added 2026-09-17** |
| 5432 | TCP | `.5.36:5432` | Postgres (NixOS bare-metal) | PostgreSQL |
| 18080 | TCP | `.5.76:18080` | Monero P2P (NixOS bare-metal) | Monero |
| 25565, 32565 | TCP | `.5.175:32565` | default/minecraft-game | Minecraft (k8s) |
| 34197 | UDP | `.6.28:34197` | default/factorio-game | Factorio |
| 6767 | Both | Verizon → home-pi:6767 | home-pi Headscale | **lives on the Verizon router, not the MikroTik** |

**Removed 2026-09-17:** `50000-60000 UDP → .6.14` (comment `LiveKit WebRTC media`). It was
vestigial — its target (steam-lobby/coturn) relays on `45000-45063`, and livekit's LB
publishes only `50000/UDP` — and it silently shadowed UDP 51820. To restore:

```
mikrotik-connect r '/ip firewall nat add chain=dstnat action=dst-nat to-addresses=192.168.6.14 to-ports=50000-60000 protocol=udp in-interface-list=WAN dst-port=50000-60000 comment="LiveKit WebRTC media"'
```

**⚠️ Known inbound gaps (observed 2026-09-17, not yet fixed):** `matrix/coturn` relays on
`49152-49215/UDP` and `matrix/livekit-server-rtc` publishes `50000/UDP`, but **neither range
has a dst-nat rule** — inbound TURN relay / media for those two services cannot work. The
`5349` rule targets `.6.21:5349`, a port `matrix/coturn` does not publish.

**CRITICAL — before choosing any new WAN port:** confirm no dstnat rule's `dst-port` range
covers it. DNAT runs in PREROUTING, *before* the `input` filter chain, so a covering range
steals the packet and a listener on the router itself never sees it. This is exactly what hid
UDP 51820 behind the (since-removed) LiveKit range — external probes were DNATed to `.6.14`
instead of reaching the router.

**No dst-nat (LAN-only):** mimir-lb `.6.23:8080`, loki-push-lb `.6.24:3100`,
unifi-web `.6.25:8443`, frigate `.6.26`, pihole-dns `.6.27:53`.

**Note:** The Headscale port 6767 forward lives on the Verizon router (192.168.0.1), not the MikroTik. home-pi (192.168.0.154) sits on the WAN subnet (192.168.0.0/24) directly behind the Verizon router. The MikroTik has a secondary DHCP WAN IP at 192.168.0.152 (not to be confused with home-pi).
**Migration (2026-08-04):** all k8s dst-nat targets moved from the kube-vip VIP `.10` to MetalLB `.6.x` LB IPs. **Fix (2026-08-03):** the 5432 dst-nat rule was re-pointed from a dead target (`.35`) to closet `.36` — postgres answers on `.36`. Note: RouterOS 7.19 `find`/`where` on port/protocol properties (`dst-port`, `to-ports`, `protocol`) matches nothing — select rules by **rule number from a fresh `print`** (`set <number> ...`), or match on `comment` (`remove [find comment="..."]`), which works fine.

## WireGuard (remote access — built 2026-09-17)

Native RouterOS WireGuard. **Built into the base `routeros` package since 7.1 — nothing to
install** (the RB5009 runs exactly one package: `routeros`). Verified working on 7.19.6 /
arm64: interface listening, inbound path proven end-to-end from external nodes.

> The server side is complete, but it ships with **zero peers** — nothing can connect until a
> peer is added. Unauthenticated packets are silently discarded, so "no response" is normal.

| Property | Value |
|----------|-------|
| Interface | `wg-remote` (`type=wg`, MTU 1420, running) |
| Listen port | **UDP 51820** |
| Tunnel subnet | `10.99.0.0/24` — the router is `10.99.0.1` |
| Server public key | `2HeIlsYngjfFpCctWpzJyfFCC0+npvliQMzaglf8bGw=` |
| Client endpoint | `john2143.com:51820` (public DNS tracks the DHCP WAN IP) |
| Firewall | `input accept udp dst-port=51820 in-interface-list=WAN`, placed **before** `drop all not coming from LAN` |
| `LAN` list | `wg-remote` is a member — required so tunnel traffic *to the router itself* (DNS, SSH, Winbox) isn't dropped by that same rule |
| Verizon | **nothing to forward** — the CR1000B DMZ already delivers all inbound to 192.168.0.2 |

### How it works

- **No client/server distinction.** Every participant is a peer with a keypair; the router is
  merely the peer with a stable public endpoint. One peer entry per device.
- **`allowed-address` is the entire routing table**, doing double duty: which destinations get
  encrypted to that peer, *and* which source IPs are accepted *from* it. A mismatch fails
  silently — no error, no log.
- Handshake is Noise IK (Curve25519 + ChaCha20-Poly1305 + BLAKE2s). Sessions rekey ~2 min and
  are rejected after 3 min. Per-packet authentication means peers roam between networks with
  no reconnection.
- **UDP only, no TCP fallback.** If UDP 51820 is blocked anywhere, nothing comes up and there
  is no diagnostic signal — which is why the DMZ was verified for UDP, not inferred from TCP.
- **Throughput is CPU-bound** (software crypto, no offload). `cpu-frequency: auto` in
  `/system/routerboard/settings` costs throughput; pinning to 1400 MHz helps. RB5009 measures
  ~300-900 Mbps real-world, ~1.1-1.4 Gbps in lab conditions.

### Add a peer

```
mikrotik-connect r '/interface wireguard peers add interface=wg-remote public-key="<CLIENT_PUBKEY>" allowed-address=10.99.0.2/32 comment="<device>"'
```

Client config:

```ini
[Interface]
PrivateKey = <client private key>
Address    = 10.99.0.2/24
DNS        = 192.168.5.1

[Peer]
PublicKey  = 2HeIlsYngjfFpCctWpzJyfFCC0+npvliQMzaglf8bGw=
Endpoint   = john2143.com:51820
AllowedIPs = 10.99.0.0/24, 192.168.1.0/24, 192.168.5.0/24, 192.168.6.0/24
PersistentKeepalive = 25
```

Use `AllowedIPs = 0.0.0.0/0` for a full-tunnel config — the existing
`srcnat masquerade out-interface=2GWAN` rule handles internet egress automatically. No NAT is
needed for LAN access: `10.99.0.0/24` is a connected route via `wg-remote`.

### Verify

```
# Listening? How many peers? (0 peers = nothing can connect)
mikrotik-connect r '/interface wireguard print'
mikrotik-connect r '/interface wireguard peers print'

# After adding a peer — the ONLY proof a tunnel is live:
# last-handshake under 2 min, with non-zero rx/tx
mikrotik-connect r '/interface wireguard peers print detail'
```

### Rollback

```
mikrotik-connect r '/ip firewall filter remove [find comment="wireguard remote access"]'
mikrotik-connect r '/interface wireguard remove wg-remote'
mikrotik-connect r '/interface list member remove [find comment="wg-remote tunnel"]'
```

### Gotchas

- **The peer list IS the access control.** The firewall accepts UDP 51820 unconditionally (the
  DMZ hands everything inbound to the router), so only configured public keys are accepted.
  Adding peers requires no firewall change.
- **No IPv6 over the tunnel** until a v6 address is added to `wg-remote`.
- MTU 1420 default; if large transfers stall while small ones work, lower it (~1392).
- `/export` **omits** the private key (only `/export show-sensitive` includes it), so the file
  in `network-configs/` is safe to commit. **`/interface wireguard print detail` DOES print
  it** — avoid that command in shared transcripts.
- The private key was displayed once during the 2026-09-17 build. Rotate with
  `/interface wireguard set wg-remote private-key="<new>"` if that matters.
- RouterOS has a built-in turnkey alternative, **Back To Home VPN** (`/ip cloud`,
  `back-to-home-vpn` — currently `revoked-and-disabled`) — WireGuard-based, configured from
  the MikroTik mobile app, no manual peers.

## NTP / time sync (built 2026-09-18)

All MikroTiks run Eastern time and sync from **public anycast NTP by literal IP** (no DNS
dependency). The iDRAC syncs from the router *and* those same public servers. **No firewall
rule was needed** — the input chain's `drop all not coming from LAN` already covers the LAN,
and the Verizon DMZ forwards all inbound, so NTP is never WAN-exposed.

| Device | Time source | Path |
|---|---|---|
| `r` (router) | `216.239.35.12`, `162.159.200.1` | direct (has WAN) |
| `c` (core, .5.4) | same two IPs | via its **existing default route** |
| `u` (.5.3), `o` (.5.2), `uc` (.5.5) | same two IPs | via two **/32 host routes** (below) |
| iDRAC (.5.254) | `192.168.5.1`, then the two public IPs | Redfish-managed |

Applied to all four switches:

```
/system clock set time-zone-name=America/New_York time-zone-autodetect=no
/system ntp client set enabled=yes servers=216.239.35.12,162.159.200.1
```

`u`, `o` and `uc` have **no default route** (they're L2 switches; adding one would be a bigger
change than the problem warrants), and they have no DNS servers. They therefore carry two
`/32` host routes so they can reach *only* the time servers — nothing else gains a path:

```
/ip route add dst-address=216.239.35.12/32 gateway=192.168.5.1 comment="NTP Google"
/ip route add dst-address=162.159.200.1/32 gateway=192.168.5.1 comment="NTP Cloudflare"
```

Server choice is measured, not guessed: `216.239.35.12` (Google) answers 12/12 and is what every
device actually locked to; `162.159.200.1` (Cloudflare) is flaky on this WAN (2/11 in one
sample, 6/8 in another). **Never use `132.163.96.3` (time.nist.gov)** — 3/8.

### ⚠ The RouterOS NTP server cannot serve RouterOS clients (LI=3)

`/system ntp server` is enabled on the router, but **do not point RouterOS devices at it.** It
advertises **LI=3 ("clock unsynchronized") in every reply, unconditionally** — even with
`use-local-clock=yes` and a demonstrably synchronized upstream. Byte-level decode of its replies
shows everything else correct (Mode 4, right stratum, valid refid, correct timestamps, correctly
echoed originate timestamp); **LI is the only difference from a working server.** RouterOS's own
NTP client discards LI=3 and sits at `status: waiting` **forever**, while the identical client
syncs from Google in ~30 s.

Isolated proof: with `o`'s clock set to within 2 s of true UTC it *still* never synced from the
router — killing the "the clock is too far off to step" theory — and then synced from Google in
under 30 s with no other change. The lesson generalizes: **RouterOS NTP server → RouterOS NTP
client does not work.** Use public NTP (or a real NTP daemon elsewhere) for RouterOS clients.

Non-RouterOS clients are unaffected: the iDRAC polls the router happily (12/12 replies) and was
corrected by whichever source it accepted, so the router's NTP server stays enabled for that.

### iDRAC (Dell PowerEdge R740, iDRAC9 `7.00.00.181`)

Time/NTP lives in Redfish attributes, not a CLI. `PATCH`
`/redfish/v1/Managers/iDRAC.Embedded.1/Attributes` with:

```
Time.1.Timezone            = EST5EDT          (was CST6CDT)
NTPConfigGroup.1.NTPEnable = Enabled          (was Disabled)
NTPConfigGroup.1.NTP1      = 192.168.5.1
NTPConfigGroup.1.NTP2      = 216.239.35.12
NTPConfigGroup.1.NTP3      = 162.159.200.1
```

One PATCH is enough; it takes effect in well under a minute with **no host reboot and no iDRAC
reset**. Value quirks: the attribute registry enumerates `NTPEnable` as `0`/`1` while the
resource renders `Disabled`/`Enabled` — `"Enabled"` is accepted. `Time.1.Timezone` has **no enum
in the registry at all**; the POSIX form works (`EST5EDT`). Verify with
`GET /redfish/v1/Managers/iDRAC.Embedded.1` → `DateTime` should track UTC and
`DateTimeLocalOffset` should be `-04:00`.

The iDRAC root password is **deliberately not stored in this repo** — prompt for it at run time,
and never pass it as a command-line argument (it lands in shell history and `ps`).

### Verify

```
for a in r c u o uc; do mikrotik-connect $a '/system clock print' | grep -E "date:|time:"; done
for a in c u o uc; do mikrotik-connect $a '/system ntp client print' | grep -E "status|synced-server"; done
date -u +"%Y-%m-%d %H:%M UTC"     # every device must agree with this within ~2s
```

Expect `status: synchronized` on all four switches, `gmt-offset: -04:00`, `dst-active: yes`.
**A switch reboot leaves the clock wrong until NTP re-syncs** (no reliable free-running clock) —
re-check `status` after any power loss rather than treating it as a new fault. The `/32` routes
are in each device's export, so restoring from `network-configs/` restores time sync too.

## Subnet Layout

```
192.168.0.0/24  — 2GWAN (upstream ISP via Verizon, DHCP from 192.168.0.1)
192.168.1.0/24  — bridge (main LAN, router at .1) — cameras + reserved
192.168.5.0/24  — bridge (switch LAN, router at .1) — general devices + IoT
192.168.88.0/24 — bridge (legacy factory-default, router at .254, unused)
192.168.6.0/24  — MetalLB v4 LB pool (`services` IPAddressPool), BGP /32s, NOT a bridge subnet
fd00:1::/64     — node ULA (SLAAC on bridge, router .1) — all k3s nodes
fd00:6::/64     — MetalLB v6 LB pool (`services` IPAddressPool), BGP /128s, NOT a bridge subnet
10.99.0.0/24    — wg-remote WireGuard tunnel subnet (router at .1, peers from .2)
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
- **iDRAC (confirmed 2026-09-18):** Dell **PowerEdge R740** BMC at `192.168.5.254` — iDRAC9 fw `7.00.00.181`, Redfish 1.17.0, MAC `2C:EA:7F:7B:12:75` (Dell OUI, same block as bigp), static `/24` with gateway `192.168.5.1`. This is the R740's own BMC, not another host's iDRAC. Time/NTP is managed over Redfish — see **NTP / time sync**.
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

**Control plane:** 3-node HA (closet, arch, nas) with embedded etcd. **MetalLB** (BGP + frr-k8s, since 2026-08-04) announces the API VIP `192.168.5.10` (Service `kubernetes-api` + custom EndpointSlice over closet/arch/nas, port 6443) and all LoadBalancer service IPs from the dual-stack `services` pool (`192.168.6.0/24` + `fd00:6::/64`). **Dual-stack** (IPv4 + IPv6) with static ULA addresses (`fd00:1::/64`) for stable node-ip.
Agents: office (.209, wifi — never a BGP speaker), pite (.9), big (.68, NixOS VM on bigp, joined 2026-07-29) — 6 nodes total.

Pod network: `10.42.0.0/16` (IPv4) + `fd42:42:42::/56` (IPv6) flannel VXLAN. Key services (LB IPs are MetalLB-announced; v6 twins live since 2026-08-13):

| Service | Type | External IP (v4) | External IP (v6) | Notes |
|---------|------|------------------|------------------|-------|
| kubernetes-api | LoadBalancer | 192.168.5.10:6443 | — (v4-only by design) | k3s API (MetalLB, custom EndpointSlice) |
| traefik | LoadBalancer | 192.168.6.11 | fd00:6::10 (manual annotate) | HTTP/HTTPS ingress |
| stalwart | LoadBalancer | 192.168.6.13 | fd00:6::13 | SMTP/IMAP (25/587/993) |
| unifi-inform | LoadBalancer | 192.168.6.10:8080 | fd00:6::30 | UniFi device adoption |
| unifi-discovery | LoadBalancer | 192.168.6.12:10001/UDP | fd00:6::12 | UniFi L2 discovery |
| unifi-web | LoadBalancer | 192.168.6.25:8443 | fd00:6::25 | UniFi controller web UI |
| ts-voice | LoadBalancer | 192.168.6.15:9987/UDP | fd00:6::15 | Teamspeak voice |
| ts-files | LoadBalancer | 192.168.6.16:30033 | fd00:6::16 | Teamspeak file transfer |
| openrct2-game | LoadBalancer | 192.168.6.17:11753 | fd00:6::17 | OpenRCT2 |
| headscale-stun | LoadBalancer | 192.168.6.18:3478/UDP | fd00:6::18 | STUN for Headscale DERP |
| mosquitto | LoadBalancer | 192.168.6.19:1883 | fd00:6::19 | MQTT |
| temporal-frontend | LoadBalancer | 192.168.6.20:7233 | — (v4-only, chart limitation) | Temporal gRPC |
| coturn (steam-lobby) | LoadBalancer | 192.168.6.14:3478 + 45000-45063/UDP | fd00:6::14 | TURN for steam-lobby — **live**, 41d, 1/1, `coturn-wan-ip-watcher` cronjob every 5m |
| coturn (matrix) | LoadBalancer | 192.168.6.21:3478 + 49152-49215/UDP | fd00:6::21 | TURN for matrix — **live**. Relay range has no dst-nat rule (see above) |
| livekit | LoadBalancer | 192.168.6.22:7881 + 50000/UDP | fd00:6::22 | LiveKit RTC, ns `matrix` — **live**, 74d, 1/1. Only `50000/UDP`, not a range |
| frigate | LoadBalancer | 192.168.6.26:5000,1984,8554,8555/UDP | fd00:6::26 | cameras |
| pihole-dns | LoadBalancer | 192.168.6.27:53 UDP+TCP | — | LAN DNS |
| factorio-game | LoadBalancer | 192.168.6.28:34197/UDP | fd00:6::28 | Factorio |
| mimir-lb | LoadBalancer | 192.168.6.23:8080 | fd00:6::23 | Mimir push/query (LAN-only) |
| loki-push-lb | LoadBalancer | 192.168.6.24:3100 | fd00:6::24 | Loki push (LAN-only) |
| minecraft-game | NodePort | :32565/TCP | — | Minecraft (unchanged, nodePort path) |

Query live: `ssh closet 'kubectl get nodes,pods,svc -A'`

## Traffic Flow & Access Logs

For "who is talking to what" questions the source of truth is **Traefik's access log**, shipped to
Loki by Alloy. **`kubectl logs` is useless for this** — the access log rotates within seconds
(`--tail=20000` returned only 18 s of history when measured 2026-09-21), so it cannot answer "what
hit this service 20 minutes ago".

**Query Loki directly over the LAN. No port-forward needed.** The Service is named `loki-push-lb`,
but its selector is actually the Loki **gateway**, so it answers the full query API:

```
curl -sS -G 'http://192.168.6.24:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="kube-system"} |= "seafile.john2143.com"' \
  --data-urlencode "start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode "end=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode 'limit=200'
```

`loki-push-lb` → `192.168.6.24:3100` (v6 `fd00:6::24`), LAN-only, no dst-nat. That snippet is
**bash** — the interactive shell is fish, so wrap it in `bash -lc '…'`. The interactive equivalent
is Grafana Explore at `https://grafana.john2143.com` — pick the **Loki** datasource (uid `loki`). A
log line's `TraceId` correlates with Tempo, which is wired in as a linked datasource.

### Traffic-flow queries

Start from the base query above and narrow it. The whole log line is one JSON object, so you can
either match a substring or parse it with the `| json` stage — the parser is cleaner and lets you
compare numerically:

```logql
{namespace="kube-system"} |= "seafile.john2143.com"                              # one host
{namespace="kube-system"} |= "/thumbnail/"                                       # one path prefix
{namespace="kube-system"} |= "seafile.john2143.com" | json | DownstreamStatus = 429
{namespace="kube-system"} | json | DownstreamStatus >= 500                       # backend errors
{namespace="kube-system"} | json | ClientHost = `108.28.68.83`                   # one client
```

`DownstreamStatus` is a JSON **number** — compare it unquoted (`= 429`). `ClientHost` is a string —
use backticks or double quotes. Keep queries in a fenced block like the above: a `|` inside a
markdown table cell must be escaped as `\|`, and the escaped-quote substring form
(`|= "\"DownstreamStatus\":429"`) is easy to mangle into something that silently matches nothing.

Then aggregate client-side. Counting by `ClientHost` and `DownstreamStatus` over the returned rows is
what turned a vague "photo browsing is broken" into a precise diagnosis on 2026-09-21 (3 client IPs,
2927 rejections, every one on `GET /thumbnail/…`).

### Useful access-log fields

| field | meaning |
|---|---|
| `ClientHost` | client IP — see the NAT caveat below |
| `DownstreamStatus` | status returned to the client — count this one |
| `OriginStatus` | status from the backend; differs when a middleware rewrote the answer |
| `RequestPath`, `RequestMethod`, `RequestHost` | what was asked for |
| `Duration` | nanoseconds (seconds ×1e9) |
| `RouterName`, `ServiceName` | Traefik router that matched; embeds `httproute-<ns>-<name>-gw-<gateway>…`, mapping the line back to the exact HTTPRoute |
| `StartUTC` | request start (UTC) |
| `RequestCount` | **cumulative process counter, not a per-request count** — never sum it |

### Why a client IP may look wrong

`ClientHost` is the **real client IP for remote clients** — a phone on a VPN appears under its own
address, and each such client gets its own rate-limit bucket. **LAN clients are the exception:**
hairpin NAT presents every device at home to Traefik as the WAN IP `108.56.153.222`, so they share
one bucket. That is exactly why `108.56.153.222` is listed explicitly in the bouncer's
`clientTrustedIps` — do not read "all my devices share one public IP" as a fault.

### Rate-limit rejections are `429`, not `403`

Traefik's `rateLimit` and `inFlightReq` middlewares **both answer `429`**, and the log cannot tell you
which one rejected a request — check the route's middleware chain
(`ssh closet 'kubectl get httproute <name> -n <ns> -o yaml'`; name the namespace explicitly, per
triage rule 11). CrowdSec bans appear as `403`; a `429` is never CrowdSec.

Loki's `max_entries_limit_per_query` is **5000** — narrow the window or paginate instead of raising
`limit`.

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

MetalLB (v0.16.1, frr-k8s) announces the k3s API VIP `192.168.5.10` and every LoadBalancer service IP via BGP to the MikroTik (AS 65001). **Dual-stack since 2026-08-13**: the `services` IPAddressPool carries both `192.168.6.0/24` (announced as /32s) and `fd00:6::/64` (announced as /128s). frr-k8s runs one FRR daemon per node; every **speaker node** advertises **all** service prefixes — no leader lease, no loopback VIP. The router installs each /32 or /128 with 5 next-hops (one active path, the rest as failover backups — RouterOS 7.19 picks a single active path, not ECMP). Traffic lands on the node with the active route, and kube-proxy DNATs it to the service's endpoints. The BGPPeer has `dualStackAddressFamily: true` (`argo/workloads/metallb/bgppeer.yaml`) — without it frr-k8s renders `ipv6 prefix-list … deny any` and never advertises v6 even after the router negotiates both AFIs. RouterOS side: both the default template AND each `metallb-*` connection carry `afi=ip,ipv6` — the template change alone is NOT enough on 7.19.6 (sessions keep `local.afi=ip` until each connection is set directly).

### Topology

```
MetalLB speakers (AS 65000, hostNetwork, port 179)
  arch    (192.168.5.76)   ──┐
  closet  (192.168.5.36)   ──┼── BGP peering ── MikroTik (AS 65001, 192.168.5.1)
  nas     (192.168.5.175)  ──┤
  big     (192.168.5.68)   ──┤
  pite    (192.168.5.9)    ──┘
office (.209) is wifi — intentionally NOT a speaker.

```
Each speaker advertises every allocated /32 (v4: .5.10 API VIP + all .6.x LB IPs) and /128 (v6: fd00:6::X LB IPs).
### Live Status

```bash
# MetalLB's view of the 5 sessions (all should be Established):
ssh closet.local 'kubectl get bgpsessionstates -n metallb-system'

# Router's view (5 lines with E flag, names ~"metallb*"):
mikrotik-connect r '/routing bgp session print'

# A service route (5 gateways, one active DAb) — v4 and v6:
mikrotik-connect r '/ip route print where dst-address=192.168.6.11/32'
mikrotik-connect r '/ipv6 route print where dst-address=fd00:6::13/128'

# FRR's own view (per node):
kubectl --context closet-as-developer exec -n metallb-system ds/metallb-frr-k8s -c frr -- vtysh -c 'show bgp summary'

# Current allocations (both families):
ssh closet.local 'kubectl get svc -A | grep -E "192.168.6|fd00:6"'
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
disaster recovery. Files are named per device — `router.rsc`, `router.verbose.rsc`,
`core.rsc`, `upstairs.rsc`, `office.rsc`, `upstairs-core.rsc` (each with a `.verbose.rsc`
twin). **Git tracks history, so there are no dates in the filenames — and there is no
`mikrotik-export-*.rsc`.** Last refreshed: **2026-09-17** (router only; the switches date
from 2026-06-14).

**`/export` omits sensitive values** — WireGuard private keys, passwords, etc. appear only
under `/export show-sensitive`. The committed files are therefore safe; never add
`show-sensitive` to the backup commands.

Writing these files touches the dotfiles repo outside the current working directory — only do
it when the user asks.

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
11. **Query ALL namespaces, never just `-n default`.** On 2026-09-17 `.6.14` looked like a dead target from `kubectl get deploy -n default`, but it is `steam-lobby/coturn` — live, 41 days, `1/1`, with a 5-minute cronjob. Workloads live in `matrix`, `steam-lobby`, `observability`, `stalwart`, `argo`, etc. Run `kubectl get svc,pods,deploy -A` before declaring any NAT target dead or service dormant.
12. **`<host>.local` may not resolve** (mDNS). The examples use `closet.local`; if that fails, use `ssh 192.168.5.36` (or bare `ssh closet`). Same for `arch.local`, `nas.local`.
13. **Prove inbound WAN reachability without an external host.** From any LAN machine, drive external probes at the public IP (`/ip cloud print` → `public-address`) and catch the arrival in the router's own conntrack:
    - TCP: `curl -s -H 'Accept: application/json' 'https://check-host.net/check-tcp?host=<pubip>:<port>&max_nodes=5'`, then poll `https://check-host.net/check-result/<request_id>`.
    - UDP: `check-udp` — **its verdicts are useless** (it reports `timeout` even for ports known to be live), but the packets it sends are real. Fire a burst, then poll `mikrotik-connect r '/ip firewall connection print terse where dst-address~":<port>"'` and correlate source IPs against the check-host nodes via `socket.gethostbyname`.
    - Lone UDP conntrack entries expire in ~30 s: fire the burst and poll **concurrently**.
    - This is how the DMZ was proven to forward UDP (263 external packets landed on `192.168.0.2:51820`) — and how the DNAT hijack was caught (all of them arriving at `.6.14` beforehand).
14. **A failed external `ping` to the public IP means NOTHING.** ICMP to `108.56.153.222` is filtered upstream — TIMEOUT / DEST_UNREACH from every external node — while TCP 80/443/993 and UDP both pass. Never conclude "the WAN path is broken" from a failed ping.

## Safety

- All RouterOS commands through this skill are **read-only** (`print`, `export` without `file=`, `monitor`, `get`).
- **NEVER** run add/remove/set/enable/disable/move/reset/reboot/shutdown without explicit user approval.
- **NEVER** run `nixos-rebuild switch` or `home-manager switch` without explicit user approval.
- When in doubt whether a command is read-only, show it to the user and ask.
- `export file=...` writes to device flash — it IS mutating.
- UniFi API writes (POST/PUT/DELETE beyond `/api/login`) mutate controller state. Only use read-only GET endpoints unless the user explicitly asks for configuration changes.
