# Home Network Topology — Full Analysis

> Live snapshot: 2026-05-23. All data from live MikroTik queries cross-referenced with NixOS configs in `~/dotfiles`.

---

## Layer 0: Physical — Routers, Switches, Access Points

```
Internet (Verizon FiOS)
    │
    ▼
┌─────────────────────────────────────────────┐
│  Verizon CR1000A (192.168.0.1)             │
│  - DMZ → 192.168.0.2 (MikroTik)            │
│  - Port forward 6767 → 192.168.0.154       │
│  - Serves DHCP on 192.168.0.0/24            │
└──────┬──────────────┬───────────────────────┘
       │              │
       ▼              ▼
  192.168.0.2    192.168.0.154
  (MikroTik      (home-pi — Raspberry Pi
   WAN static)    Headscale + PowerDNS)
   + .152 DHCP

       │ MikroTik CRS310-8G+2S+IN (192.168.1.1, 5.1)
       │ RouterOS, routes all internal subnets
       │
       ├─── 10GbE SFP+ ────┬─── Upstairs switch (192.168.5.3)
       │                    │    CRS310-8G+2S+IN
       │                    │    Ports active: ether1,2,8, sfp-sfpplus1,2
       │                    │      sfp-sfpplus1 → U7 Pro XGS (10GbE)
       │                    │      sfp-sfpplus2 → (inter-switch or host)
       │                    │      ether8 → (host)
       │                    │
       │                    ├─── Downstairs switch (192.168.5.2)
       │                    │    CRS310-8G+2S+IN
       │                    │    Ports active: ether5,7, sfp-sfpplus1,2
       │                    │      ether5 → U7 Lite (1GbE)
       │                    │      ether7 → (security camera?)
       │                    │      sfp-sfpplus1,2 → (inter-switch or hosts)
       │                    │
       │                    └─── Bridge LAN (192.168.5.0/24, 1.0/24)
       │
       ├─── UniFi U7 Pro XGS AP (192.168.5.171)
       │     WiFi 7 tri-band: 2.4 / 5 / 6 GHz
       │     10GbE SFP+ uplink via upstairs switch
       │     Hostname: U7ProXGSOffice
       │
       ├─── UniFi U7 Lite AP (192.168.5.173)
       │     WiFi 7 dual-band: 2.4 / 5 GHz
       │     1GbE uplink via downstairs switch
       │     Hostname: U7LiteBlueRoom
       │
       └─── UniFi Controller (k3s on closet:30443)
             Web UI: https://192.168.5.35:30443
```

---

## Layer 1: IP Addressing & Subnets

### Router Interfaces

| Interface | IP Addresses | Subnet | Source | Purpose |
|-----------|-------------|--------|--------|---------|
| 2GWAN | 192.168.0.2/24 | 0.0/24 | Static | Primary WAN, Verizon DMZ target |
| 2GWAN | 192.168.0.152/24 | 0.0/24 | DHCP | Secondary WAN IP |
| bridge | 192.168.5.1/24 | 5.0/24 | Static | Main LAN gateway |
| bridge | 192.168.1.1/24 | 1.0/24 | Static | Camera subnet gateway |
| bridge | 192.168.88.254/24 | 88.0/24 | Static | Legacy default (unused) |

Interface-list membership: `LAN = bridge`, `WAN = 2GWAN`

### Subnet Layout

```
192.168.0.0/24  — WAN (Verizon upstream). Router at .1 (Verizon), MikroTik at .2 + .152 (DHCP)
                  home-pi at .154. Direct Verizon DHCP, no MikroTik NAT.
192.168.1.0/24  — Camera subnet (bridge). Router at .1. WAN egress blocked via firewall.
192.168.5.0/24  — General devices (bridge). Router at .1. Everything else.
192.168.88.0/24 — Legacy factory-default (bridge). Router at .254. Unused.
10.42.0.0/24    — k3s flannel pod network (on cluster nodes)
100.64.0.0/10   — Tailscale tailnet (on TS-connected devices)
```

All bridge subnets (1.0/24, 5.0/24, 88.0/24) route to each other without NAT.

### Routes

```
0.0.0.0/0         → 192.168.0.1 (Verizon)     default route
192.168.0.0/24    → 2GWAN (connected)          WAN subnet
192.168.1.0/24    → bridge (connected)         camera subnet
192.168.5.0/24    → bridge (connected)         main LAN
192.168.88.0/24   → bridge (connected)         legacy subnet
```

---

## Layer 2: Device Inventory

### NixOS Hosts (managed via `nh os switch .` from ~/dotfiles)

| Hostname | IP(s) | MAC | Role | Hardware |
|----------|-------|-----|------|----------|
| **office** | 192.168.5.209 (DHCP) | C4:3D:1A:F3:0E:76 | Primary workstation, k3s agent, vLLM GPU | i9-14900K, 64GB, RX 7900 XT, 2.5GbE |
| **arch** | 192.168.5.226 (DHCP) | 70:85:C2:A5:07:CC | GenAI workstation, k3s agent, ollama/vllm | i9-9900K, 31GB, GTX 1080 Ti |
| **closet** | 192.168.5.35 (static) + 192.168.5.202 (DHCP secondary) | 40:B0:76:D9:69:92 | k3s server (control-plane), Longhorn, UniFi | Ryzen 5 1600, 7.7GB, 4TB USB SSD |
| **nas** | 192.168.5.175 + .176 (DHCP, dual NIC) | E8:4D:D0:C1:54:20 + 90:2B:34:DB:6D:7D | ZFS file server, atticd, k3s+Longhorn | i7-3770K, 15GB, 4x8TB ZFS RAIDZ1, 10GbE SFP+ |
| **secu** | 192.168.5.140 (DHCP) | 00:13:EF:F2:A0:BF | Camera NVR (FDE) | HP EliteDesk 800 G3, i5-6500T, 7.6GB |
| **pite** | 192.168.5.213 (DHCP) | DC:A6:32:0C:FE:5C | k3s agent, canary honeytoken | Raspberry Pi 4B, 1.8GB, 238GB SD |
| **vpin** | 192.168.5.252 (DHCP) | DC:A6:32:25:51:6E | Mullvad exit node | Raspberry Pi (3?), 3.7GB, 59.5GB SD |
| **aman** | DHCP (Tailscale only) | — | Mullvad exit node, Avahi reflector | Raspberry Pi 4B, 3.7GB, 238GB SD |
| **home-pi** | 192.168.0.154 (DHCP, WAN subnet) | DC:A6:32:30:2D:38 | Headscale server, PowerDNS | Raspberry Pi (aarch64) |

**closet dual-IP note:** Static .35 is the permanent ARP entry and k3s node IP. DHCP .202 is a secondary dynamic address on the same interface — likely from NetworkManager or dhcpcd running alongside the static config.

### Cameras (Reolink ONVIF/RTSP)

All on 192.168.1.0/24 (dedicated camera subnet). WAN egress blocked. NVR handled by secu (.140).

| Camera | IP | Connection | MAC | Status |
|--------|-----|-----------|-----|--------|
| Back yard | 192.168.1.60 | WiFi, static | 78:93:C3:8E:34:9F | ARP reachable (back online) |
| Garage | 192.168.1.61 | WiFi, static | EC:71:DB:F4:DC:49 | DHCP bound + ARP |
| Front porch | 192.168.1.63 | Wired, static | EC:71:DB:89:D8:8B | DHCP bound + ARP |
| Front Gate | 192.168.1.64 | Wired, static | EC:71:DB:65:58:A3 | DHCP bound + ARP |
| Side yard | 192.168.1.65 | WiFi, DHCP resv | 94:B3:F7:18:52:CC | DHCP bound + ARP |
| Front Driveway | 192.168.1.66 | Wired, DHCP resv | EC:71:DB:3E:2F:21 | DHCP bound + ARP |
| Reolink NVR | 192.168.1.67 | Wired, DHCP resv | EC:71:DB:8B:92:93 | DHCP bound + ARP |

All 7 cameras online (back yard recently returned — was previously `offered` only).

### IoT & Smart Home (192.168.5.0/24)

| Device | IP | MAC | Notes |
|--------|-----|-----|-------|
| JetKVM | .187 | 30:52:53:09:E1:72 | Server KVM over IP, hostname: serverkvm |
| AiDot light 1 | .164 | D0:CF:13:8C:6D:74 | Smart bulb |
| AiDot light 2 | .166 | D0:CF:13:8C:08:6C | Smart bulb |
| AiDot light 3 | .167 | D0:CF:13:8C:5F:18 | Smart bulb |
| AiDot light 4 | .168 | D0:CF:13:8D:4E:28 | Smart bulb |
| WiZ light | .132 | D8:A0:11:79:F1:3C | Hostname: wiz_79f13c |
| Akamatis sensor 1 | .170 | 94:A9:90:6C:70:88 | mmWave presence (hostname: akamatis-presence-sensor-6c7088) |
| Akamatis sensor 2 | .165 | 80:F1:B2:52:F0:C8 | mmWave presence (hostname: akamatis-presence-sensor-52f0c8) |
| K3B-US-PGA0539A | .127 | C8:FF:77:57:E0:3D | Unknown device type |
| Linux ARM device | .147 | B0:FC:0D:DE:FB:50 | armv7l, Linux 3.18.19, dhcpcd |
| Unknown | .172 | 00:07:A6:40:E7:4B | No hostname or client-id |
| Static IP device | .8 | 94:83:C4:C4:9C:4D | ARP reachable, not in DHCP |

### 00:07:A6:40:E7:4B OUI lookup

MAC prefix `00:07:A6` = **Eutron S.p.A.** (Italian industrial/security equipment manufacturer). Device at .172 — no hostname, no client-id. Possibly an alarm panel or industrial controller.

### Transient Devices (rotating MACs)

| Device | IP | MAC | Notes |
|--------|-----|-----|-------|
| Android phone | .146 | 54:49:DF:12:BF:49 | android-dhcp-10 |
| MacBook Pro | .141 | B6:2E:51:C1:93:5B | Hostname: MacBookPro |
| iPhone #1 | .136 | B2:81:41:91:B6:92 | Hostname: iPhone |
| iPhone #2 | .126 | BE:B2:F3:CD:84:C3 | Hostname: iPhone |
| pop-os | .221 | D4:D8:53:A7:6A:B1 | NEW — System76 laptop, hostname: pop-os |

### Infrastructure Devices

| Device | IP | MAC | Notes |
|--------|-----|-----|-------|
| U7 Pro XGS AP | .171 | 90:41:B2:D6:74:DB | WiFi 7 AP, 10GbE uplink, hostname: U7ProXGSOffice |
| U7 Lite AP | .173 | 1C:0B:8B:50:FF:7E | WiFi 7 AP, 1GbE uplink, hostname: U7LiteBlueRoom |
| Upstairs switch | 192.168.5.3 | 04:F4:1C:E6:7C:0C | CRS310-8G+2S+IN |
| Downstairs switch | 192.168.5.2 | 04:F4:1C:E7:24:3C | CRS310-8G+2S+IN |
| Verizon router | 192.168.0.1 | 74:90:BC:79:0A:A4 | CR1000A, upstream gateway |

---

## Layer 3: NAT & Port Forwarding

### Source NAT (masquerade)

```
Rule 9:  chain=srcnat action=masquerade dst-address=!192.168.0.0/24 out-interface=2GWAN
         → Masquerade all outbound traffic EXCEPT to WAN subnet

Rule 11: chain=srcnat action=masquerade src-address=192.168.0.0/16 dst-address=192.168.5.35 out-interface=bridge
         → Hairpin NAT srcnat for loopback access
```

### Destination NAT (port forwards — live from MikroTik, 2026-05-23)

| WAN Port | Proto | MikroTik Target | Final Target | k8s NodePort | Service |
|----------|-------|-----------------|--------------|-------------|---------|
| 80 | TCP | closet:80 | traefik LB | 31316 | HTTP ingress |
| 443 | TCP | closet:443 | traefik LB | 30908 | HTTPS ingress |
| 9987 | UDP | closet:30087 | ts-voice:30087 | 30087 | Teamspeak voice |
| 30033 | TCP | closet:30034 | ts-files:30034 | 30034 | Teamspeak file transfer |
| 5432 | TCP | closet:5432 | CNPG Postgres | (ClusterIP) | PostgreSQL |
| 5999 | TCP | closet:5432 | CNPG Postgres | (ClusterIP) | PostgreSQL (alt) |
| 25565 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft Java |
| 32565 | TCP | nas:32565 | minecraft-game:32565 | 32565 | Minecraft (alt) |
| 11753 | TCP | closet:31753 | openrct2-game:31753 | 31753 | OpenRCT2 |
| 30478 | UDP | closet:30478 | headscale-stun:30478 | 30478 | Headscale STUN |
| 18080 | TCP | arch:18080 | Monero P2P node | (host) | Monero |
| — | — | 173.66.223.59 → 192.168.5.35 | Hairpin NAT | — | LAN→WAN→LAN |

### Verizon Router Port Forward (not queryable — documented from config)

| WAN Port | Proto | Target | Service |
|----------|-------|--------|---------|
| 6767 | TCP+UDP | home-pi:6767 (192.168.0.154) | Headscale control |

**Note:** Verizon DMZ sends all other inbound traffic to 192.168.0.2 (MikroTik). The explicit 6767 forward takes precedence over DMZ for that port. home-pi is on the WAN subnet, not behind MikroTik NAT.

### Firewall Input Rules

```
0: accept established,related,untracked
1: drop invalid
2: accept ICMP
3: accept dst=127.0.0.1 (CAPsMAN local)
4: drop all not from LAN interface-list
```

Router accepts management only from LAN. WAN-side attacks blocked at rule 4.

---

## Layer 4: k3s Cluster

**Server:** closet (192.168.5.35) — control-plane  
**Agents:** arch (.226), nas (.175), office (.209), pite (.213)  
**Total nodes:** 5 (all Ready, v1.35.4+k3s1 except pite at v1.35.2)

### Pod Network

```
10.42.0.0/24 — flannel VXLAN overlay (cni0 bridge)
  closet: 10.42.0.0/32 (flannel.1), 10.42.0.1/24 (cni0 gateway)
```

### Key k3s Services

| Service | Type | External IP / NodePort | Notes |
|---------|------|----------------------|-------|
| traefik | LoadBalancer | 192.168.5.35, .226, .175, .209, .213 | HTTP:31316, HTTPS:30908 |
| unifi-web | NodePort | :30443 | UniFi controller web UI |
| unifi-inform | LoadBalancer | :8080 (closet, arch, nas) | UniFi device adoption |
| unifi-discovery | LoadBalancer | :10001/UDP (closet, arch, nas) | UniFi L2 discovery |
| ts-voice | NodePort | :30087/UDP | Teamspeak voice |
| ts-files | NodePort | :30034/TCP | Teamspeak file transfer |
| minecraft-game | NodePort | :32565/TCP | Minecraft |
| openrct2-game | NodePort | :31753/TCP | OpenRCT2 |
| headscale-stun | NodePort | :30478/UDP | STUN for Headscale DERP |

---

## Layer 5: Tailscale / Headscale

### Headscale Server

**home-pi** (192.168.0.154), domain `headscale.9s.pics` → home public IP → Verizon port forward 6767.

- URL: `https://headscale.9s.pics:6767`
- DNS: PowerDNS on same host (authoritative for `ts.9s.pics` zone, uses CNPG PostgreSQL on k3s-ashburn)
- STUN: DERP relay via closet:30478 (NodePort)

### Known Tailnet Nodes

| Node | Tailscale IP | Role |
|------|------------|------|
| home-pi | (self) | Headscale server |
| closet | 100.64.0.2 | k3s server |
| aman | (DHCP) | Mullvad exit node, Avahi reflector |
| k3s-ashburn | (Hetzner) | k3s server + PostgreSQL |
| k3s-hillsboro | (Hetzner) | k3s server + PostgreSQL |
| k3s-nuremberg | (Hetzner) | k3s server + PostgreSQL |
| k3s-*-agent | (Hetzner) | k3s agents (on-demand) |

---

## Layer 6: DNS

| Role | Server | Zone |
|------|--------|------|
| Public DNS | External provider | john2143.com, net.2143.me → home public IP |
| Tailnet DNS | home-pi (PowerDNS) | ts.9s.pics (authoritative) |
| LAN DNS | MikroTik (static entry only) | router.lan → 192.168.5.1 |
| mDNS/Avahi | aman (reflector) | .local across subnets |

---

## Layer 7: Services & Ports

### Externally Reachable

| Service | Host | External URL / IP | Internal Target |
|---------|------|-------------------|----------------|
| HTTP/HTTPS | traefik (k3s LB) | john2143.com:80,443 | closet:80,443 → traefik LB:31316,30908 |
| Headscale | home-pi | headscale.9s.pics:6767 | home-pi:6767 (Verizon forward) |
| Teamspeak voice | k3s ts-voice | john2143.com:9987 (UDP) | closet:30087 |
| Teamspeak files | k3s ts-files | john2143.com:30033 (TCP) | closet:30034 |
| PostgreSQL | k3s CNPG | (WAN IP):5432,5999 | closet:5432 |
| Minecraft | k3s minecraft | (WAN IP):25565,32565 | nas:32565 |
| OpenRCT2 | k3s openrct2 | (WAN IP):11753 | closet:31753 |
| Monero P2P | arch | (WAN IP):18080 | arch:18080 |

### Internal Services (LAN/VPN only)

| Service | Host | URL |
|---------|------|-----|
| k3s API | closet | https://192.168.5.35:6443 |
| Attic Nix cache | nas | http://nas:8280 |
| ArgoCD | k3s-ashburn (Tailscale) | https://argocd.ts.2143.me |
| Home Assistant | (TBD) | https://home.ts.2143.me |
| UniFi Controller | closet (k3s) | https://192.168.5.35:30443 |
| RustFS (S3) | (TBD) | https://files.john2143.com |

---

## Summary Metrics (2026-05-23)

| Metric | Count |
|--------|-------|
| Online hosts (DHCP bound) | 32 |
| ARP-reachable devices | 21 (bridge) + 2 (WAN) |
| NixOS hosts | 9 (8 local + 1 WAN-side home-pi) |
| Cameras online | 7 of 7 |
| IoT/smart devices | 11 |
| k3s nodes | 5 (all Ready) |
| Switch ports active | 6 upstairs, 4 downstairs |
| MikroTik dst-nat rules | 11 |
| External services exposed | 9 |

---

## Notable Observations

1. **closet dual IP (.35 + .202):** Static primary + DHCP secondary on same interface. The static is the ARP permanent entry used by k3s. The DHCP secondary is a dhcpcd/NetworkManager artifact — harmless but worth cleaning up if not intentional.

2. **MikroTik dual WAN IP (.2 + .152):** Static .2 is the Verizon DMZ target. DHCP .152 is a secondary address on the same WAN interface — possibly a legacy config or used for a specific port forward via Verizon.

3. **home-pi on WAN subnet:** Connected directly to Verizon router, not behind MikroTik NAT. Headscale traffic bypasses the MikroTik entirely (Verizon port forward → home-pi directly). This means home-pi cannot reach LAN devices unless it has Tailscale routes.

4. **Unknown device .172 (00:07:A6:40:E7:4B):** MAC prefix is Eutron S.p.A. — Italian security/industrial equipment. No hostname or client-id. Worth investigating physically.

5. **pop-os .221:** New device not previously documented. System76 laptop running Pop!_OS.

6. **Back yard camera .60 back online:** Previously showed `offered` status (intermittent). Now ARP-reachable with static IP. WiFi signal may have improved or camera was power-cycled.

7. **No MikroTik dst-nat for 6767:** Confirmed — Headscale port forward is entirely on the Verizon router. The MikroTik does not participate in Headscale traffic routing.

8. **k3s pod network uses flannel:** 10.42.0.0/24 overlay with VXLAN. Nodes communicate via their bridge IPs (192.168.5.x) for pod-to-pod traffic.
