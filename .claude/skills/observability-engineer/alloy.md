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
| `traefik` | `:9100` |
| `temporal` | relabel forces `<podIP>:9090` — the pods declare no container port |
| `keda` | `keda-operator-metrics-apiserver.keda.svc:8080` |
| `metallb-frr`, `metallb-speaker` | HTTPS `:9140`/`:9120` with bearer token; targets are dropped when they answer 401 |
| `observability` | static list: mimir, loki-read, loki-write, loki-backend, tempo, grafana, alloy `:12345` |

The remaining jobs in `mimir.md` (blackbox, cilium, etcd, home-nodes, hubble, nginx-gateway,
node-exporter, openbao, smartctl, longhorn, status-1) are defined in the same `configMap.content` —
read it there rather than assuming a shape.

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
