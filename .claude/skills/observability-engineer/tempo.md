# Tempo

Trace store. The smallest surface of the three signals, because Tempo is deliberately not exposed
to the LAN.

## The path a trace takes

Apps send OTLP to Alloy — `alloy.observability.svc:4317` (gRPC) or `:4318` (HTTP) — which batches
and exports to `tempo.observability.svc:4317` (insecure). Nothing reaches Tempo directly; if traces
are missing, the fault is usually in Alloy (`alloy.md`) or in the app's exporter config.

## No LAN query endpoint

Tempo is ClusterIP only. The MetalLB service `tempo-otlp-lb` (`192.168.6.27:4317`) is
**ingest-only**, gRPC-only, and exists for the nonprod cluster
(`argo/workloads/observability/lb-services.yaml:59-72`). Do not try to query traces on it.

Query traces through Grafana (`https://grafana.ts.2143.me`, datasource uid `tempo`), which is
also where the Loki↔Tempo datasource link is wired.

## Retention

7 days (`argo/apps/tempo.yaml:30`; verified 7d returns data, 8d does not) — **while the compactor is
healthy**. Retention runs in the compactor; when it cannot read a block's meta, nothing is deleted
and `tempodb_blocklist_length` climbs (it reached ~2,000 against a steady ~330 in Nov 2026).

## Crash loop: compactor stuck in `Starting`

Symptom: `tempo-0` restarts about every 60 s, `/ready` returns 503, and `/status/services` shows
`compactor` in `Starting` while everything else is `Running`. Tempo's `up` is 0.

Mechanism: at startup the compactor runs its first blocklist poll synchronously
(`tempodb/tempodb.go`, `EnablePolling`). If any `meta.json` / `meta.compacted.json` in
`tempo-blocks/single-tenant/` points at a SeaweedFS chunk that no longer exists, the filer retries
each read for 13 s or more. The poll then takes minutes (`tempodb_blocklist_poll_duration_seconds`
went from ~2.5 s to ~300 s), and the liveness probe kills the pod before it finishes. A pod that
started before the chunks went missing keeps running, so the break only shows on the next restart.
Changing Tempo's config does not cause or fix it.

Find the bad metas (read-only, from inside the filer pod): list block folders with
`curl -H 'Accept: application/json' 'http://127.0.0.1:8888/buckets/tempo-blocks/single-tenant/?limit=500'`
(page with `lastFileName`), fetch each meta with `?metadata=true` to get its chunk `file_id`, then
`curl -I http://<volume-pod-ip>:8080/<file_id>`. A 404 counts only if a second read of the entry
still shows the same `file_id`: Tempo deletes `meta.json` right after copying it during compaction.

Fix used on 2026-11-11 (reversible, nothing deleted): rename each bad meta in place, e.g.
`curl -X POST 'http://127.0.0.1:8888/buckets/tempo-blocks/single-tenant/<id>/meta.compacted.json.quarantined-2026-11-11?mv.from=/buckets/tempo-blocks/single-tenant/<id>/meta.compacted.json'`.
Tempo finds blocks by their meta object, so it skips them. Moving the folders out of the bucket fails
("can not move across collection"), and moving them to another top-level prefix makes Tempo treat
that prefix as a tenant. Then delete `tempo-0` and confirm every module is `Running`.

## Correlation

`TraceId` on a Traefik access-log line opens the corresponding trace in Grafana — that is the
fastest route from "this request" to "where the time went", and it is why the access log is the
right starting point for latency questions.

Traefik's tracing endpoint is configured in `dotfiles/nixos/closet-configuration.nix` and only
takes effect on a closet rebuild. A `TraceId` missing from access logs after a tracing change means
that rebuild has not happened — not that tracing is broken.
