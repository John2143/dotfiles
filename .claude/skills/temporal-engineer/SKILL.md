---
description: Temporal on the home cluster — layout, namespaces, workers, failure triage, safe operation
argument-hint: (none — invoked as skill://temporal-engineer)
allowed-tools: Bash(ssh *), Bash(kubectl *), Bash(curl *), Read, Search, Edit
tool-hints: |
  Read-only by default. `temporal workflow terminate`, `temporal operator namespace delete`,
  and killing a schema or namespace Job are unrecoverable — cancel is not terminate, and a
  deleted namespace takes its history with it. Ask before any of them.
  kubectl for the home cluster goes through `ssh closet.local 'kubectl -n <ns> …'` with an
  explicit namespace; the workstation's current context is not authoritative for this cluster.
  Never put the CNPG password or the oauth2 client secret on a command line.
---

# Temporal

Self-hosted Temporal (Helm chart 1.7.0) in the home k3s cluster, Kubernetes namespace `default`.
Six workloads depend on one frontend, so a Temporal fault almost never looks like a Temporal
fault — it looks like somebody else's `503`.

Consumers: `frigate-genai` (4 WorkerDeployments via temporal-worker-controller), `rots-web` prod +
previews, `steam-lobby` prod + previews, `john2143-worker`, `imageserver`.

| Need | File |
|---|---|
| endpoints, UI, CLI, DB access | `access.md` |
| rules that must not drift | `invariants.md` |
| symptom → cause → action | `failures.md` |
| Temporal namespaces and retention | `namespaces.md` |
| workers, versioning, task queues | `workers.md` |
| schema versions, shards, CNPG cluster | `db.md` |

---

## Mode: Temporal operations

### Step 1 — Verify the target

```bash
git -C ~/repos/argo remote -v                      # expect 2143-Labs/argo
ssh -o ConnectTimeout=2 closet.local 'hostname'    # expect closet
```

All cluster reads: `ssh closet.local 'kubectl -n <namespace> …'`. `closet-as-viewer` also exists
locally if SSH is unavailable. Never `apply`, `delete`, `patch`, `scale`, `rollout restart`.

To reach Temporal itself: `access.md` — in-cluster `temporal-frontend.default.svc.cluster.local:7233`
(plaintext gRPC), CLI in `deploy/temporal-admintools`.

### Step 2 — Diagnose

Start at the triage table in `failures.md`. Escalate to `workers.md`, `namespaces.md`, or `db.md`
once the failing layer is known. Load `invariants.md` before proposing any values change — most
"obvious" fixes here (turning off Helm hooks, re-enabling per-build metrics, bumping shards) are
the exact changes that caused past incidents.

### Step 3 — Change (declarative only)

Every change is a file edit in `~/repos/argo`, committed and pushed; Argo CD auto-syncs. There is
no imperative path — a hand-applied change is reverted by `selfHeal`.

| Object | File |
|---|---|
| server, schema hook, metrics, LB IP | `apps/temporal.yaml` |
| UI routes, oauth2-proxy | `apps/temporal-routes.yaml`, `apps/oauth2-proxy-temporal.yaml`, `workloads/temporal-routes/` |
| database cluster | `apps/temporal-db.yaml`, `workloads/temporal-db/cnpg-cluster.yaml` |
| worker controller | `apps/temporal-worker-controller.yaml`, `workloads/temporal-worker-controller/` |
| namespace registration | `workloads/<app>/templates/…` (hooks, not a shared chart) |
| LAN DNS pin for the gRPC IP | `workloads/lan-dns/configmap.yaml` |

After pushing, verify without mutating:

```bash
ssh closet.local 'kubectl -n argocd get application temporal -o wide'
ssh closet.local 'kubectl -n argocd get application temporal -o jsonpath="{.status.operationState.phase} {.status.operationState.message}{\"\n\"}"'
```

### Constraints

| Action | Allowed |
|---|---|
| `kubectl get/describe/logs`, `temporal … describe/list/show`, `curl` the UI | yes |
| Edit files in `~/repos/argo` | yes, after confirming the repo |
| `git commit` / `git push` | commit yes, push only with approval |
| `temporal operator namespace create/update` | only through a chart hook Job |
| `temporal workflow cancel` / `signal` | with approval (cancel is recoverable) |
| `temporal workflow terminate`, `operator namespace delete` | approval, and expect data loss |
| `kubectl delete pod/job`, `scale`, `rollout restart` | no — let Argo reconcile |
| SQL or `temporal-sql-tool` by hand | no |
