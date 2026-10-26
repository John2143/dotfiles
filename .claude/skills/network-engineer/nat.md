# NAT, WAN and port forwarding

Everything inbound from the internet. Live state is authoritative — read it before changing
anything:

```
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
```

## The two-NAT path

```
Internet → Verizon CR1000B (192.168.0.1) → per-port forward → MikroTik WAN 192.168.0.2
                                                                 → dst-nat → cluster VIP or host
```

The Verizon router is **not** a DMZ: it forwards only the ports listed below. **Every new WAN
service needs a forward on the Verizon router as well as a MikroTik dst-nat** — one without the
other fails silently, with no conntrack entry at the MikroTik.

| Property | Value |
|---|---|
| Model / firmware | CR1000B / 3.6.0.2_BD |
| LAN | 192.168.0.1/24, DHCP pool .100-.169 |
| WAN | DHCP from ISP |
| IPv6 | DHCPv6-PD; delegated prefix and LAN prefix change on renumber — re-read the admin panel |

Verizon forwards (all to `192.168.0.2` unless noted): 80, 443, 25, 587, 993, 3478, 3479, 7881,
9987, 11753, 18080, 25565, 30033, 34197, 45000-45063, 51820, 8280 → home-pi (192.168.0.154).
Anything not in that list never arrives, no matter what the MikroTik says.

## dst-nat table

| WAN port | Proto | Target | Service |
|---|---|---|---|
| 80, 443 | TCP | `.6.6` (traefik) | ingress; kept current by the router script `ingress-follow` |
| 25, 587, 993 | TCP | `.6.13` | stalwart |
| 3478 | TCP+UDP | `.6.14` | coturn (steam-lobby) |
| 45000-45063 | UDP | `.6.14` | coturn relay |
| 3479 | UDP | `.6.18` | headscale STUN (`externalTrafficPolicy: Local`) |
| 7881 | TCP | `.6.22` | livekit signal |
| 9987 | UDP | `.6.15` | TeamSpeak voice |
| 30033 | TCP | `.6.16` | TeamSpeak files |
| 11753 | TCP | `.6.17` | OpenRCT2 |
| 25565 | TCP | `.6.29` | Minecraft |
| 34197 | UDP | `.6.28` | Factorio |
| 18080 | TCP | `.5.76` | Monero P2P (bare metal) |

`51820/UDP` is **not** dst-nat — WireGuard terminates on the router itself (`wireguard.md`).

LAN-only, no dst-nat: mimir `.6.23:8080`, loki `.6.24:3100`, syslog `.6.25:514/udp`, frigate
`.6.26`, mosquitto `.6.19:1883`, seaweedfs `.6.31:8333` (also reachable from the DO tunnel),
temporal `.6.20:7233`, lan-dns `.6.30:53`, k8s API `.5.10:6443`.

## Rules that prevent self-inflicted outages

- **Check for a covering port range first.** DNAT runs in PREROUTING, *before* the input filter, so
  a wide range steals the packet and a listener on the router never sees it. This is how UDP 51820
  was once silently shadowed.
- **Select rules by exact comment, never by number.** `:put [:len [/ip firewall nat find
  comment="…"]]` must print 1 before any `set`/`remove`.
- RouterOS 7.19 `find`/`where` does **not** match on `dst-port`, `to-ports` or `protocol` — those
  cannot be part of a selector identity.
- Removing a rule does not remove a Verizon forward, and vice versa. Clean up both.
- Known dead Verizon forwards (no matching MikroTik rule): 25555 → 32565. Remove on sight.

## Outbound

```
chain=srcnat action=masquerade out-interface=2GWAN dst-address=!192.168.0.0/24
```

Hairpin NAT was removed (dynamic WAN IP makes it unworkable). LAN clients reach services by
internal address, not by public hostname.
