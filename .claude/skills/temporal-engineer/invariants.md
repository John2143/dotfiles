# Invariants

Each of these was set deliberately after an incident. Reverting one reproduces the incident.
Read this before editing `apps/temporal.yaml` or the CNPG cluster.

## 1. The schema Job must stay a Helm hook

`apps/temporal.yaml` sets `schema.useHelmHooks: true`.

With hooks disabled the chart renders `Job/temporal-schema-<ver>` as a normal tracked resource
with `ttlSecondsAfterFinished: 86400`. The TTL deletes the finished Job → Argo reports it
`Missing` → the app is permanently `OutOfSync` → the resync recreates it through `Replace`, which
fails with `spec.selector: Required value … field is immutable` because the manifest has no
API-generated selector. Argo does not retry a failed sync at the same revision, so the app sits
wedged with a failed last operation indefinitely.

As a hook, it becomes a PreSync with `BeforeHookCreation,HookSucceeded`: excluded from
sync-status comparison (no wedge), deleted on success (re-runs every sync), and the migration is
idempotent (`setup-schema -v 0.0` then `update-schema`), so re-running is safe. It also re-reads
`temporal-db-app/password` each run, so a rotated password needs no extra step.

Corollaries:

- Do **not** add `argocd.argoproj.io/hook` annotations to this chart. Per the Argo CD Helm docs,
  defining any Argo hook makes **all** Helm hooks ignored — that reintroduces the wedge.
- Do **not** restore `syncPolicy.syncOptions: [Replace=true]`. It never fixed the immutability
  error; it is the mechanism that produced it.
- `backoffLimit: 5` and `activeDeadlineSeconds: 1800` are the guard against a failing hook holding
  a sync `Running` for hours (chart default: 100 retries, no deadline).

Long form: `~/repos/argo/docs/2026-10-04-temporal-schema-hook.md`.

## 2. `metrics.breakdownByBuildID: false`

Without it the server emits one metrics series set per WorkerDeployment build ID. Four workers
redeploying regularly grew ~3,000 series per deploy and pushed Mimir past its 500k limit; the
stale series persist until the emitting pod restarts, so the limit stays breached long after the
deployment is gone. It also disables per-queue backlog gauges for **versioned** queues — nothing
reads them.

Do not re-enable unless you have both a retention story and a Mimir headroom measurement.
Upstream: `temporalio/temporal#9945`.

## 3. `numHistoryShards: 512`

Fixed at bootstrap. Changing it on a populated cluster corrupts history routing; changing it
requires an empty database. Treat like a database fork, not a config value.

## 4. The frontend IP is pinned twice

`metallb.io/loadBalancerIPs: "192.168.6.20"` in `apps/temporal.yaml` **and** the
`temporal-grpc.john2143.com` entry in the `workloads/lan-dns/configmap.yaml` hosts block. Use the
annotation, never `spec.loadBalancerIP`. Changing one alone breaks LAN workers with an error that
looks like a worker bug.

## 5. CNPG shape is Guaranteed QoS on purpose

`workloads/temporal-db/cnpg-cluster.yaml`: 2 instances, `requests == limits` for CPU and memory,
required pod anti-affinity, node `arch` excluded, `primaryUpdateMethod: switchover`, 5Gi data +
4Gi WAL on `longhorn-cnpg`.

- Guaranteed pins `oom_score_adj` at -997 so node pressure kills other pods first. Dropping to
  burstable quietly undoes that.
- 1 core is ~2.8x the observed p99 and was chosen after a 500m ceiling throttled it.
- The anti-affinity is `required`: both instances on one node defeats the point.
- `arch` is excluded because it is the node that faulted the old volumes.

Never scale to 1, never make the limits burstable, never move a volume to a different class
without a backup — there is no CNPG backup configured (see `db.md`).

## 6. `ignoreDifferences` on WorkerDeployments

`apps/frigate-genai.yaml` ignores `/spec/replicas` and `/spec/workerOptions/unsafeCustomBuildID` on
`temporal.io/WorkerDeployment`. The controller and the KEDA ScaledObjects own them; CI rewrites the
build ID. Remove the ignore and the app flaps `OutOfSync` forever — `selfHeal` then fights the
controller.

`apps/john2143-worker.yaml` ignores the same two pointers. The trap: because the build ID is
ignored, a commit whose only change is the build ID produces no diff and **does not sync**. The
`john2143.com/build-id-sync` annotation on `workloads/john2143-worker/workerdeployment.yaml` exists
to be bumped alongside such a change — bump it or the rollout never happens.

## 7. Namespace registration is a Sync hook with `HookSucceeded`

`workloads/rots-web/templates/temporal-namespace-job.yaml`,
`workloads/steam-lobby-preview/templates/init-job.yaml`. Both hooks run `describe || create` at
`sync-wave: "-1"`. The `HookSucceeded` delete policy is the part that matters: a completed Job left
tracked is deleted and its old result reused, so a rebuilt Temporal never gets its namespace back.

Rules, rationale and the copyable pattern: `namespaces.md`.
