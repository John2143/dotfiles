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

Query traces through Grafana (`https://grafana.john2143.com`, datasource uid `tempo`), which is
also where the Loki↔Tempo datasource link is wired.

## Retention

7 days, and it is the one signal that works exactly as configured (`argo/apps/tempo.yaml:30`;
verified 7d returns data, 8d does not). Unlike Loki's compactor and Mimir's bucket index, there is
nothing to caveat here.

## Correlation

`TraceId` on a Traefik access-log line opens the corresponding trace in Grafana — that is the
fastest route from "this request" to "where the time went", and it is why the access log is the
right starting point for latency questions.

Traefik's tracing endpoint is configured in `dotfiles/nixos/closet-configuration.nix` and only
takes effect on a closet rebuild. A `TraceId` missing from access logs after a tracing change means
that rebuild has not happened — not that tracing is broken.
