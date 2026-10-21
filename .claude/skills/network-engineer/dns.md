# DNS

Three layers. Know which one you are debugging.

| Layer | Server | Answers |
|---|---|---|
| Public | external provider | `john2143.com`, `net.2143.me` → home WAN IP |
| Tailnet | headscale MagicDNS (`extra_records`) | `*.ts.2143.me` → traefik `.6.6` |
| LAN | MikroTik `192.168.5.1` + `lan-dns` `.6.30` | split-horizon answers for the home zones |

## LAN

The router is authoritative only for `router.lan`. Six forward zones carry
`comment="lan-dns forward"` and send `2143.me`, `john2143.com`, `aross.studio`,
`balabusta.homes`, `chess.dsstar.us` and `mm.b.hero.rehab` to `192.168.6.30`. A `netwatch` entry
watches `lan-dns` and falls back to public answers when it is down — that fallback is why a broken
`lan-dns` shows up as *public* IPs rather than NXDOMAIN.

`lan-dns` is a LoadBalancer Service at `192.168.6.30` / `fd00:6::30`; its records are generated
from the cluster's HTTPRoutes, so a new route normally needs no manual DNS. Full model:
`argo/docs/lan-dns.md`.

## IPv6 clients

Router advertisements carry **no DNS** (`/ipv6 nd advertise-dns=no`); the stateful DHCPv6 server
hands out `fd00:1::1` via option `dns-router-ula` (code 23). Before that, clients were given
Verizon's resolver, which answers publicly and silently bypassed split-horizon.

## Checks

```
dig @192.168.6.30 +short john2143.com     # split-horizon answer
dig @192.168.5.1  +short john2143.com     # what a LAN client actually gets
dig @192.168.5.1  +short router.lan       # router's own zone
mikrotik-connect r '/ip dns print'
```

If a LAN client resolves a *public* IP for a home hostname, suspect the `netwatch` failover first.
