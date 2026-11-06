# Mimir

Prometheus-compatible metrics store. Everything the home cluster and the DO clusters scrape lands
here by remote-write.

## Access

`http://192.168.6.23:8080` (`fd00:6::23`), Prometheus API under `/prometheus/api/v1/query`. The
Service is `mimir-lb`.

Health check — every scrape job with its current target count:

```
curl -s 'http://192.168.6.23:8080/prometheus/api/v1/query?query=count%20by%20(job)(up)'
```

## Jobs

Measured 2026-11-05 — **19 jobs**, with target counts that drift as pods come and go. Re-run the
query above rather than trusting a count; the list itself is the stable part:

| job | targets | | job | targets |
|---|---|---|---|---|
| `blackbox-http` | 6 | | `kubelet` | 10 |
| `blackbox-tcp` | 8 | | `longhorn` | 1 |
| `cadvisor` | 9 | | `nginx-gateway` | 1 |
| `cilium-agent` | 1 | | `node-exporter` | 1 |
| `etcd` | 3 | | `observability` | 11 |
| `home-nodes` | 10 | | `openbao` | 3 |
| `hubble` | 1 | | `smartctl` | 6 |
| `keda` | 1 | | `status-1` | 1 |
| `kube-state-metrics` | 5 | | `temporal` | 4 |
| | | | `traefik` | 6 |

Which Alloy component produces each job is in `alloy.md` — this file is about the store.

## The series cap is the sharp edge

A `cluster` label on home series doubled every series and hit Mimir's 500k per-tenant limit on
2026-10-28 (`argo/workloads/alloy/values-prod.yaml:66-69`).

The rule: home is the series **without** a `cluster` label. DOKS is `cluster="doks"`, the status
droplet is `cluster="do"`. Never add a cluster label to a home job.

## History is ~13h, not 30d

Configured `compactor_blocks_retention_period: 720h`, but the ingester keeps 13 h and the
store-gateway has never loaded a block — `cortex_bucket_store_blocks_loaded = 0`,
`cortex_blocks_meta_synced{state="no-bucket-index"} = 1` — because the compactor never builds the
bucket index (`cortex_compactor_tenants_discovered = 0`). Some 1,432 block dirs sit in S3
unreadable (`argo/docs/2026-09-22-o11y-retention-and-health-audit.md:35-55`).

So a query older than ~13 h returning `NO DATA` is the known bug, not missing samples. Say that
instead of concluding the workload was idle. This is the opposite failure mode from Loki, where
"empty" usually means "aged out".

## Do not propose the fix here

Fixing it is an `argo` change with two documented options — `bucket_store.bucket_index.enabled:
false`, and a dedicated single-replica compactor (the audit above). Hand off to `argo-engineer`.
