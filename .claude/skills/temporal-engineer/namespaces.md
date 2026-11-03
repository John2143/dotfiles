# Namespaces

Temporal namespaces are **not** Kubernetes namespaces. Every Temporal namespace in this cluster
lives in the Kubernetes namespace `default` and in the `temporal` database; the Kubernetes
namespace is irrelevant to them.

| Temporal namespace | Owner | Retention | Isolated by |
|---|---|---|---|
| `rots` | rots-web prod | 72h | workflows per game server |
| `rots-preview` | rots-web previews | 72h | task queue `rots-pr-<N>` |
| `pvp` | steam-lobby prod | 72h | task queue `lobby` |
| `pvp-preview` | steam-lobby previews | 72h | per-PR task queues |
| `default` | frigate-genai (4 WorkerDeployments), imageserver | 72h | per-worker task queues / deployment names |
| `john2143-com` | john2143-worker | 168h | task queue `john2143-com` |
| `temporal-system` | Temporal itself | 168h | **internal** — system workflows; never touch, never list-debug as if it were an app |

72h is deliberate: history is written to `temporal_visibility` and the default store, and there is
no backup (see `db.md`), so longer retention only increases the blast radius of a database loss. Do
not raise it without an answer for storage growth and recovery.

**Known gap: `default` and `john2143-com` have no registration Job in this repo.** They exist
because they were created out of band; the worker controller does not create them either (it
requires `temporalNamespace` to already exist). A rebuilt Temporal will leave frigate-genai and
john2143-worker with no namespace and no hook to recreate it. If that happens, add a Job in the
consumer's style — do not create it by hand and call it fixed.

## Creating a namespace — always through a Job

Temporal clients cannot self-register. A missing namespace turns every request into
`503 … temporal_unavailable`, which is why each app chart ships its own registration Job before
the app's Deployment.

Pattern (`workloads/rots-web/templates/temporal-namespace-job.yaml`,
`workloads/steam-lobby-preview/templates/init-job.yaml`):

```yaml
annotations:
  argocd.argoproj.io/hook: Sync
  argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
  argocd.argoproj.io/sync-wave: "-1"
# container: docker.io/temporalio/admin-tools:1.32.0,
#            TEMPORAL_ADDRESS=temporal-frontend.default.svc:7233
# command:   temporal operator namespace describe "$NS" \
#              || temporal operator namespace create "$NS" --retention 72h
```

Non-negotiable properties, each of which caused a past failure when missing:

- `HookSucceeded` — a completed Job left as a tracked resource gets deleted and its old result
  reused instead of re-running, so a rebuilt server never gets its namespace back.
- `sync-wave: "-1"` — the app only becomes Ready once its worker reaches the namespace.
- `describe || create` — idempotent; concurrent previews collide harmlessly and retry.
- High `backoffLimit` — the collision above is expected, not an error.

Adding a namespace for a new app: copy this Job into that app's chart with its own
`values.yaml` namespace key. Do not create a shared namespace chart — ownership must follow the
consumer, or a preview cleanup deletes production's namespace.

## When to touch a namespace by hand

Only to read. `temporal operator namespace describe <ns>` shows retention and state.

`temporal operator namespace delete` is unrecoverable and destroys workflow history. If a namespace
must be recreated, that is a chart change — re-run the consumer's Job — so the next rebuild
reproduces it. Ask before deleting.
