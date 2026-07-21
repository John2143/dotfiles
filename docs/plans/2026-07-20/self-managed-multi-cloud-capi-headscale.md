## Context

The current architecture spans three clusters (home k3s, DOKS, planned GKE) with no unified control plane access and mixed node management strategies. DOKS provides free managed control plane but limits OS/k8s version control. GKE offers spot instances for cost savings but adds another managed platform. The home cluster runs self-managed k3s with full control.

This plan defines a unified self-managed architecture: k3s + Cluster API (CAPI) on every cloud, one Headscale VPN for all kube-apiserver access, identical node images everywhere, and cloud-native autoscaling without managed K8s tax.

## CAPI — What It Is

Cluster API is a Kubernetes operator that manages the lifecycle of Kubernetes clusters. It treats clusters as custom resources — you define a `Cluster`, `MachineDeployment`, and `MachineTemplate` in YAML, and CAPI provisions the infrastructure, bootstraps nodes, and joins them to the control plane.

```
You declare:                          CAPI executes:
┌──────────────────────────┐         ┌──────────────────────────────┐
│ apiVersion: cluster.x-k8s│         │ 1. Create 3 DO droplets      │
│ kind: MachineDeployment  │         │ 2. Cloud-init installs k3s   │
│ spec:                    │         │ 3. k3s agent joins cluster   │
│   replicas: 3            │  ───►   │ 4. Health check passes       │
│   strategy:              │         │ 5. Node reports Ready        │
│     type: RollingUpdate  │         │                              │
│   template:              │         │ Autoscaler bumps replicas→5: │
│     spec:                │         │ 6. Create 2 more droplets    │
│       image: nixos-k3s   │         │ 7. Join, Ready              │
│       instanceType: s-2  │         │                              │
└──────────────────────────┘         └──────────────────────────────┘
```

### CAPI Architecture

A CAPI deployment has two layers:

**Management cluster** — runs the CAPI controllers. This can be a small $6/mo droplet running k3s. It watches `Cluster` and `Machine` resources and calls cloud APIs (DO, GCP, etc.) to provision infrastructure. It does NOT run workloads — it's a control plane for the control planes.

**Workload clusters** — the actual clusters where your services run. CAPI bootstraps them from a machine image, installs k3s, and hands off to cluster-autoscaler for day-2 scaling.

```
Management cluster ($6/mo droplet)
┌────────────────────────────────────────┐
│ CAPI controllers:                      │
│  ├─ core (Cluster, Machine, MachineSet)│
│  ├─ bootstrap (k3s, cloud-init)        │
│  ├─ control-plane (k3s server)         │
│  └─ infrastructure (DO, GCP providers) │
│                                        │
│ Declares and manages:                  │
│  ┌──────────────────────────┐          │
│  │ Workload cluster "do-nyc"│          │
│  │ ├─ K3sControlPlane: 3    │          │
│  │ ├─ MachineDeployment:    │          │
│  │ │    pool-general: 2→10  │          │
│  │ └─ MachineDeployment:    │          │
│  │      pool-gpu: 0→5       │          │
│  └──────────────────────────┘          │
│  ┌──────────────────────────┐          │
│  │ Workload cluster "gcp-us"│          │
│  │ └─ ...                   │          │
│  └──────────────────────────┘          │
└────────────────────────────────────────┘
```

### How Autoscaling Works

1. **cluster-autoscaler** runs inside the workload cluster (standard, free).
2. It watches for pending pods → calculates needed nodes → bumps `MachineDeployment.spec.replicas` via the CAPI `ClusterAutoscaler` annotation.
3. CAPI controller sees the replica change → calls DO API (`POST /v2/droplets`) → droplet boots with cloud-init → k3s joins → pod schedules.
4. Scale-down: idle for 10 min → cluster-autoscaler drains the node → decrements `MachineDeployment.replicas` → CAPI calls `DELETE /v2/droplets/<id>`.

No node pool configuration in the cloud console. No manual Terraform apply. Declarative YAML, GitOps-compatible.

### Infrastructure Providers

CAPI has providers for every major cloud:

| Provider | Status | Notes |
|---|---|---|
| **DigitalOcean (CAPDO)** | Mature, CNCF-incubating | Provisions droplets, load balancers, volumes |
| **GCP (CAPG)** | Mature | Provisions VMs, supports spot/preemptible |
| **Hetzner (CAPH)** | Community, active | Provisions cloud servers, block storage |
| **AWS (CAPA)** | Mature, widely used | Provisions EC2, EBS, ELB |

Each provider is a separate controller deployed to the management cluster. Same API (`MachineDeployment`), different infrastructure backend.

### Machine Images

CAPI uses machine images — you build an OS image once and CAPI provisions nodes from it. Options:

| Approach | Build time | Boot time | Control |
|---|---|---|---|
| **NixOS image** (nixos-generators) | Single command, reproducible | ~30s boot | Full — identical to home nodes |
| **Ubuntu + cloud-init** | None (use DO marketplace) | ~60s boot | cloud-init scripts, drift risk |
| **Flatcar Container Linux** | None (use existing image) | ~30s boot | Immutable, auto-updating |

NixOS is the right choice here: same OS as home cluster, same kernel, same k3s version, same Cilium config. One `flake.nix` builds identical images for DO, GCP, and Hetzner.

## Target Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Headscale (home cluster)                │
│                   Single tailnet                         │
│                   ACLs, DNS, route distribution          │
└──────┬───────────────────┬───────────────────┬──────────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Home (k3s)   │   │ DO (k3s)     │   │ GCP (k3s)    │
│ Physical     │   │ CAPI-managed │   │ CAPI-managed │
│ 5 nodes      │   │ 2→10 nodes   │   │ 2→10 nodes   │
│              │   │              │   │              │
│ Runs:        │   │ Runs:        │   │ Runs:        │
│  Headscale   │   │  imageserver │   │  MongoDB     │
│  Temporal    │   │  Temporal    │   │  Future svcs │
│  frigate     │   │   workers    │   │              │
│  litellm     │   │  DERP relay  │   │              │
│  HA/home     │   │  Tor relay   │   │              │
│              │   │  Egress node │   │              │
│              │   │              │   │              │
│ API via:     │   │ API via:     │   │ API via:     │
│  Headscale   │   │  Headscale   │   │  Headscale   │
│  subnet      │   │  proxy pod   │   │  proxy pod   │
│  route       │   │  on gateway  │   │  on gateway  │
└──────────────┘   └──────────────┘   └──────────────┘
```

### Kube API Access Through Headscale

Each cluster exposes its kube-apiserver through one Headscale-connected proxy:

**Home cluster** — kube-apiserver is on `192.168.5.10:6443`. A Headscale subnet router (already running on home network) advertises `192.168.5.0/24`. Any Tailscale device with `--accept-routes` can `kubectl` directly. No proxy pod needed.

**DO cluster** — kube-apiserver is at a private IP inside DO's VPC. A Headscale client pod on a gateway node runs a TCP proxy (`socat TCP-LISTEN:6443,fork TCP:<kube-apiserver-ip>:6443`). This pod joins Headscale with hostname `do-k8s-api`. `kubectl` targets `https://do-k8s-api:6443`.

**GCP cluster** — same pattern as DO. Headscale client + TCP proxy.

```yaml
# ~/.kube/config after setup
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: <home-ca>
    server: https://192.168.5.10:6443
  name: home
- cluster:
    certificate-authority-data: <do-ca>
    server: https://do-k8s-api:6443
  name: do-nyc
- cluster:
    certificate-authority-data: <gcp-ca>
    server: https://gcp-k8s-api:6443
  name: gcp-us
```

### Network: East-West Between Clusters

Services talk to each other over Tailscale IPs, never public DNS:

| Source | Target | Address |
|---|---|---|
| frigate-genai-worker (home) | Temporal frontend (home) | `temporal.ts.net:7233` |
| frigate-genai-worker (DO) | Temporal frontend (home) | `temporal.ts.net:7233` |
| john2143-com worker (home) | MongoDB (GCP) | `mongo.ts.net:27017` |
| imageserver (DO) | MongoDB (GCP) | `mongo.ts.net:27017` |

Bursty workloads (frigate-genai workers) can run on DO or GCP where autoscaling handles the load. Stateful workloads (Temporal DB, MongoDB) stay pinned or have clear failover paths.

### Cost Model

| Component | Monthly Cost |
|---|---|
| **Home cluster** (5 physical nodes) | Power only (~$30/mo) |
| **DO workload cluster** | Droplets only — $24/node × 2-10 nodes = $48–240/mo |
| **DO management cluster** | 1 × $6 droplet for CAPI = $6/mo |
| **GCP workload cluster** | Spot e2-small × 2-10 nodes = $10–50/mo (spot avg) |
| **Headscale** | Runs on home cluster = $0 |
| **Kube API proxies** | 2 small pods per cloud = negligible |
| **Cross-cloud egress** | Tailscale tunnels = $0 (only control traffic) |
| **Total (3-cloud baseline)** | **~$100–300/mo** (scales with load) |

### Autoscaling Behavior Per Cloud

| Event | DO | GCP |
|---|---|---|
| Frigate event burst | KEDA scales workers 0→15 pods | KEDA scales workers 0→15 pods |
| Pods pending (no room) | cluster-autoscaler sees pending pods | cluster-autoscaler sees pending pods |
| Node provisioning | CAPI → DO API → droplet in ~60s | CAPI → GCP API → spot VM in ~90s |
| Node joins cluster | k3s agent, Cilium install, Ready in ~30s | Same |
| Pods schedule | Immediately | Immediately |
| Burst ends, idle 10min | CAPI drains → deletes droplet → cost stops | Same |

## Approach

### Phase 1: CAPI Management Cluster

- Provision a $6/mo DO droplet (`s-1vcpu-1gb`) running k3s.
- Install CAPI core controllers: `cluster-api`, `bootstrap-k3s`, `control-plane-k3s`.
- Install the DO infrastructure provider (`cluster-api-provider-digitalocean`).
- Generate a DO API token with droplet/load-balancer/volume scopes.
- Store token as a Kubernetes Secret on the management cluster.
- Install Flux on the management cluster to GitOps the workload cluster definitions.

### Phase 2: DO Workload Cluster

- Define a `K3sControlPlane` with 3 replicas (HA embedded etcd).
- Define `MachineDeployment` for worker pool: `s-2vcpu-4gb`, min 2 max 10, NixOS image.
- Install Cilium as CNI (same config as home cluster).
- Install cluster-autoscaler with CAPI annotations.
- Install KEDA for pod-level scaling.
- Deploy the Headscale proxy pod on a gateway node for kube API access.
- Register with ArgoCD or Flux for workload GitOps.

### Phase 3: Migrate Services from DOKS

- Deploy imageserver and its ingress to the new DO workload cluster.
- Deploy DERP relay and Tor relay.
- Update public DNS for `up.brick.gay`, `2143.moe`, `devolved.us`.
- Cut over traffic. Decommission DOKS node pool.

**Important:** MongoDB on DOKS is NOT migrated to the DO workload cluster. MongoDB moves to GCP (Phase 4) or stays on DOKS as a temporary measure. The DO workload cluster runs stateless services only.

### Phase 4: GCP Workload Cluster (Future)

- Install CAPI GCP provider on the management cluster.
- Define workload cluster with spot VM pool (e2-small, burst) + on-demand baseline (e2-medium, stable).
- Migrate MongoDB from DOKS to GCP. Target: MongoDB 7.0, bind to Tailscale IP only.
- Wire up MongoDB ACL in Headscale (`tag:mongodb` → `tag:imageserver`, `tag:worker`).

### Phase 5: Home Cluster Integration

- Ensure home k3s nodes have Tailscale with subnet routing for `192.168.5.0/24`.
- Register home cluster in CAPI management cluster (optional — physical nodes can't be CAPI-managed, but the cluster can be registered for visibility and kubeconfig distribution).
- Deploy Headscale proxy pod for kube API if subnet routing isn't sufficient.

## Notes & Open Decisions

### Stateful Workload Placement

| Workload | Where it lives | Why |
|---|---|---|
| **CNPG (Temporal DB)** | Home cluster | Low-latency access for frigate-genai workers. Physical nodes for predictable I/O. |
| **MongoDB** | GCP (future) | Isolate from home blast radius. GCP spot + on-demand mix for cost. Tailscale-only network binding. |
| **SeaweedFS** | Home cluster | Bulk object storage. Physical HDDs on NAS. Too expensive to replicate across clouds. |
| **Litellm DB** | Home cluster | CNPG-managed. Low volume. |
| **Imageserver PVC** | DO workload | Ephemeral upload cache. CAPI can attach DO volumes. |

### Service Mesh Decision

Linkerd currently runs on both clusters but is broken on DO (expired certs, ECDSA verification failure). Decision: **Drop Linkerd entirely.**

- Tailscale/WireGuard already provides end-to-end encryption between services across clouds.
- Cilium provides NetworkPolicy enforcement within each cluster (defense-in-depth).
- Linkerd adds operational overhead (cert rotation, control plane maintenance, sidecar injection) without adding security the other layers don't already cover.
- Revisit if L7 traffic policies (rate limiting, circuit breaking, traffic splitting) become necessary. At current scale, they're not.

### GitOps Tooling

| Cluster | Tool | Rationale |
|---|---|---|
| Home | ArgoCD | Already running. Keep for historical continuity. |
| DO workload | Flux | Pre-existing on current DOKS. Consistent with `2143-k8s` repo structure. |
| GCP workload | Flux | Same as DO — Flux per cluster, no central ArgoCD SPOF. |
| CAPI management | Flux | GitOps the cluster definitions themselves. |

### Secrets & Certificates

- **SOPS** (age-encrypted) for Git-stored bootstrap secrets: CAPI tokens, Tailscale auth keys, initial k3s tokens.
- **External Secrets Operator** for cloud-provider secrets: DO Spaces keys, GCP service accounts.
- **cert-manager** on every cluster for internal PKI and public TLS (Let's Encrypt). Already deployed on both clusters.
- **No plaintext secrets in Git repos.** Everything encrypted at rest.

### Observability

- **Loki** (already deployed) for centralized log aggregation across all clusters.
- **Prometheus** (already running on DOKS as kube-prometheus-stack) per cluster.
- **Grafana** (already deployed) as the unified dashboard.
- **Tempo** for distributed tracing if cross-cluster request flows become complex enough to need it.

### DO vs GCP Tradeoffs

| Concern | DO | GCP |
|---|---|---|
| Spot/preemptible | No — all droplets bill at full rate | Yes — up to 91% discount on e2 spot |
| Autoscaling maturity | Mature, CA is built-in and solid | Mature, CA + Capacity Advisor for spot |
| Egress cost | $0.01/GB — 8-12× cheaper than GCP | $0.085–$0.12/GB — expensive |
| Simplicity | One pricing model, no surprises | Spot preemption, CUDs, tiered egress |
| CAPI provider | Mature (CAPDO) | Mature (CAPG) |

**Strategy:** DO for baseline stateless workloads (imageserver, relays). GCP for burst + cost-sensitive workloads (MongoDB, future services). Keep cross-cloud traffic minimal — only MongoDB queries over Tailscale, not bulk data.

## Critical Files & Anchors

1. **NixOS machine image** — `dotfiles/nixos/modules/k3s-node.nix` or similar — defines the OS, kernel, k3s binary, and Cilium config for all cloud nodes.
2. **CAPI resource definitions** — new files in `2143-k8s/management/` or similar — YAML for `Cluster`, `K3sControlPlane`, `MachineDeployment`, `MachineTemplate`.
3. **Headscale ACLs** — `2143-k8s/base/headscale-acl.yaml` — permissive tags for each cluster's k8s-api proxy.
4. **Headscale proxy Deployments** — one per cloud cluster, running Tailscale client + socat proxy.
5. **`~/.kube/config`** — updated with Headscale-resolvable cluster endpoints.

## Verification

```bash
# Management cluster is healthy
KUBECONFIG=mgmt.kubeconfig kubectl get clusters -A
# Expected: do-nyc READY, gcp-us READY

# CAPI MachineDeployments are scalable
KUBECONFIG=mgmt.kubeconfig kubectl scale machinedeployment pool-general --replicas=3
# Expected: 3 droplets appear in DO console, join cluster, report Ready

# Autoscaling works end to end
KUBECONFIG=do.kubeconfig kubectl run test --image=busybox --restart=Never -- sleep 9999
kubectl scale deploy frigate-genai-ffmpeg --replicas=20
# Expected: cluster-autoscaler logs show scale-up, new node appears, pods schedule

# Kube APIs reachable via Headscale
curl -sk https://do-k8s-api:6443/healthz  # ok
curl -sk https://gcp-k8s-api:6443/healthz # ok
kubectl --context do-nyc get nodes        # works from laptop
kubectl --context gcp-us get nodes        # works from laptop
kubectl --context home get nodes          # works from laptop

# MongoDB reachable only via Tailscale
# From DO cluster pod:
nc -zv mongo.ts.net 27017  # Connection succeeded
# From public internet:
nc -zv mongo.ts.net 27017  # Connection refused (no DNS, no route)
```

## Assumptions & Contingencies

- **CAPI cluster-api-provider-digitalocean** is actively maintained. If it lags behind DO API changes, fall back to Terraform per-cluster with `k3s` manual join — lose autoscaling, keep self-managed nodes.
- **NixOS cloud images** build correctly for DO (custom image upload). If DO doesn't support custom images on basic droplets, fall back to Ubuntu + cloud-init with k3s install script. NixOS is preferred but not mandatory.
- **Headscale MagicDNS** resolves across all clusters. If DNS doesn't reach between clouds reliably, use Tailscale IPs directly (`100.x.x.x`) for kube API endpoints instead of hostnames.
- **CAPI management cluster is a SPOF.** If the $6 droplet dies, workload clusters keep running (CAPI is **day 0-1 only** — existing nodes don't need the management cluster). To restore: reprovision management cluster, re-import `Cluster` resources, CAPI reconciles to current state. Acceptable for SMB; add management cluster HA if uptime SLA exceeds 99.9%.
- **cluster-autoscaler + CAPI** require the `cluster.x-k8s.io/cluster-name` annotation on MachineDeployments. If the autoscaler doesn't pick up MachineDeployments, verify the annotation and that the autoscaler runs with `--cloud-provider=clusterapi`.
