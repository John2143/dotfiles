# `.local` names and the router's mDNS repeater

Last updated 2026-11-16.

## Two resolvers, two different names

`nas` and `nas.local` are answered by completely different machinery, which is
why one can work while the other times out:

| Query | Resolver | Answer |
|---|---|---|
| `nas` | tailnet MagicDNS (`100.100.100.100` → headscale) | `100.64.0.14`, canonical name `nas.ts.2143.me` |
| `nas.local` | mDNS, avahi, via `hosts: mdns4_minimal` in `/etc/nsswitch.conf` | `192.168.5.175` (bond0) |
| `nas.ts.2143.me` | MagicDNS | `100.64.0.14` |

Unicast DNS never answers a `.local` name, so no `/ip dns static` entry or
`lan-dns` change can fix one. If `.local` is broken, the fault is always
mDNS-side: either the client cannot query, or no host is announcing that name.

## Rule: `mdns-repeat-ifaces` stays empty

`/ip dns mdns-repeat-ifaces` must remain unset. The tracked export in
`network-configs/router.rsc` already had it empty; the live router had drifted
to `bridge,2GWAN` and was reset on 2026-11-16.

What the drift cost: the NAS lost its own mDNS name for at least nine days.
`journalctl -u avahi-daemon` on `nas` recorded **53 `Host name conflict`
events** between Nov 7 and Nov 16, walking the name from `nas-2` to `nas-11` —
avahi's policy is that the incumbent keeps the name and the real owner renames
itself. `avahi-resolve -n nas.local` timed out; `nas-11.local` answered
`192.168.5.175`. So `ssh nas` (MagicDNS) worked while `ping nas.local` failed.

The squatter came in over the WAN: `2GWAN` is `192.168.0.2/24`, an upstream
segment with dozens of live neighbours, and the repeater relayed their mDNS onto
`bridge`. A device named `nas` upstream only has to wake up to steal the name.

Nothing on the LAN needs the repeater. `192.168.1.0/24`, `192.168.5.0/24` and
`192.168.88.0/24` are all addresses on the same `bridge`, so LAN mDNS is already
a single broadcast domain without it; `2GWAN` added reach and nothing but the
leak. Re-adding an interface here needs a reason that is not "cross-VLAN
discovery" — put the VLAN on `bridge` instead.

**Re-tested deliberately, 2026-11-16.** The repeater was re-enabled for a casting
trial against the FiOS set-tops on the Verizon segment (`bridge,2GWAN`, plus a
`cast-rx` address-list of seven TV addresses and four forward rules that bounded
the unicast return path to the Chromecast/AirPlay ports). Two results:

- **It broke the name again within four hours** — `12:30:59 Host name conflict,
  retrying with nas-2`; `nas.local` stopped resolving and the box published
  `nas-2.local` until avahi was restarted. Nine hours of exposure bought one
  collision and no benefit.
- **The trial found nothing to cast to.** No `_googlecast._tcp` was announced
  anywhere, and no discovered mDNS record resolved into `192.168.0.0/24`; the
  `VMS4100ATV` and the `0C:7F:B2:…` boxes are ARRIS FiOS set-tops, not cast
  receivers.

The setting cannot be scoped: RouterOS repeats every record both ways, so the
whitelist governed connections only, never advertisements — the LAN's own names
and its two AirPlay receivers (`living-room-2707`, `Bedroom-11607`) were visible
to the whole Verizon segment the entire time. Treat a future casting request as a
device problem, not a routing problem.

Check it with:

```bash
mikrotik-connect r '/ip dns print' | grep -A2 mdns-repeat   # expect empty
```

## When a `.local` name stops resolving

```bash
avahi-resolve -n nas.local                       # is anyone answering?
ssh nas 'journalctl -u avahi-daemon | grep -c "Host name conflict"'
ssh nas 'avahi-browse -art | grep hostname'      # what it currently publishes
avahi-browse -art | grep -i nas                  # who is on the L2
```

A conflict count that grows means another host is claiming the name: find it
before restarting anything, or the restart just renames the NAS again. Recovery
after the squatter is gone:

```bash
ssh nas 'sudo systemctl restart avahi-daemon'
avahi-resolve -n nas.local && ping -c2 nas.local
```

`systemctl restart avahi-daemon` on `nas` needs `sudo` over SSH — a plain
`systemctl restart` fails with "Access denied as the requested operation
requires interactive authentication".

## Prefer the tailnet name in anything scripted

`nas` (MagicDNS) survives LAN renumbering, bond failover and being off-LAN; it
is what restic (`nfs://nas.ts.2143.me`) and Longhorn already use. An mDNS name
is link-local only and loses to any squatter. Use `nas` in scripts, `nas.local`
only for devices that are not on the tailnet.

## Related

- `docs/lan-dns.md` in `~/repos/argo` covers unicast LAN DNS (the six zones,
  `lan-dns`, router forwards).
- The NAS's DHCPv6 client also receives a colliding `fd00:1::1/128` from the
  router's `ula-addr-pool`, which is a separate bug tracked on the board.
