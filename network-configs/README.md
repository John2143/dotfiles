# Network Configs

MikroTik firmware and device configurations for the home network.

## Contents

- `router.rsc` — Full RouterOS config export from the main router (RB5009UPr+S+, 192.168.5.1)
- `core.rsc` — Config export from the core switch (CRS305-1G-4S+IN, 192.168.5.4)
- `upstairs.rsc` — Config export from the upstairs switch (CRS310-8G+2S+IN, 192.168.5.3)
- `office.rsc` — Config export from the office switch (CRS310-8G+2S+IN, 192.168.5.2)
- `upstairs-core.rsc` — Config export from the upstairs-core switch (CRS305-1G-4S+ r2, 192.168.5.5)

Each device also has a `.verbose.rsc` twin (`/export verbose` — includes protocol-mode,
bridge and default settings) for full-fidelity restore.

**`/export` omits sensitive values** — WireGuard private keys, passwords, etc. only appear
under `/export show-sensitive`. These files are safe to commit; never add `show-sensitive`.

Git tracks history — no need for dates in filenames.

## How to Update

```bash
# RouterOS writes CRLF over a terminal; strip it or every line looks changed.
export k=/run/user/$(id -u)/mikrotik-key
ssh -i "$k" admin@192.168.5.1 '/export' | tr -d '\r' > router.rsc
ssh -i "$k" admin@192.168.5.4 '/export' | tr -d '\r' > core.rsc
ssh -i "$k" admin@192.168.5.3 '/export' | tr -d '\r' > upstairs.rsc
ssh -i "$k" admin@192.168.5.2 '/export' | tr -d '\r' > office.rsc
ssh -i "$k" admin@192.168.5.5 '/export' | tr -d '\r' > upstairs-core.rsc

# ...and the .verbose.rsc twin of each ('/export verbose' - see SKILL.md for the full list)
./check-drift.sh --quiet   # must print OK
```

## Restoring

**Destructive — overwrites the entire running config. Reboot recommended after.**

```bash
# Via SSH pipe (streams commands directly):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 < router.rsc

# Or via RouterOS flash (upload file first):
mikrotik-connect r '/import file=router.rsc'
mikrotik-connect r '/system reboot'
```

**Never import a switch config onto the router or vice versa** — the interface names and hardware topology are different.

## Router SNMP (for pite's Prometheus)

The router answers SNMPv3 only for `pite` (192.168.5.9) and `office`
(192.168.5.209), user `pite`, `authPriv` with SHA1 + AES. SHA1 is not a choice:
RouterOS 7.24.5 offers only MD5/SHA1 for `authentication-protocol` (verified with
`/console inspect request=completion path="snmp,community,add,authentication-protocol"`).
The default `public` community still exists but is narrowed to
`addresses=127.0.0.1/32 read-access=no`, so no v1/v2c request is ever answered.
Credentials live in OpenBao at `consumers/john2143-com/observability/router-snmp`
and reach pite as the agenix secret `router-snmp.age`.

pite runs `snmp_exporter` on `127.0.0.1:9116` (never exposed) and scrapes it every
60 s with modules `if_mib system hrDevice hrStorage`; the series arrive in Mimir as
`job="router-snmp"`. `/export` omits passwords, which is why the committed baseline
above can hold the `/snmp community` section safely — check
`grep -cE 'authentication-password|encryption-password' router.rsc` is 0 before
committing a refresh.

Measured flash cost: ~132 sectors/h while polling, against a ~117 sectors/h
long-run rate (`write-sect-since-reboot` before/after a 3.2 h window).

## Per-connection accounting: why traffic-flow is off

`/ip traffic-flow` is disabled on all five devices, deliberately:

- **Hardware offload must stay on.** Every bridge port on the core and upstairs
  switches is `hw=yes`; L2 forwarding happens in the switch chip and never crosses
  the CPU, so switch traffic-flow would export almost nothing.
- **Fasttrack defeats it on the router too.** `defconf: fasttrack` sends
  established/related traffic through FastPath, which MikroTik documents as
  invisible to "firewall, queues, IPsec, IP accounting, VRF" — i.e. to flow export.

`/ip firewall connection` is the remaining source: it holds `orig-bytes`/`repl-bytes`
per connection, and its `F` flag shows fasttracked flows are included. Churn is
~209 new connections/min (~125k/day), so per-connection data belongs in Loki, not
Mimir's series cap. A sampling poller would also miss every flow shorter than its
interval, and it only ever sees traffic routed by the RB5009 — switch-local traffic
is out of reach for as long as offload stays on. Not built; revisit only if a
concrete per-flow question needs it.

