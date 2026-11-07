---
description: Query and correlate logs, metrics and traces (Loki, Mimir, Tempo, Alloy) — find why a request 4xx/5xx'd, what happened at a given time, read host journals over ssh, and diagnose the observability stack itself
argument-hint: (none — invoked as skill://observability-engineer)
allowed-tools: Read, Search, Find, Task, Bash(curl *), Bash(ssh *), Bash(kubectl *)
tool-hints: |
  Read-only: query, read, and `kubectl get/logs` only. Never restart, scale, delete or edit a
  workload — fixes go through the argo repo (see argo-engineer).
  Never paste a raw log line into a commit, report or chat: `RequestPath` carries `authSig` JWTs
  and API keys, and the argo repo is public. Quote the field, never the line.
  No port-forwards: Loki, Mimir and the syslog sink all answer over the LAN at their MetalLB
  addresses. Tempo does not — query traces through Grafana.
  The workstation's kubectl context is not authoritative for the home cluster: use
  `ssh closet.local kubectl …`.
  Re-run `kubectl get pods -n observability -o wide -l app.kubernetes.io/name=alloy` before
  trusting the node coverage map — it changes.
---

# Observability

Three signals, one stack, everything in the `observability` namespace: Alloy collects, Loki holds
logs, Mimir holds metrics, Tempo holds traces, Grafana reads all three. Identify the signal first,
then read that reference file. Do not query blind — the label names and the retention behaviour
below are not what the defaults would lead you to expect.

| Area | File |
|---|---|
| Logs — LogQL, labels, retention, ingest sources | `loki.md` |
| Traefik access logs — request triage, status codes, client identity | `access-logs.md` |
| Reading logs on a host or pod over ssh (no Loki) | `local-logs.md` |
| Metrics — remote-write jobs, series cap, retention | `mimir.md` |
| Traces — OTLP path, TraceId correlation | `tempo.md` |
| Collection pipeline — Alloy sources, coverage gaps | `alloy.md` |

Paths are relative to this file's directory (`.claude/skills/observability-engineer/` on the
workstation).

## Endpoints

| Purpose | Address | Notes |
|---|---|---|
| Loki query + push | `http://192.168.6.24:3100` (`fd00:6::24`) | svc `loki-push-lb`; its selector is the **gateway**, so it serves the whole query API despite the name |
| Mimir query + push | `http://192.168.6.23:8080` (`fd00:6::23`) | svc `mimir-lb`; Prometheus API under `/prometheus/api/v1/…` |
| Tempo query | — | ClusterIP only; use Grafana, not a LAN call |
| Tempo OTLP ingest | `192.168.6.27:4317` | svc `tempo-otlp-lb`, gRPC only, for the nonprod cluster |
| Syslog sink | `192.168.6.25:514/udp` | svc `syslog-lb` → Alloy `:1514` |
| Stack health check | `http://192.168.6.23:8080/prometheus/api/v1/query?query=count%20by%20(job)(up)` | Mimir; every scrape job with its current target count |

Grafana is `https://grafana.ts.2143.me` with datasource uids `loki`, `mimir`, `tempo`. Loki and
Tempo are cross-linked, so a `TraceId` in a log line jumps straight to the trace.

## Which signal answers which question

| Question | Go to |
|---|---|
| Who called this route, when, with what status? | `access-logs.md` |
| Did the pod crash / what did it print? | `local-logs.md` |
| Is the node or the stack itself sick? | `mimir.md` |
| Why is this request slow — where did the time go? | `tempo.md` |
| Why is data missing from one of the above? | `alloy.md`, then the signal's file |

`kubectl logs` is not a substitute for Loki for Traefik: its access log rotates within seconds —
`--tail=20000` returned 18 s of history (measured 2026-09-21). For anything older, it is a Loki
question.

## Closing the loop

Diagnosis belongs here; the fix does not. Any change to Alloy, Loki, Mimir, Tempo or Grafana is an
edit to `~/repos/argo` followed by a commit and sync — hand off to `argo-engineer`. Nothing in this
skill mutates cluster or host state.

When a number here turns out to be wrong, correct it from a live query and date the correction, in
the reference file that owns it. Three duplicates of the same fact is how the `ClientHost` claim
drifted between skills in the first place.
