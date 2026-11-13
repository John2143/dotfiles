# Alloy — the collection pipeline

One agent, one config. Everything that reaches Loki, Mimir or Tempo passes through it, so when a
signal is missing for one source but present for others, look here before looking at the store.

## One config file

`workloads/alloy/values-prod.yaml` → `configMap.content` is the whole pipeline:

- `discovery.kubernetes` → `prometheus.scrape` per job → remote-write to Mimir
- `loki.source.kubernetes` / `kubernetes_events` / `journal` / `syslog` → `loki.write`
- `otelcol.receiver.otlp` → batch → `otelcol.exporter.otlp` → Tempo

Component detail for the long-standing jobs:

| job | how it is scraped |
|---|---|
| `kubelet`, `cadvisor` | `role=node` discovery; kubelet `:10250` with `bearer_token_file` (SA token) and `tls_config.insecure_skip_verify`; cadvisor via `/metrics/cadvisor` |
| `kube-state-metrics` | chart app in the `kube-state-metrics` ns, `:8080` |
| `longhorn` | **one target per `app=longhorn-manager` pod** on `:9500`, `instance` = node name. Each manager reports only the volumes it owns and the replicas, engines and disks on its own node, so the old `longhorn-backend` Service target returned one node's slice (32 of 263 volumes on 2026-11-13). Five managers now report every volume. `prometheus.relabel "longhorn_metrics"` drops the per-backup families (cluster-wide — without the drop, five managers report each backup five times), `snapshot_actual_size`, `workqueue_*` and `rest_client_*` |
| `traefik` | `:9100` |
| `temporal` | relabel forces `<podIP>:9090` — the pods declare no container port |
| `keda` | `keda-operator-metrics-apiserver.keda.svc:8080` |
| `metallb-frr`, `metallb-speaker` | HTTPS `:9140`/`:9120` with bearer token; targets are dropped when they answer 401 |
| `observability` | static list: mimir, loki-read, loki-write, loki-backend, tempo, grafana, alloy `:12345` |

The remaining jobs in `mimir.md` (blackbox, cilium, etcd, hubble, nginx-gateway, node-exporter,
openbao, longhorn, status-1) are defined in the same `configMap.content` — read it there rather
than assuming a shape.

**Exception: `home-nodes` and `smartctl` are not Alloy jobs.** A standalone Prometheus on `pite`
scrapes host `node_exporter:9100` and `smartctl-exporter:9633` over the tailnet and remote-writes to
Mimir (`workloads/headscale/configmap.yaml:65-66`). `pite` is a tagged node, so its tailnet reach
comes from an explicit ACL rule — a target that goes down is far more often an ACL or name-resolution
problem than a dead exporter. Verified 2026-11-05: `big.local:9100` and `big.local:9633` were both
down while `curl http://100.64.0.24:9100/metrics` from `pite` returned 200 — the exporters were
healthy, the name did not resolve.

## The OTLP metric filter

`otelcol.receiver.otlp "traces"` hands its metrics output to `otelcol.processor.filter "beyla_metrics"`
before the batch processor and the Mimir exporter. It drops two things, both of which restate what
other signals already carry:

- the four HTTP body-size families (`http.{server,client}.{request,response}.body.size`), for every
  service — nothing reads them and the buckets alone were ~26k home series;
- `http.client.*` for services whose `service.name` ends in `-db`, which is the CNPG instance manager
  inside every database pod calling the Kubernetes API (most of those services' series). `db.*`,
  `http.server.*` and `rpc.*` stay, and `http_server_request_duration_count` is load-bearing for the
  status page.

Two rules that bite:

- **OTTL string literals take Go-style escapes.** A regex written `"^http\.client\."` fails to load
  ("invalid quoted string"); write `"^http[.]client[.]"`.
- **`alloy validate` does not parse OTTL** — a bogus function name passes it. Load the filter for
  real, or a bad condition reaches production and the pod keeps running the previous config:
  `docker run --rm -i --entrypoint sh grafana/alloy:v1.19.2 -c 'cat > /tmp/c.alloy; alloy run --stability.level=experimental --storage.path=/tmp/d /tmp/c.alloy'`
  and check for `Failed to build component`.

Whether a filter actually fires is visible per pod:
`kubectl --context closet-as-admin get --raw /api/v1/namespaces/observability/pods/<pod>:12345/proxy/metrics | grep otelcol_processor_filter_datapoints_filtered_total`

**Beyla does not always roll cleanly.** Changing `apps/beyla.yaml` restarts the three Beyla pods
(arch, big, nas) through the DaemonSet's `checksum/config` annotation. On 2026-11-13 two of them sat
in `Terminating` for minutes with `FailedKillPod: context deadline exceeded` on the eBPF container,
which blocks the rollout at `maxUnavailable: 1` and leaves ArgoCD `Progressing`. Force-delete the
stuck pod (`kubectl -n observability delete pod <name> --force --grace-period=0`); the DaemonSet
recreates it with the new checksum. The new config file reaches the *existing* pods through the
mounted ConfigMap within a minute, so telemetry changes before the pods are replaced — do not read a
still-old checksum as "the change is not live".

## Positions

Log positions live on the hostPath `/var/lib/alloy` (`alloy.storagePath` + `volumes.extra`), and the
log components (`loki.source.kubernetes`, `loki.source.kubernetes_events`) are clustered. A
restarted pod therefore resumes where it left off rather than re-reading, and deleting that path
re-ships from the current tail.

## Adding a source or a job

For the home cluster, edit `configMap.content`. For the nonprod cluster, the standalone Alloy on
`np1`-`np3` writes to `192.168.6.24:3100` directly (`workloads/alloy/values-nonprod.yaml:50`) —
which is why those three hosts appear in `{job="node-journal"}` without being part of the home
DaemonSet's pod count.

Never add a `cluster` label on a home job; see `mimir.md` for what that did to the series count.

## Coverage gaps

Two nodes ship nothing. The map, the evidence and the standing fix are owned by `local-logs.md` —
do not restate them here. The check is:

```
kubectl get pods -n observability -o wide -l app.kubernetes.io/name=alloy
```

One pod per home node is the healthy state.

## Changes deploy through argo

Edit → commit → push → sync. `kubectl apply` is never the path, and a live edit to the ConfigMap
will be reverted on the next sync. Defer to `argo-engineer`.
