# Reading logs directly on a host

The ssh path, for when Loki has nothing — because the node does not ship, or because the window you
need predates what the pipeline kept.

## Coverage map — read this before any command

Verified live on 2026-11-05 with
`sum by (host) (count_over_time({job="node-journal"}[24h]))`, which returns **exactly seven hosts**:

| host | lines/24h | how it ships |
|---|---|---|
| `nas` | 125,432 | home Alloy DaemonSet |
| `closet` | 104,978 | home Alloy DaemonSet |
| `big` | 43,858 | home Alloy DaemonSet |
| `arch` | 27,931 | home Alloy DaemonSet |
| `np1` | 2,672 | nonprod Alloy, pushes straight to `192.168.6.24:3100` |
| `np2` | 2,670 | nonprod Alloy |
| `np3` | 2,604 | nonprod Alloy |

**Absent: `office` and `pite`.** `office` carries the taints `wifi,seated` and `pite` carries `pi`;
the home DaemonSet declares neither `nodeSelector` nor `tolerations`, so no Alloy pod is scheduled
there (`argo/docs/2026-09-22-o11y-retention-and-health-audit.md:113-120`; re-checked against
`argo/workloads/alloy/values-{prod,nonprod}.yaml`).

**For those two nodes there is no Loki data at all — `ssh` is the only source.** The workloads you
will be asked about and cannot find in Loki: `longhorn-manager`, `longhorn-csi-plugin`,
`instance-manager`, `metallb-frr-k8s`, `metallb-speaker`, and the `nightly-backup` Job.

Metrics are a different story, so do not over-generalize: `office.local:9100` is scraped normally by
`pite`'s Prometheus, and `pite` scrapes **itself** as `localhost:9100` — that anonymous-looking
target is `pite`, not a phantom duplicate (`node_uname_info{instance="localhost:9100"}` reports
`nodename="pite"`). So these nodes have metrics and no logs. When a metric is missing for one of
them, the fault is in the scrape path from `pite`; when a *log* is missing, it is expected.

## The 12-hour hole

`loki.source.journal` reads with `max_age = "12h"`, so any Alloy outage longer than 12 h leaves a
**permanent** gap in `{job="node-journal"}`. The on-host journal is the only way to fill it —
journald persists to `/var/log/journal`, which is why that path is mounted into the Alloy pod.

## Commands

Pod logs, home cluster:

```
ssh closet.local kubectl logs -n <ns> <pod> --tail=200
ssh closet.local kubectl logs -n <ns> -l <selector> --tail=50 --prefix
```

Never rely on the workstation's local `kubectl` — its context points at DigitalOcean, not this
cluster.

Nodes that do not ship (`pite`, `office`) — the API path goes through `nas`, and anything
kubelet-adjacent has to be read on the node itself:

```
ssh nas sudo k3s kubectl get pods -A -o wide
ssh pite journalctl -u k3s --no-pager -n 50
```

Host services:

```
journalctl -u k3s --no-pager -n 50
journalctl -u <unit> --no-pager --since "2 hours ago"
```

## Search the message, not the level

`journalctl -p warning` can show nothing while an auth failure sits logged at `info`
(`argo/docs/2026-09-24-immich-sso-migration.md:169-170`). Search the text instead:

```
journalctl -u <unit> --no-pager | rg <text>
```

The shape that works for storage-path faults:

```
journalctl -u k3s | rg "failed to find plugin"
```

(`argo/docs/k3s-store-paths.md:11`)

## When to stop using this page

If the caller needs history beyond a restart, or the same events as another consumer saw them, it
is a Loki question — go to `loki.md`. `kubectl logs` for Traefik is always the wrong tool; that log
rotates in seconds.
