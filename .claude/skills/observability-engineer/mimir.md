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

Measured 2026-11-11 — **22 jobs**, with target counts that drift as pods come and go. Re-run the
query above rather than trusting a count; the list itself is the stable part:

| job | targets | | job | targets |
|---|---|---|---|---|
| `blackbox-http` | 6 | | `kubelet` | 10 |
| `blackbox-internet` | 2 | | `longhorn` | 1 |
| `blackbox-tcp` | 8 | | `nginx-gateway` | 1 |
| `cadvisor` | 9 | | `node-exporter` | 1 |
| `cilium-agent` | 1 | | `observability` | 11 |
| `cnpg` | 17 | | `openbao` | 3 |
| `etcd` | 3 | | `router-snmp` | 1 |
| `home-nodes` | 10 | | `smartctl` | 6 |
| `hubble` | 1 | | `status-1` | 1 |
| `keda` | 1 | | `temporal` | 4 |
| `kube-state-metrics` | 6 | | `traefik` | 6 |

Most jobs are produced by the home Alloy DaemonSet — component detail is in `alloy.md`. **Seven
are not:** `home-nodes`, `smartctl`, `etcd`, `blackbox-http`, `blackbox-tcp`, `blackbox-internet`
and `router-snmp` are scraped by a standalone Prometheus on `pite` that remote-writes here
(`dotfiles/nixos/pite-canary.nix`, `job_name` entries). That matters twice: when one of their
targets goes down the fault is usually tailnet reachability from `pite`, not Alloy; and Alloy's
relabel rules never see these series, so a drop rule in `values-prod.yaml` cannot trim them.

## The series cap is the sharp edge

A `cluster` label on home series doubled every series and hit Mimir's 500k per-tenant limit on
2026-10-28 (`argo/workloads/alloy/values-prod.yaml:75-77`).

The rule: home is the series **without** a `cluster` label. DOKS is `cluster="doks"`, the status
droplet is `cluster="do"`. Never add a cluster label to a home job.

**The limit is per ingester, not per tenant.** Each ingester's ceiling is
`max_global_series_per_user / <ingesters in the ring>` at `replication_factor: 1`. At 500k with 2
ingesters that was 250k each; on 2026-11-11 the cluster held 414k series with one ingester pinned at
250k, and `cortex_discarded_samples_total{reason="per_user_series_limit"}` rose 15.4M in 24 h.
Adding ingesters without raising the limit lowers every ceiling — always change both together.
`cortex_ingester_memory_series` is scraped through the Service, so it shows one pod at a time. The
ring page (`/ingester/ring`) lists the instances but has no series counts. To read each pod's count:
`kubectl --context closet-as-admin get --raw /api/v1/namespaces/observability/pods/mimir-0:8080/proxy/metrics | grep -E '^cortex_ingester_(memory|active)_series'`
(repeat for `mimir-1`).

State after argo #101–#103 (2026-11-11): **2 ingesters, 750k limit (375k each).** A third ingester
was tried and reverted: `office` carries `wifi=no-network-storage:NoSchedule`, so with `arch` and
`nas` excluded only `big` and `closet` can host a Longhorn-backed Mimir pod.

Measured with `count({__name__=~".+"})` (verified 2026-11-11):

- **424k at 04:00Z**, before #101.
- **335k at 22:44Z**, which works out to about **186k memory series per ingester, half its ceiling**.

The trims account for about 64k of the drop: `temporal` −31k, `cadvisor` −14k, `kubelet` −9.5k,
`longhorn` −8.5k. The rest came from churn, and the biggest part of that is Beyla's
`longhorn-system/instance-manager-*` series, which can swing ±27k within an hour (see below).
Queries older than about 12h reach the store-gateway: one instant `count` at that age takes ~110 s,
range queries time out, and parallel ones get the connection dropped. Run them one at a time.

**State after argo #126/#128/#129 (2026-11-13).** The same query read 369k at 05:20Z and **194k at
07:00Z**, of which 146k is home — about 97k memory series per ingester against a 375k ceiling. The
contributors: Beyla 90.9k → 8.0k, span metrics 53.5k → 216, kube-state-metrics 42.7k → 19.6k,
cadvisor 40.2k → 28.5k, kubelet 5.2k → 3.2k, and Longhorn 6.9k → 7.8k (more series, but every volume
now reports instead of one node's slice). Series that stop being written stay visible to instant
queries for about five minutes, so a check run straight after a merge overstates the count — wait out
the lookback before quoting a number.

Trims in place:

- Round 2, argo #126/#128/#129 (2026-11-13), all in `values-prod.yaml` unless noted:
  - `prometheus.relabel "ksm_slow"` drops the families nothing reads — Service and EndpointSlice
    info/created/ports, ReplicaSets, pod tolerations and IPs, persistent volumes (not claims),
    secrets, configmaps, leases, webhooks, NetworkPolicies, attachment metadata and `kube_.*_created`.
    Home KSM went 42.7k → 19.1k. rots-prod alone had 2,013 Services and 3,013 EndpointSlices.
  - `prometheus.relabel "cadvisor_metrics"` now drops `container_fs_.*` as a family; it carries no
    `pod` or `container` label here, so it cannot be joined to a workload. Home cadvisor 40.2k → 27.6k.
  - `prometheus.relabel "kubelet_metrics"` adds `apiextensions_*`, `watch_cache_*`, `kubeproxy_*`,
    `k3s_*` and friends — k3s serves apiserver/controller-manager/kube-proxy metrics on the same
    endpoint. `aggregator_unavailable_apiservice` is deliberately kept.
  - `otelcol.processor.filter "beyla_metrics"` drops the four HTTP body-size families and
    `http.client.*` on `*-db` services (see `alloy.md`).
  - `apps/beyla.yaml` stops instrumenting ten infra namespaces (`longhorn-system`, `argocd`,
    `observability`, `cnpg-system`, `keda*`, `kured`, `kube-state-metrics*`, `metallb-system`).
  - `apps/tempo.yaml` generates span metrics from SDK spans only (see `tempo.md`).
  - pite's `nixos/pite-canary.nix` remote write drops `veth*` `node_network_*`, six unread
    node_exporter families, and the kubelet/controller-manager families that the `job="etcd"` endpoint
    repeats. `write_relabel_configs` only affects the push, so pite's local alert rules still see
    everything.
- The home `prometheus.remote_write "mimir"` endpoint drops classic `_bucket` series for `kubelet`,
  `cadvisor`, `temporal*`, `longhorn*`, `metallb*`, `argocd*`, `memberlist*`, `keda*` and
  `cnpg-system*` (`values-prod.yaml:68`). Application histograms keep theirs — gameserver
  `rots_tick_duration_bucket` / `dino_tick_duration_bucket`, litellm, traefik, observability.
- `prometheus.relabel "cadvisor_metrics"` (`values-prod.yaml:126`) drops `namespace="longhorn-system"`
  and seven unqueried `container_*` families. Do not `labeldrop` `id` there: cadvisor's `name` label
  already carries the container ID, and system cgroups (`pod=""`) differ only by `id`, so dropping
  it collides ~900 label sets.

**A remote-write rule only sees remote-written series.** Beyla's OTLP metrics take a separate path
(`otelcol.exporter.otlphttp "mimir"`) and Mimir derives their `job` from
`service.namespace/service.name` — so `longhorn-system/instance-manager-*`, `memberlist/loki`,
`metallb-system/metallb` etc. look like scrape jobs but are not. That is why Beyla's series were never
touched by the `_bucket` rule above, and why the fix for them was to stop instrumenting those
namespaces (argo #129), not to filter them downstream. Likewise `job="etcd"` and the
blackbox/SNMP jobs come from pite's Prometheus. Before writing a drop rule, check which path the
series arrives on.

Tempo's span metrics (`traces_spanmetrics_*`) are load-bearing: the games-alerts join-rejection alert
and two games-fleet panels read them. They were removed and restored on 2026-11-11 (#101, #103), and
since #129 they cover app SDK spans only — the generator holds ~200 active series instead of ~27k, so
they are no longer a series-cap concern. The Tempo crash loop seen on 2026-11-11 was **not** caused by
either config: block metas pointed at missing SeaweedFS chunks and it fails with any config (see
`tempo.md`).

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
