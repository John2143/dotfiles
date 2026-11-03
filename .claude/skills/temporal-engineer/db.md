# Database

`workloads/temporal-db/cnpg-cluster.yaml`, CloudNativePG on `longhorn-cnpg`, Kubernetes namespace
`default`. The server connects through the CNPG services, never to a particular instance.

| Service | Use |
|---|---|
| `temporal-db-rw:5432` | writable primary — what `apps/temporal.yaml` connects to |
| `temporal-db-ro:5432` | read replica |
| `temporal-db-r:5432` | any instance |

`datastores.default.connectAddr` and `datastores.visibility.connectAddr` are both
`temporal-db-rw:5432`; `existingSecret: temporal-db-app` supplies the password at runtime, so a
password rotation needs no manifest change and no restart ordering.

## Shape

- 2 instances (primary + one synchronous standby), PostgreSQL 16.6.
- Guaranteed QoS (`requests == limits`: 1 CPU, 1Gi), required pod anti-affinity on
  `kubernetes.io/hostname`, node `arch` excluded, preferred `big`/`closet`.
- 5Gi data + 4Gi WAL, both `longhorn-cnpg`. `primaryUpdateMethod: switchover` — a chart/image change
  promotes the standby instead of restarting the primary in place.
- `pg_hba` is `scram-sha-256` for `0.0.0.0/0`: no TLS, no client certs. The cluster is only
  reachable in-cluster (ClusterIP), so treat network reachability as the auth boundary.

Rationale, and what must not change: `invariants.md` §5.

## Databases and roles

| Object | Name |
|---|---|
| default store database | `temporal` (owner `temporal`) |
| visibility store database | `temporal_visibility`, created by `bootstrap.initdb.postInitSQL` |
| application role | `temporal`, login, password in `temporal-db-password` |
| application secret | `temporal-db-app` (key `password`) — what the server reads |

The visibility database exists only because of that `postInitSQL`; a cluster rebuilt without it
leaves the server failing on visibility writes.

## Schema

Two stores, both `pluginName: postgres12`, both `manageSchema: true`. Schema is applied by the
chart's PreSync hook Job (`setup-schema -v 0.0` then `update-schema`), versioned to the chart
release. That hook is the only supported path.

- Never run `temporal-sql-tool` by hand, and never edit the schema-version tables.
- A chart bump changes the target schema version; the hook migrates on the next sync. If it fails,
  the sync fails and serving continues on the old schema — read the hook logs (`failures.md` §hook)
  rather than forcing the version.
- Rolling the chart backwards past a schema version that already applied is not automatic. Treat it
  like a database downgrade: requires a restore.

`numHistoryShards: 512` is fixed at bootstrap and immutable thereafter (`invariants.md` §3).

## Backups — there are none

`grep -rn 'ScheduledBackup\|barmanObjectStore' workloads/temporal-db apps/temporal-db.yaml` returns
nothing. Recovery today is: Longhorn replica redundancy, plus whatever survives a node outage. That
is availability, not backup — it does not cover operator error, a bad migration, or deletion of the
cluster.

Practical consequences:

- Never delete or rebuild `temporal-db` to "start clean"; it is the only copy of every workflow
  history.
- Before any schema upgrade or instance-count change, take a logical dump out of band.
- Adding a `ScheduledBackup` + object-store credentials is a genuine improvement and belongs as a
  new file under `workloads/temporal-db/` registered by `apps/temporal-db.yaml`.

## Diagnosing

```bash
ssh closet.local 'kubectl -n default get cluster temporal-db'
ssh closet.local 'kubectl -n default get pods -l cnpg.io/cluster=temporal-db -o wide'
ssh closet.local 'kubectl -n default describe cluster temporal-db | sed -n "/Status/,/Events/p"'
ssh closet.local 'kubectl -n default get events --field-selector involvedObject.name=temporal-db --sort-by=.lastTimestamp'
```

| Symptom | Meaning |
|---|---|
| `Cluster in healthy state` but `temporal-db-rw` unresolved | endpoints/label mismatch — check the CNPG operator pod first |
| instance `Pending` | anti-affinity with only one schedulable node, or an unschedulable Longhorn volume |
| repeated `switchover` | primary losing its node or volume; check Longhorn volume health, not Temporal |
| `CrashLoopBackOff` on `temporal-frontend`/`history` with SQL errors | database not accepting connections; the server is a victim |
| one instance gone after a node outage | rebuild it as a fresh clone of the primary; do not try to recover faulted Longhorn volumes |

Longhorn health is the usual cause of "Temporal is down". Check volumes before touching Temporal
configuration: `~/repos/argo/docs/k3s-store-paths.md`,
`~/repos/argo/docs/2026-10-18-db-replicas-and-storage-headroom.md`.
