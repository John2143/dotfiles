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

Most jobs are produced by the home Alloy DaemonSet — component detail is in `alloy.md`. **Two are
not:** `home-nodes` and `smartctl` are scraped by a standalone Prometheus on `pite` that
remote-writes here (`workloads/headscale/configmap.yaml:65-66`). That matters when one of their
targets goes down: the fault is usually tailnet reachability from `pite`, not Alloy.

## The series cap is the sharp edge

A `cluster` label on home series doubled every series and hit Mimir's 500k per-tenant limit on
2026-10-28 (`argo/workloads/alloy/values-prod.yaml:66-69`).

The rule: home is the series **without** a `cluster` label. DOKS is `cluster="doks"`, the status
droplet is `cluster="do"`. Never add a cluster label to a home job.

## History: the 13h bug is fixed

The 2026-09-22 audit found the ingester keeping only 13 h while the store-gateway loaded zero blocks
(`cortex_bucket_store_blocks_loaded = 0`, `cortex_blocks_meta_synced{state="no-bucket-index"} = 1`,
compactor never building the index, 1,432 unreadable block dirs).

**That is no longer the state — verified 2026-11-05:** `cortex_bucket_store_blocks_loaded = 33`,
`cortex_blocks_meta_synced` reports `33` in state `loaded`, and `up[1h] offset 30d` returns data.
Queries 30 days back work.

`cortex_compactor_tenants_discovered` still reports `0`, so how the blocks are being loaded is not
obvious from that metric — do not reason about compaction from it alone; re-check
`blocks_loaded` and `blocks_meta_synced` instead.

If "NO DATA" comes back for a window that should have data, re-run the query with a shard of the
range before concluding the workload was idle.

## Do not propose the fix here

Fixing it is an `argo` change with two documented options — `bucket_store.bucket_index.enabled:
false`, and a dedicated single-replica compactor (the audit above). Hand off to `argo-engineer`.
