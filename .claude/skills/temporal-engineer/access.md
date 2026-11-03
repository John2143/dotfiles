# Access

Everything here is read-only. Anything that writes is listed in `SKILL.md` under constraints.

## Topology

Namespace `default`, all managed by Argo CD from `apps/temporal.yaml` (chart `temporal` 1.7.0).

| Deployment | Role |
|---|---|
| `temporal-frontend` | gRPC :7233 — every client and worker connects here |
| `temporal-history` | history shards (512) |
| `temporal-matching` | task queues |
| `temporal-worker` | system/internal workflows |
| `temporal-web` | UI :8080 |
| `temporal-admintools` | long-running pod carrying the `temporal` CLI |
| `oauth2-proxy-temporal` | :4180, fronts the public UI route |
| `temporal-db` (CNPG) | `temporal-db-rw/-ro/-r` — see `db.md` |

The worker controller is separate: namespace `temporal-system`, `deploy/twc-manager` — see
`workers.md`.

## In-cluster (preferred)

```bash
ssh closet.local 'kubectl -n default get pods -l app.kubernetes.io/name=temporal -o wide'
ssh closet.local 'kubectl -n default get endpoints temporal-frontend'
```

Clients use plaintext gRPC — `TEMPORAL_ADDRESS=http://temporal-frontend.default.svc.cluster.local:7233`
(the `http://` prefix is what the Go SDK wants for an unencrypted connection). There is no TLS and
no auth server in this deployment.

## CLI

Not installed on this workstation — `command -v temporal` is empty. Two paths that work:

```bash
# from the workstation: LAN gRPC to the frontend LoadBalancer, no ssh needed
nix run nixpkgs#temporal-cli -- --address 192.168.6.20:7233 operator namespace list

# from anywhere with cluster access: the CLI baked into the pod (admin-tools 1.32.0)
ssh closet.local 'kubectl -n default exec deploy/temporal-admintools -- \
  temporal --address temporal-frontend.default.svc:7233 operator namespace list'
```

`--address` is a global flag and must precede the subcommand; `TEMPORAL_ADDRESS` as an env var
works too. Namespaces and task queues mean nothing without it. CLI/server version skew does not
affect `list`/`describe`/`show`; prefer the pod for anything that writes.

Useful read-only commands:

```bash
temporal operator namespace list                      # namespaces + retention
temporal workflow list --namespace <ns> -q 'ExecutionStatus="Running"'
temporal workflow show -w <workflow-id> --namespace <ns>      # event history, the useful one
temporal task-queue describe --task-queue <q> --task-queue-type activity --namespace <ns>
temporal worker deployment describe --name <deployment> --namespace <ns>
```

`tctl` is removed upstream, but two manifests still tell you to run it (`steam-lobby`,
the rots namespace Job). Ignore them; use `temporal operator …`.

## UI

| Host | Path |
|---|---|
| `temporal.ts.2143.me` | LAN only (`lan-only` middleware) + security headers, straight to `temporal-web` |
| `temporal.john2143.com` | public, through `oauth2-proxy-temporal` and the public rate/in-flight limits |

`temporal.ts.2143.me` has no authentication of its own — the LAN-only middleware is the control.
Do not remove it, and do not add a public route to `temporal-web`.

Both routes are HTTPRouter objects in `workloads/temporal-routes/httproute.yaml`.

## gRPC from outside the cluster

`temporal-frontend` is a `LoadBalancer` pinned to **192.168.6.20** by
`metallb.io/loadBalancerIPs` in `apps/temporal.yaml`, and that same IP is pinned in the
`workloads/lan-dns/configmap.yaml` hosts block as `temporal-grpc.john2143.com`. **Change both
together** or SDKs on the LAN break while the Service still looks healthy.

`workloads/temporal-routes/tlsroute.yaml` exists but cannot work: it terminates TLS and hands
plaintext to the frontend. That is why the gRPC name is a DNS pin rather than a gateway route —
do not "fix" the TLSRoute without also giving the frontend real TLS.

Connection from a LAN host: `192.168.6.20:7233`, plaintext, no auth.

## Metrics and logs

- Metrics: Alloy `prometheus.scrape "temporal"` (`workloads/alloy/values-prod.yaml`) discovers pods
  labelled `app.kubernetes.io/name=temporal`, keeps `frontend|history|matching|worker`, and forces
  `<podIP>:9090` because the pods do not declare the container port. Mimir job label: `temporal`.
- Logs: Loki. Query `{namespace="default"} |= "temporal"` for container stdout; Traefik access logs
  answer "who called the UI". The query recipe (gateway host, time flags) is in the argo-engineer
  skill — do not re-derive it here.

## Credentials

| Secret | Holds | Use |
|---|---|---|
| `temporal-db-app` | `password` for role `temporal` | consumed by the server and the schema hook |
| `temporal-db-password` | same password at bootstrap | CNPG role provisioning |
| `secrets/default-oauth2-proxy-temporal.yaml` (sealed) | oauth2 client id/secret, cookie secret | public UI login |

Read a secret only into a file, never onto a command line:

```bash
ssh closet.local 'kubectl -n default get secret temporal-db-app -o jsonpath="{.data.password}"' \
  | base64 -d > /tmp/pg.pass; chmod 600 /tmp/pg.pass
```

The UI's oauth2 login is not evidence of Temporal auth — the cluster-internal API is
unauthenticated by design. Anything that can reach `192.168.6.20:7233` can do anything.
