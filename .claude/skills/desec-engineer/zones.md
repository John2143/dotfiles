# Zones

Six on deSEC (`desec list-domains`), one on a second account. Every name CNAMEs into one of two
sinks: the ddns-owned home WAN IP, or `174.138.108.28` (DigitalOcean, static, written by hand).

| Zone | Apex / wildcard | Owner | Consumers |
|---|---|---|---|
| john2143.com | `@` A + `*` A → home | ddns | home edge; Google MX; `*` MX → `m.2143.me` catch-all; DNS-01; LAN |
| 2143.me | `@` A → DO (static), `m` A → home | `m` ddns, rest hand | DO edge; self-hosted mail on `m` (Proton MX at apex); DNS-01; LAN |
| dsstar.us | `@` A → home, `*` CNAME `john2143.com` | ddns (apex only) | `i` CNAME → 2143.me; `chess` LAN zone |
| balabusta.homes | `@` A + `*` A → home | ddns | LAN |
| poe.sale | `@` A → DO, `*` CNAME `john2143.com` | hand | `how.poe.sale`; DNS-01 |
| 9s.pics | `*` CNAME `2143.me`, **no apex A or NS** | hand | DO cluster (`2143-59s`), HTTP-01 |
| aross.studio | second account, token `desec-aross-studio-token` | hand | cert-manager only; LAN |

`listen`, `anni`, `timestone.2143.me`, `prod.john2143.com` and `i.dsstar.us` CNAME into the DO apex;
`*.dsstar.us`, `*.poe.sale` and (intended) `headscale.9s.pics` CNAME into `john2143.com`. An apex
write on either sink therefore moves a lot of names.

## Drift, verified 2026-11-07

- **`headscale.9s.pics` is orphaned.** A literal `A` at the WAN IP whose writer — the deSEC timer on
  home-pi, `2143-59s/README.md:88` — was retired, while the ddns CronJob syncs four zones and
  `9s.pics` is not one of them. It looks correct only because the IP has not moved. CNAME it to
  `john2143.com.`, or add `sync 9s.pics headscale` to the CronJob.
- **`9s.pics` has no apex `NS` and no apex `A`**, yet reports `correctly_delegated` because that
  field only reflects the parent (`.pics`). `dig 9s.pics NS` returns nothing and
  `https://9s.pics` does not resolve. Restore the two NS rrsets if the apex should exist.
- **`2143-59s/README.md:85-88` is stale**: it documents k8gb NS delegation to `ns1/ns2/ns3.9s.pics`.
  `ns1.9s.pics` (`174.138.108.28`) times out and the SOA is `get.desec.io`, so deSEC serves the zone.
