# Workers

Two patterns exist. Which one an app uses is decided by its manifests, not by preference.

## A. In-process worker (Deployment)

The worker runs inside the application pod; Argo and the Deployment's `replicas` own scaling.

| App | Namespace | Task queue | Notes |
|---|---|---|---|
| `rots-web` authserver | `rots` / `rots-preview` | `rots-prod` / `rots-pr-<N>` | hosts the fleet-coordinator and per-login session workflows; `TEMPORAL_*` from `workloads/rots-web/values.yaml` |
| `steam-lobby` | `pvp` / `pvp-preview` | `lobby` | task queues isolate previews inside one shared namespace |
| `imageserver` | `default` | app-defined | `TEMPORAL_ADDRESS` only, SDK default namespace |

These scale on CPU/RPS like any other pod. Their failure mode is an app log line, not a controller
condition — check the pod before blaming Temporal.

## B. WorkerDeployments (temporal-worker-controller)

`frigate-genai` runs four — `frigate-genai-ffmpeg`, `-gemini`, `-ollama`, `-triggers`, task queues
`genai-tasks-<name>`, namespace `default` — and `john2143-worker` runs one:
`john2143-com-worker`, namespace `john2143-com`, task queue `john2143-com`, connection
`john2143-temporal`.

Unusual on `john2143-com-worker`, both deliberate:

- `rollout.strategy: AllAtOnce` — no rainbow deploy, the old build goes away immediately.
- `sunset: {scaledownDelay: 10m, deleteDelay: 1h}` — how long a retired build keeps its pods.

Objects live in two places:

- Kubernetes namespace `temporal-system`: `deploy/twc-manager`
  (`temporalio/temporal-worker-controller:v1.13.0`), the `temporal.io` CRDs, the controller
  webhook served with a cert-manager certificate.
- Kubernetes namespace `default`: the `Connection` (`frigate-genai-temporal` →
  `temporal-frontend.default.svc.cluster.local:7233`), one `WorkerDeployment` and one
  `WorkerResourceTemplate` per worker. The CRDs are in
  `workloads/temporal-worker-controller/crds.yaml`; the app manifests in `workloads/frigate-genai/`.

How the pieces fit:

1. `WorkerDeployment.spec.workerOptions.unsafeCustomBuildID` names the build (CI rewrites it on each
   image bump together with `TEMPORAL_WORKER_BUILD_ID`).
2. The controller launches versioned worker pods for that build ID.
3. `WorkerResourceTemplate` renders a KEDA `ScaledObject` per version — the temporal scaler watches
   the task queue (`targetQueueSize`, `activationTargetQueueSize`, `queueTypes: activity`) and scales
   the version's pods, `minReplicaCount: 0` so an idle version costs nothing.
4. `apps/frigate-genai.yaml` ignores `/spec/replicas` and `/spec/workerOptions/unsafeCustomBuildID`,
   because the controller and KEDA own both. See `invariants.md` §6.

Worker code must declare versioning (`deployment_config` with `VersioningBehavior.PINNED`) and read
`TEMPORAL_DEPLOYMENT_NAME` / `TEMPORAL_WORKER_BUILD_ID`; a worker without `deployment_config`
runs unversioned and never appears under a WorkerDeployment.

## Versioning and promotion

Temporal serves a version while pinned workflows still need it — the "rainbow deploy". A new build
does not take traffic until it is **promoted to current**; the `CURRENT` column in the UI stays empty
until then, which is normal immediately after a rollout and suspicious an hour later.

```bash
temporal worker deployment describe --name frigate-genai-ffmpeg --namespace default
temporal task-queue describe --task-queue genai-tasks-ffmpeg --task-queue-type activity --namespace default
```

Promotion is a UI click (Worker Deployments → set current version) or
`temporal worker deployment set-current-version --deployment-name <name> --build-id <id>`. It
refuses when an expected task queue is not yet polled by the new version — that refusal is a
symptom of a worker that will not poll, not of the promotion. Old versions are retired by
`workloads/frigate-genai/worker-version-prune.yaml`; never prune while workflows are pinned.

## Debugging "nothing executes"

1. Is the task queue receiving tasks? `temporal task-queue describe` — a growing
   `ApproximateBacklogCount` with zero pollers means no worker is polling.
2. Are there polls at all? Same output, `Pollers` section — only meaningful if the deployment has
   replicas: with `minReplicaCount: 0` an idle queue legitimately has zero pollers and shows one
   all-zero `UNVERSIONED` statistics row. Compare with
   `kubectl -n default get deploy | grep <worker>-<build>`.
3. Pods stuck at 0 while the backlog grows? `get scaledobject` and `get hpa` — the scaler activates
   on queue size, so a queue name that does not match the worker's keeps replicas at 0 forever.
4. WorkerDeployment `CURRENT` empty after a rollout? No promotion yet.
5. `twc-manager` logs / webhook `x509` errors: the controller's cert-manager certificate is the
   problem, not the workers.

```bash
ssh closet.local 'kubectl -n default get workerdeployments,workeresourcetemplates,scaledobjects'
ssh closet.local 'kubectl -n temporal-system logs deploy/twc-manager --tail=200'
ssh closet.local 'kubectl -n default describe workerdeployment frigate-genai-ffmpeg'
```

## History

`~/repos/argo/docs/worker-deployment-handoff.md` covers the migration mid-flight and is still useful
for the object map and the CI rewrite rules, but its status section is stale: the migration is merged
on `main`. Trust the manifests over its "pending" list.
