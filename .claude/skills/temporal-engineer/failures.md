# Failures

Start with the table. Each row names the layer; follow the section. If `temporal` reads
`Synced`/`Healthy` with empty `status.conditions`, Argo sees nothing wrong — the fault is on the
consumer side or in the database.

| Symptom | Likely layer | Go to |
|---|---|---|
| App `temporal` `OutOfSync`, failed op mentions `Job/temporal-schema` and `field is immutable` | schema hook misconfigured | §wedge |
| Any sync stuck `Running` for tens of minutes | PreSync hook still running | §hook |
| Sync `Failed`, hook log says `read-only file system` | hook security context | §hook |
| Consumer returns `503 … temporal_unavailable` | namespace missing, or frontend down | §unavailable |
| Workflow sits in a task queue, nothing executes | worker / versioning / KEDA | `workers.md` |
| Prometheus/Mimir series limit or "too many series" | metrics cardinality | `invariants.md` §2 |
| `temporal-db-rw` does not resolve, pods `Pending`/`CrashLoop` | CNPG cluster | `db.md` |
| `twc-manager` crashing, webhook `x509` errors | controller TLS | `workers.md` |

## §wedge — the schema-Job loop

Signature: `temporal` app `OutOfSync`, `status.operationState` failed, message contains
`Job.batch "temporal-schema-…" is invalid: [spec.selector: Required value, … field is immutable]`.

Meaning: `schema.useHelmHooks` is false (or `Replace=true` is back). See `invariants.md` §1.

Recovery is two steps, in this order: restore the values, push, **then press SYNC once in the Argo
UI** for `temporal`. Automated sync will not retry the same revision after a failed attempt, so the
stale failed operation survives the push on its own.

```bash
ssh closet.local 'kubectl -n argocd get application temporal \
  -o jsonpath="{.status.operationState.phase} {.status.operationState.startedAt}{\"\n\"}{range .status.operationState.syncResult.resources[?(@.kind==\"Job\")]}{.name} {.hookType} {.hookPhase}{\"\n\"}{end}{.status.conditions}{\"\n\"}"'
# expect: Succeeded <ts> / temporal-schema PreSync Succeeded / empty conditions
ssh closet.local 'kubectl -n default get job temporal-schema'   # NotFound — HookSucceeded deleted it
```

## §hook — a failing PreSync

A failed or running PreSync blocks only that sync; serving pods keep running. BeforeHookCreation
keeps the failed Job until the next sync, so read its logs **before** retrying:

```bash
ssh closet.local 'kubectl -n default get pods -l job-name=temporal-schema'
ssh closet.local 'kubectl -n default logs <pod> -c manage-schema-default-store'
ssh closet.local 'kubectl -n default logs <pod> -c manage-schema-visibility-store'
ssh closet.local 'kubectl -n argocd get application temporal -o jsonpath="{.status.operationState.message}"'
```

| Log | Cause | Action |
|---|---|---|
| `read-only file system` | `containerSecurityContext.readOnlyRootFilesystem: true` conflicts with `temporal-sql-tool`'s scratch files | remove that single key, keep the rest, push, SYNC |
| connection refused / auth failed / `database "temporal" does not exist` | CNPG not ready or password rotated wrongly | `db.md`, then SYNC |
| `setup-schema` fails on a version step | chart bumped past the recorded schema version | confirm the hook ran the previous release first; never hand-run `temporal-sql-tool` |

Do not delete the Job to "clear" it — BeforeHookCreation does that on the next attempt, and a
manual delete in between loses the logs you need.

## §unavailable — `503 temporal_unavailable`

The consumer's SDK cannot reach or be served by its namespace. Order of checks:

1. **Frontend up?** `ssh closet.local 'kubectl -n default get pods -l app.kubernetes.io/name=temporal'`
   and `get endpoints temporal-frontend`. Zero endpoints means nothing else matters yet.
2. **Namespace exists?** `temporal operator namespace list` via `access.md`. Temporal clients
   cannot self-register; a namespace that was never created (or was lost with a rebuilt server)
   turns every request into this error.
3. **Namespace Job green?** For rots-web / steam-lobby-preview, a failed `temporal-namespace` Job is
   the normal cause — check its pod, then `scheduler`/wave ordering. See `invariants.md` §7.
4. **Wrong namespace string?** Each consumer sets `TEMPORAL_NAMESPACE`; rots uses `rots` /
   `rots-preview`, steam-lobby uses `pvp` / `pvp-preview`. Previews share one namespace and isolate
   by task queue — a new preview pointing at a per-PR namespace will 503 until that Job runs.

If Temporal was rebuilt, expect every namespace to be gone at once (namespaces live in the
database), and every namespace Job to re-run on the next sync of its app.

## §db-down — database

`temporal-db-rw` unresolved, `temporal` pods `CrashLoopBackOff` with SQL connection errors, or
`Cluster temporal-db` not `Cluster in healthy state`. Diagnosis in `db.md`. Serving pods will
restart-loop until the primary is back; that is expected and is not a Temporal fault.

## §cardinality — series explosion

Mimir admission failing, `temporal` scrape job contributing tens of thousands of series, or
`up{job="temporal"}` fine while queries break. Check `metrics.breakdownByBuildID` is still `false`
and look for pods from retired build IDs still running (stale series persist until the emitting
pod restarts). Never "solve" it by dropping the `temporal` job.

## §ui — the UI, not the server

`temporal.ts.2143.me` blank/403/404 while workflows are fine: the failure is the route, not
Temporal. The LAN-only middleware is the control, the public host must go through
`oauth2-proxy-temporal`, and a login loop is usually the oauth2 secret or the cookie domain.
Traefik access logs in Loki show which router matched (`access.md`).
