# Hosting Next Steps: Enterprise HA Platform on Hetzner

**Status**: Plan (pre-implementation). To be refined via plan mode.

---

## 1. Target Architecture

6 symmetric k3s nodes + 1 Home Pi across 3 regions, all Hetzner:

| Region | Nodes | Plan | Per-node | Per-region |
|--------|-------|------|----------|------------|
| **Ashburn, VA** | server + agent | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 | $49.98 |
| **Hillsboro, OR** | server + agent | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 | $49.98 |
| **Nuremberg, DE** | server + agent | CPX32 (8GB / 4 vCPU / 160GB) | ~$15.20 | ~$30.40 |
| **Home** | Raspberry Pi | PowerDNS #3, Uptime Kuma, RustFS | — | $0 + power |

All 6 nodes symmetrically sized. Any node can run the full workload for its region. SeaweedFS uses local SSD (10GB per node, 3-way replication). B2 serves the full corpus with local hot cache.

**LA mode**: 3 server nodes (~$75/mo). **HA mode**: 6 nodes (~$140/mo). Toggle via agent node provisioning/destruction.

Full stack: NixOS / k3s / Cilium / Istio / Traefik+CrowdSec / k8gb+PowerDNS(MariaDB Galera)+ExternalDNS(RFC2136) / Bunny CDN(GeoIP) / SeaweedFS(local SSD,10GB,encrypted) / B2(rclone crypt) / Longhorn / MongoDB(`--enableEncryption`,active-passive) / CloudNativePG(streaming replica) / Temporal(MCR,active-passive) / ArgoCD / Prometheus+Grafana+Healthchecks.io

---

## 2. Changes to This Repository

### 2.1 New Files: NixOS k3s Node Configurations (6 nodes)

**`nixos/modules/hetzner-k3s-server.nix`** — Shared module. PowerDNS on host (systemd, boots before k3s). k3s with Cilium CNI. Split-IP firewall. MariaDB Galera node for PowerDNS backend.

**`nixos/modules/hetzner-k3s-agent.nix`** — Lighter module for agent nodes. No PowerDNS. No Galera. k3s agent joins the server's cluster.

**`nixos/k3s-ashburn-server.nix`**, **`nixos/k3s-ashburn-agent.nix`** — Ashburn-specific SSH keys, IPs, hostnames.

**`nixos/k3s-hillsboro-server.nix`**, **`nixos/k3s-hillsboro-agent.nix`**

**`nixos/k3s-nuremberg-server.nix`**, **`nixos/k3s-nuremberg-agent.nix`**

### 2.2 Updated Files

**`flake.nix`** — Add 6 NixOS configurations and the 2 new modules.

### 2.3 LA/HA Toggle Scripts

**`scripts/toggle-ha.sh`** — Provisions 3 agent nodes via Hetzner API. Deploys NixOS. Agents join k3s clusters. ArgoCD deploys workloads.

**`scripts/toggle-la.sh`** — Drains agent nodes gracefully. Destroys VMs via Hetzner API. Server nodes continue running.

---

## 3. New Repository: `2143-k8s-infra`

Multi-cluster infrastructure. Same structure as previously documented:
- `clusters/{ashburn,hillsboro,nuremberg}/` — per-cluster Helm values (k8gb, ExternalDNS, Traefik, CrowdSec, Istio)
- `base/` — shared manifests (Gslb CRDs, RFC2136 secret, middlewares, cert-manager)
- `argocd/` — root App-of-Apps with sync waves

---

## 4. Application Configuration (new, separate repo)

Deploy identically to all clusters via ArgoCD:
- `john2143-com`: stateless, S3 → SeaweedFS S3 gateway on localhost
- `mongo`: self-hosted, `--enableEncryption`, active-passive
- `openfront-pro`, poe-sale-redirectors: stateless, raw IP for poe
- `Temporal Server`: active on Ashburn, MCR replication
- `Temporal Workers`: all nodes
- `CloudNativePG`: primary on Ashburn, streaming replicas
- `derp-server`: UDP, raw IP via hostPort

**Storage**: SeaweedFS 10GB local per node on the 160GB SSD (3-way replication, ~10GB usable hot cache, LUKS2 + encryptVolumeData). Longhorn for PVCs. B2 + RustFS via rclone crypt daily CronJob.

---

## 5. Greenfield Deployment Phases

### Phase 0 — Provision (LA mode: 3 server nodes)
1. Create 3 VMs: Ashburn CPX31, Hillsboro CPX31, Nuremberg CPX32
2. Deploy NixOS via nixos-anywhere
3. Verify: PowerDNS, MariaDB Galera, k3s, Cilium

### Phase 1 — Bootstrap
1. Configure PowerDNS zone + NS + TSIG key
2. Deploy ArgoCD root App-of-Apps
3. Sync: cert-manager → Traefik → ExternalDNS → k8gb → Istio → CrowdSec → Longhorn

### Phase 2 — SeaweedFS + Storage
1. Deploy SeaweedFS on local SSD (10GB per node)
2. 3-way replication, encryptVolumeData, LUKS2
3. Create S3 buckets and access keys

### Phase 3 — Deploy Applications
1. MongoDB + CloudNativePG + Temporal (active-passive)
2. HTTP apps, DERP, TeamSpeak
3. k8gb Gslb CRDs with geoip strategy
4. Smoke test via direct IPs

### Phase 4 — Backups
1. B2 bucket + rclone crypt keys
2. Daily CronJob: B2 + RustFS
3. Healthchecks.io + B2 Object Lock

### Phase 5 — DNS Go-Live
1. Point domain at k8gb CoreDNS IPs
2. Optional: Bunny CDN pull zone
3. Monitor: errors, DNS, certs, backups

### Phase 6 — Toggle HA Mode
1. `./scripts/toggle-ha.sh` — provisions 3 agent nodes
2. Agents join clusters, ArgoCD deploys workloads
3. Demo HA: kill a server node, watch agent take over

---

## 6. Cost

| Mode | Nodes | Monthly |
|------|-------|---------|
| **LA** | 3 servers | ~$75 |
| **HA** | 6 nodes | ~$140 |
| **Demo** | 3 servers × 48 hours | ~$8-10 (Hetzner hourly billing) |

---

## 7. Open Decisions

| Decision | Resolved |
|----------|----------|
| Provider | **Hetzner only** |
| Node spec | **CPX31 (US) / CPX32 (EU) — 8GB symmetric** |
| Nodes per region | **2 (server + agent)** |
| Object storage | **SeaweedFS 10GB local SSD + B2 cold** |
| DNS | **PowerDNS + MariaDB Galera + RFC2136** |
| CDN | **Bunny CDN (GeoIP) optional overlay** |
| Time-based scaling | **Dropped (saves $0)** |
| Multi-provider | **Dropped (all Hetzner)** |
| New domain | **TBD** |

---

## 8. Timeline

| Phase | Effort | Notes |
|-------|--------|-------|
| Phase 0 — Provision | 0.5 day | nixos-anywhere |
| Phase 1 — Bootstrap | 1-2 days | ArgoCD sync waves |
| Phase 2 — SeaweedFS | 0.5 day | Local SSD, no volumes |
| Phase 3 — Apps | 1 day | ArgoCD sync |
| Phase 4 — Backups | 0.5 day | rclone + CronJob |
| Phase 5 — Go-live | 0.5 day | DNS + monitoring |
| Phase 6 — HA toggle | 0.5 day | Script + test |
| **Total** | **4-6 days** | Across 2-3 weeks |
