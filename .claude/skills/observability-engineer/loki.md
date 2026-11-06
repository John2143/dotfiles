# Loki

Log store for every container's stdout, Kubernetes events, host journals and router syslog.

## Access

`http://192.168.6.24:3100` (`fd00:6::24`). The Service is named `loki-push-lb`, but it selects the
Loki **gateway**, so push *and* query work there — the name is misleading, not a restriction.

`auth_enabled: false`, so normal queries need no `X-Scope-OrgID`. The one exception is Grafana's
`drilldown-limits` call, which needs `X-Scope-OrgID: fake` or returns `401 no org id`
(`argo/docs/2026-10-05-ingress-o11y-hardening.md:50`).

## Deployment shape

`deploymentMode: SimpleScalable` — write, read and backend at 2 replicas each, chunks on S3
(SeaweedFS) (`argo/apps/loki.yaml`). This is not single-binary: there is no pod called `loki`. It is
`loki-write-*`, `loki-read-*`, `loki-backend-*` and `loki-gateway-*`. A "Loki is down" report that
names a single pod is mis-scoped.

## Labels the sources actually produce

| selector | source | labels |
|---|---|---|
| `{namespace=…, pod=…, container=…}` | container stdout | k8s metadata |
| `{job="kube-events"}` | Kubernetes events | JSON body |
| `{job="node-journal"}` | host systemd journal | `unit`, `host`, `level` |
| `{job="mikrotik", host="router"}` | router syslog over UDP | `level`, `app` |

All four re-verified live on 2026-11-05 over 24h: `{job="kube-events"}` 8,458 lines,
`{job="node-journal"}` 310,145 across seven hosts, `{job="mikrotik", host="router"}` 212. These are
`count_over_time` over a sliding window — a re-run later will differ slightly, and that is not drift.

`{job="node-journal"}` also carries entries with **no** `unit` — 9,205/24h, kernel and other
non-unit lines — so `unit="k3s.service"` (80,585/24h) is not the whole journal. Top units for
orientation: `k3s.service`, `tailscaled.service`, `iscsid.service`, `postgresql.service`,
`smartctl-exporter.service`.

Which hosts ship, and which do not, is owned by `local-logs.md`.

## Retention is not what the config says

Configured 90d (`retention_period: 2160h` + `compactor.retention_enabled: true`,
`argo/apps/loki.yaml:49-53`); **measured 2026-11-05, the oldest queryable data is ~45 days back**
for the journal stream and at least 62 days back for `kube-events` — the streams do not share a
floor, so "how far back" depends on which stream you ask.

Note also that `loki_compactor_apply_retention_operation_total` (cited in the 2026-09-22 audit) no
longer exists on Loki 3.7.7 — the metric was renamed. Do not read retention health from a missing
metric and conclude the compactor is dead; probe with `count_over_time` over increasing ranges
instead, which is how the 45d/62d figures above were obtained.

## Hard limits, read from the running server

From `curl -sS http://192.168.6.24:3100/config` on Loki **3.7.7**, verified 2026-11-05:

| limit | value |
|---|---|
| `max_entries_limit_per_query` | 5000 |
| `max_query_series` | 500 |
| `max_query_length` | **30d1h** |
| `max_query_lookback` | 0s |
| `max_chunks_per_query` | 2000000 |
| `max_streams_matchers_per_query` | 1000 |
| `cardinality_limit` | 100000 |
| `enforce_retention_period` | false |

The 30-day cap is the one that bites: any question spanning more than ~30 days must be answered in
chunks of ≤30d, summed in the answer. It cannot be one query, regardless of how much retention
exists. And because `enforce_retention_period` is false, the 90d figure in the config is not
enforced by the read path either — the measured depths above are the real ceiling.

## Household caveat

Data older than roughly 45d is not queryable from the journal stream, so "last quarter" cannot be
answered at all. Say so before querying, and never pad an answer with the 90d config value.

## Common queries

```logql
# everything for one host's journal unit
{job="node-journal", host="closet"} |= "k3s" | json | level >= "warning"

# events for one namespace
{job="kube-events"} | json | involvedObject.namespace = "default"

# did anything happen at all in a window (cheap existence check)
count_over_time({namespace="default"}[5m])
```

Narrow the time range before adding filters — with 5000 entries per query and 500 series per query,
a broad selector wastes the budget on the wrong window.
