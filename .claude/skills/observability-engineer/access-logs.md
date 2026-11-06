# Traefik access logs

Alloy tails every container's stdout into Loki, and Traefik emits one JSON object per request under
`{namespace="kube-system"}`. That access log is the only durable record of "who called what" —
Traefik's own `kubectl logs` rotates within seconds.

## Query recipe

Query the Loki API directly over the LAN; no port-forward needed. The snippet is **bash** — the
interactive shell is fish, so wrap it in `bash -lc '…'`:

```
curl -sS -G 'http://192.168.6.24:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="kube-system"} |= "home.ts.2143.me" | json | DownstreamStatus >= 500' \
  --data-urlencode "start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode "end=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode 'limit=200'
```

The Service is named `loki-push-lb`, but its selector is the Loki **gateway**, so it serves the full
query API despite the name. The interactive equivalent is Grafana Explore with the **Loki**
datasource (uid `loki`).

To narrow to one status or one client, parse the line — `DownstreamStatus` is a JSON number,
`ClientHost` a string:

```logql
{namespace="kube-system"} |= "home.ts.2143.me" | json | DownstreamStatus = 429
{namespace="kube-system"} | json | ClientHost = `192.168.5.123`
```

## Fields

Access-log lines are JSON. The fields worth knowing:

| field | meaning |
|---|---|
| `ClientHost` | real peer address of the connection — but see the section below, it is not one identity |
| `ClientAddr` | `ip:port` of the peer, including the source port; the way to tell paths apart per client |
| `RequestAddr` | address the client used, as a hostname or IP |
| `ServiceAddr` | backend pod IP:port that served the request |
| `DownstreamStatus` | status returned to the client — count this one |
| `OriginStatus` | status from the backend; differs from `DownstreamStatus` when a middleware rewrote the answer |
| `RequestPath`, `RequestMethod`, `RequestHost` | what was asked for |
| `Duration` | nanoseconds — a measured 2.12 s request logged `2122748498` |
| `RouterName`, `ServiceName` | the Traefik router that matched; embeds `httproute-<ns>-<name>-gw-<gateway>…`, so it maps a line back to the exact HTTPRoute |
| `StartUTC` | request start (UTC) — use this, not the local `time` field |
| `TraceId` | correlates the request with Tempo |
| `RequestCount` | **cumulative process counter, not a per-request count** (≈490k and rising) — never sum it |

## `ClientHost` does not identify a household device

`ClientHost` is the real peer address of the connection, and there is no single answer for
household clients. Measured over 6 h on 2026-11-05: `192.168.5.123` (6,479 requests) reached
Traefik directly through the MetalLB address, while `108.56.153.222` — the household WAN IP —
accounted for 7,804 requests that hairpinned out to the public address and back. A third cluster of
addresses, `10.42.x.x`, is in-cluster callers (Grafana, workers) using the public hostname. So:
attribute a request to a household device only if you can see its `192.168.5.x`, and treat
`108.56.153.222` as "some household path, identity unknown". Both paths are live simultaneously —
split horizon is not universally applied.

To tell which path a specific client used, look at `ClientAddr`, not the hostname.

## Status codes

- **`429` is ambiguous.** Both the `rateLimit` and the `inFlightReq` middleware answer `429`
  (`argo/workloads/gateway/templates/security-middlewares.yaml:36,47`), so the log line does not say
  which one rejected the request. Read the HTTPRoute's attached middleware chain instead:
  `kubectl -n <ns> get httproute <name> -o yaml`.
- **`403` is CrowdSec.** The WAF answered, not the backend — look at `OriginStatus` to confirm the
  request never reached the app.
- **429s are per-replica and non-deterministic.** Traefik runs 3 replicas, each with its own
  in-memory rate-limit bucket, so the same burst gets a different verdict depending on which replica
  the connection landed on, and a `burst: 50` bucket per replica absorbs ~150 requests fleet-wide
  (`argo/docs/2026-10-05-ingress-o11y-hardening.md:56-57`). Never infer "the limit is N" from
  observed 429s.

## Limits

Loki's `max_entries_limit_per_query` is **5000** — narrow the window or paginate instead of raising
`limit`. Anything beyond ~55d is not queryable at all; see `loki.md` for the retention reality and
the 30-day per-query cap.

## Never quote a line

`RequestPath` routinely carries `authSig` JWTs (observed on `home.ts.2143.me`) and API keys, and the
`argo` repo is public. Quote individual fields — `DownstreamStatus`, `RequestHost`, `RouterName` —
and never paste a raw log line into a commit, report or chat.
