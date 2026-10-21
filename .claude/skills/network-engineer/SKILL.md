---
description: Home network — MikroTik router and switches, subnets, DHCP, IP config, plus pointers to protocol-specific runbooks
argument-hint: (none — invoked as skill://network-engineer)
allowed-tools: Bash(mikrotik-connect *), Bash(kubectl *), Bash(ssh *), Bash(curl *), Read, Search, Edit
tool-hints: |
  Read-only by default: print / export / monitor / get are fine, add / set / remove / enable /
  disable / reboot need explicit user approval. Verify device identity before operating. Prefer
  live queries over the tables here when the question is about current state.
  kubectl for the home cluster goes through `ssh closet 'kubectl …'` and must use `-A` or an
  explicit namespace, never a bare `-n default` guess.
  This skill may update its own files when the user asks for documentation changes.
---

# Home network

Router, switches, and general IP configuration. Everything protocol-specific lives in a reference
file next to this one — read it before working in that area.

| Area | File |
|---|---|
| Cabling, switch ports, device identity | `topology.md` |
| WAN, port forwarding, destination/source NAT | `nat.md` |
| DNS (public, LAN, split-horizon, tailnet) | `dns.md` |
| WireGuard tunnel to the DO cluster | `wireguard.md` |
| UniFi wireless and controller | `unifi.md` |
| Cameras and recording | `cameras.md` |
| MetalLB, BGP, load-balancer IPs, traffic flow | `k8s-networking.md` |

Paths are relative to `~/dotfiles/.claude/skills/network-engineer/`.

## Access

```
mikrotik-connect <alias> <RouterOS command…>
```

Aliases: `r` router (192.168.5.1), `c` core (.4), `u` upstairs (.3), `o` office (.2),
`uc` upstairs-core (.5). Key auth is materialized from agenix; works from bash and fish.

Before operating on any device, confirm identity — model/serial and RouterOS version are different
commands:

```
mikrotik-connect r '/system routerboard print'
mikrotik-connect r '/system resource print'
```

Serial list is in `topology.md`.

## Subnets

```
192.168.0.0/24   WAN side (Verizon router)
192.168.1.0/24   cameras
192.168.5.0/24   main LAN, switches and servers
192.168.6.0/24   MetalLB v4 pool — not a bridge subnet
192.168.88.0/24  factory-default escape hatch (MikroTik default config)
fd00:1::/64      node ULA, stateful DHCPv6
fd00:6::/64      MetalLB v6 pool
10.99.0.0/24     WireGuard
```

DHCP pool on 5.0/24 is `.50`–`.254`. **Everything below `.50` is statically assignable** — check ARP
for the current holder before taking one. Reservations inside the pool are explicit
(`.127`, `.165`, `.170`).

## Live state

```
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound'
mikrotik-connect r '/ip arp print terse where status=reachable'
mikrotik-connect r '/ip route print terse'
mikrotik-connect r '/ip firewall nat print terse where chain=dstnat'
mikrotik-connect r '/ipv6 address print terse'
```

## Keeping these docs true

The reference files are snapshots. Regenerate the current state with:

```
~/dotfiles/scripts/network-snapshot.sh
```

It prints leases, ARP, routes, dst-nat, IPv6 and BGP as markdown. Diff it against the files here
and update what moved. Router/switch configs themselves are backed up separately — see
`network-configs/check-drift.sh`.

## Rules that prevent wasted hours

1. **Validate paths from outside the system under test.** Cluster nodes DNAT `.6.x` locally, so a
   `curl` from office or big proves nothing about the router's forwarding.
2. **ICMP to a MetalLB VIP always times out** — no interface owns the VIP and kube-proxy only DNATs
   TCP/UDP. A failed ping is expected, not a symptom.
3. **DNAT runs before the input filter.** Before choosing a new WAN port, confirm no dst-nat range
   already covers it, or the packet is silently stolen. See `nat.md`.
4. **Never select rules by number.** Use a unique exact comment, and prove the selector matches one
   row (`:put [:len [find comment="…"]]`) before mutating.
5. **RouterOS 7.19 `find`/`where` ignores port and protocol properties** — they cannot be part of a
   selector identity.
6. **Check both ends before declaring a path broken.** A `syn-sent` in the router's connection table
   means the packet arrived, not that forwarding failed.
7. **A failed external ping to the public IP means nothing** — ICMP is filtered upstream while TCP
   and UDP pass.

## Safety

- Read-only RouterOS operations only (`print`, `export`, `monitor`, `get`). Mutations need approval.
- `export file=…` writes to device flash — that is a mutation.
- Never run `nixos-rebuild switch`, `home-manager switch`, or any `nh` switch.
- If a command's read-only status is unclear, show it and ask.
