---
description: deSEC public DNS — six zones, the two sinks every name CNAMEs into, and the rules that keep DNS-01, mail and the 15-minute DDNS job working
argument-hint: (none — invoked as skill://desec-engineer)
allowed-tools: Bash(desec *), Bash(dig *), Bash(curl *), Read, Search, Find, Edit
tool-hints: |
  Read-only unless asked: list-domains/domain-info/get-records/export-zone and dig are safe.
  add/change/delete-record, new/delete-domain and every token mutation are writes.
  Never pass --token or --debug-http — both put the token somewhere it is visible.
  Four zones' A records belong to the ddns CronJob: write those in argo or they revert in 15 min.
---

# deSEC

Public DNS for six zones; `aross.studio` is a second account. `desec <cmd> --help` covers the CLI.
Zone inventory, ownership and known drift: `zones.md`.

## What you cannot read off the repo

**Two sinks.** Every public name lands on the home WAN IP (ddns CronJob,
`argo/workloads/ddns/cronjob.yaml:94-97`) or on the static DigitalOcean floating IP
`174.138.108.28`. Most names are CNAMEs into one of them. Work out which before debugging — a name
pointing at "the wrong" IP is usually deliberate.

**Four zones' A records are not yours.** The CronJob writes `john2143.com @ *`, `2143.me m`,
`dsstar.us @`, `balabusta.homes @ *` every 15 minutes, and only the RRsets it names — other records
in those zones are safe to edit.

**`correctly_delegated` says nothing about the zone's contents.** It only reflects the parent's NS.
`9s.pics` reports clean with no apex NS and no apex A at all.

**Writes are rate-limited per domain**: 2/s, 15/min, 100/h, 300/day, `429` + `Retry-After`. Seeding
a zone record-by-record cannot work: write a zonefile, then `desec import-zone -f <file> <zone>`
(`-d` dry-runs it).

**`change-record` replaces an RRset; `add-record`/`update-record` append.** The replace form with one
value deletes the rest of the set — five MX records become one.

**TTL floor is 900s**, everything in use is 3600, so a wrong write lives for an hour. Check the
authority before blaming a cache: `dig @ns1.desec.io <name> <type>`.

## Adding a zone

Registrar NS → `ns1.desec.io` + `ns2.desec.org`; `desec new-domain <zone>`; publish the `DS` from
`desec domain-info <zone>` at the registrar; wait for `security_status: secure`. Then, as applicable:

- **apex must follow the WAN IP** → add `sync <zone> @ '*'` to the CronJob *and* give the ddns token
  rights on the new zone (OpenBao → ExternalSecret; rotate per `docs/fleet-patching.md:23-36`). If a
  CNAME into `john2143.com` does the job, prefer it and change nothing.
- **certificates over DNS-01** → add the zone to a solver's `dnsZones` in
  `argo/workloads/cert-manager/templates/cluster-issuer.yaml`. A second deSEC account needs its own
  solver and token, as `aross.studio` has.
- **LAN split-horizon** → forward zone on the router; see `skill://network-engineer`, `dns.md`.

## Access

`desec` reads `~/.config/desec/token`: the admin token, with create-domain and manage-tokens on,
delete-domain and auto-policy off. Workload tokens are not interchangeable — `k3s-ddns` is scoped to
four zones and the cert-manager ones cannot create a domain. A fresh token can write *every* zone
until you flip its default policy to `--no-write` and allow one zone, which is how the scoped ones
are made.

## Safety

Read-only unless asked. `delete-domain` and `import-zone --clear` reach everything CNAME'd into the
zone: state what stops resolving before running them. Never print the token, paste it into a report,
or let it reach a command line.
