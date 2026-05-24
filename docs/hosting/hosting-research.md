# Hosting Research: DigitalOcean Migration to Self-Hosted Kubernetes

**Status**: Research complete (2026-05). Reference document for decisions made and alternatives rejected.

---

## 1. Research Question

What is the cheapest way to host Kubernetes with 99.99% reliability across at least 3 geographically distributed locations, replacing a DigitalOcean setup costing ~$43/month (1× DOKS 4GB/2vCPU/80GB + LB + 22GB PVCs + 250GB Spaces)?

---

## 2. Current DigitalOcean Setup

Projected monthly costs from 10-day bill ($14.33):

| Component | Monthly Cost |
|-----------|-------------|
| DOKS managed Kubernetes (1 node, 4GB/2vCPU/80GB) | $23.13 |
| Public Load Balancer | $11.58 |
| 4 PVCs (8GB + 10GB + 2GB + 2GB) | $2.10 |
| Spaces (250GB + 1TB bandwidth) | ~$6.18 |
| **Total** | **~$43.00** |

Workloads: john2143-com (image host, S3-backed), mongo (MongoDB 330Mi), openfront-pro, poe-sale-redirector, poe2-sale-redirector, derp-server (Tailscale DERP UDP), cert-manager, prometheus, grafana, argocd. Uses nginx-ingress (retired March 2026), Cilium CNI, ArgoCD GitOps.

---

## 3. Requirements

- 99.99% uptime (≤52.56 minutes downtime/year)
- At least 3 geographically distributed nodes
- Domain failover — domains reachable even if 1/3 datacenters fail
- Cheaper than ~$43/month
- Open to self-hosted and multi-cloud approaches
- User technically proficient (NixOS, Kubernetes, ArgoCD already in use)
- Minimize vendor lock-in; prefer open-source/nonprofit stack

---

## 4. Research Phases

### Phase 1: Global Cloud Provider Comparison (6 sub-topics)

**Key finding**: Architecture A — Hetzner-only self-hosted k3s + Backblaze B2 + Cloudflare Tunnel + Bunny DNS at **$15.55/month** (64% cheaper than DO).

Detailed reports at `ai_research/cheaper-kubernetes-hosting-99-99-reliability-3x-geo-distributed/`:
- `reports/budget-vps-managed-k8s-comparison_report.md`
- `reports/self-hosted-k3s-on-budget-vps_report.md`
- `reports/object-storage-alternatives_report.md`
- `reports/geo-distributed-k8s-architecture_report.md`
- `reports/dns-failover-global-lb_report.md`
- `reports/cost-projections-top-architectures_report.md`
- `phase_1_summary.md`
- `final_report.md`

**Providers evaluated**: Hetzner, Civo, Linode/Akamai, Vultr, Scaleway, OVHcloud, Contabo. Hetzner is the cheapest raw compute (CX22 at ~€3.79/mo EU, CPX21 at ~$13.99/mo US). Civo and Linode offer best managed K8s under $40 but exceed budget with 3 concurrent nodes.

**Architecture rules established**:
- 3 independent k3s clusters (not stretched) is the only viable geo-distributed pattern
- Etcd across WAN links is explicitly unsupported by k3s documentation
- Multi-cluster with DNS failover achieves 99.99% through geographic redundancy, not intra-cluster HA
- Cloudflare Tunnel replaces cloud LB ($11.58 → $0) but introduces vendor dependency

### Phase 2: US-Only Investigation (3 sub-topics)

**Key finding**: US-only hosting at 4GB/node across 3 locations is **more expensive than global** due to Hetzner having only 2 US locations, forcing a third provider at $15-20/month.

Detailed reports at `ai_research/cheapest-kubernetes-hosting-99-99-reliability-3x-us-locations/`:
- `reports/us-budget-vps-providers_report.md`
- `reports/cross-us-latency-architecture_report.md`
- `reports/cost-projections-us-only_report.md`

**Latency findings** (from AWS inter-region matrix, cloudping.co):
- US East ↔ US West: 72.84ms — exceeds etcd stability recommendation
- US East ↔ US Central: 28–29ms
- US Central ↔ US West: 41–42ms
- No triangle with true East/Central/West diversity where all links are <50ms

**Cross-US etcd viability**: With tuning (election timeout ≥1000ms, heartbeat 70-100ms), etcd can operate at 70ms RTT. Official docs state 5s is the safe upper limit. k3s docs prohibit embedded etcd in "distributed multicloud" (100-150ms), not same-continent 50-73ms. However, 3 independent clusters remain safer.

### Phase 3: Open-Source Stack Design (4 sub-topics)

**Key finding**: Full open-source stack on Hetzner is viable. US-only $44.48/mo, global (EU+US) $25.47/mo. deSEC TTL constraint discovered.

Detailed reports at `ai_research/using-an-open-source-nonprofit-stack-like-desec-k8gb-running-my-/`:
- `reports/k8gb-desec-externaldns-architecture_report.md`
- `reports/ddos-mitigation-open-source_report.md`
- `reports/full-stack-cost-projections_report.md`
- `reports/migration-plan-doks-to-hetzner_report.md`
- `phase_1_summary.md`
- `final_report.md`


### Phase 4: Geo-Distributed Encrypted Object Storage (3 sub-topics)

**Key finding**: SeaweedFS selected over Garage for per-file AES-256-GCM encryption and richer S3 API. MinIO eliminated (archived Feb 2026). Requires 3× 100GB Hetzner Cloud Volumes (~€15/mo total) for 3-way replication of 250GB. Encryption: LUKS2 + SeaweedFS encryptVolumeData + rclone crypt per backup target. Backups: B2 ($1.44/mo) + home RustFS. Monitoring: Healthchecks.io.

Detailed reports at `ai_research/geo-distributed-encrypted-object-storage/`:
- `reports/garage-seaweedfs-minio-comparison_report.md`
- `reports/encryption-distributed-object-storage_report.md`
- `reports/multi-target-backup-b2-rustfs_report.md`
- `phase_1_summary.md`
- `final_report.md`
---

## 5. Technology Decisions

### 5.1 Chosen

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Compute | Hetzner CPX21 (US) + CX22 (EU) | Cheapest 4GB VPS; Ashburn + Hillsboro + Nuremberg |
| OS | NixOS | Already in use; declarative; k3s module available |
| K8s distribution | k3s (3 independent clusters) | Lightweight (~1.4GB idle); SQLite per cluster; no etcd WAN issues |
| CNI | Cilium (already in use) | eBPF-based; Cluster Mesh for cross-cluster; already deployed |
| Ingress | Traefik (replaces nginx-ingress) | Open-source; nginx-ingress retired March 2026; native Ingress compatibility |
| GitOps | ArgoCD (already in use) | App-of-Apps pattern; sync waves; already deployed |
| DNS hosting | PowerDNS on host (NixOS systemd) | Zero external dependency; RFC2136 API; configurable TTL; boots before k3s |
| DNS failover | k8gb (CNCF) | Open-source GSLB; mutual CoreDNS queries across clusters; geoip strategy |
| DNS sync | ExternalDNS + RFC2136 provider | Updates PowerDNS via TSIG-authenticated DNS UPDATE |
| Object storage | SeaweedFS (hot, geo-distributed) | 3× 100GB Hetzner Cloud Volumes (~€15/mo); per-file AES-256-GCM encryption; 3-way replication; local reads in all regions |
| Object backups | Backblaze B2 (cold) + home RustFS (warm) | rclone crypt with separate keys per target; ~$1.44/mo; Healthchecks.io monitoring |
| Database | Self-hosted MongoDB (encryption at rest) | Already runs on DOKS; `--enableEncryption` flag; Longhorn PV; encrypted hourly backups to B2; zero cost |
| Storage (PVCs) | Longhorn (open-source) | Snapshots, S3 backup to B2, UI; ~200-300MB RAM overhead; $0; already familiar from home cluster |
| DDoS mitigation | CrowdSec + Traefik middleware + iptables + Hetzner native | 5-layer defense; $0 software; ~€1.50/mo for extra IPs |
| Certificates | cert-manager + Let's Encrypt | Already deployed; open-source; automatic renewal |

### 5.2 Rejected

| Component | Rejected | Reason |
|-----------|----------|--------|
| Stretched K8s cluster | ✗ | Etcd requires <10ms latency; impossible across regions |
| Managed K8s (Civo, Linode LKE) | ✗ | 3 concurrent nodes exceed $43 budget ($65-85/mo) |
| OVHcloud | ✗ | Managed K8s control plane €65.70/mo; free tier SLA only 99.5% |
| AWS S3 | ✗ | Egress costs ($13-87/mo) make it non-viable |
| Wasabi | ✗ | 1TB minimum ($6.99/mo) — paying for 750GB unused |
| Anycast | ✗ | Requires ASN + BGP + IP space; $50-200+/mo; enterprise-only |
| Cloudflare Load Balancer | ✗ | $5/mo + requires $20/mo Pro plan |
| Bunny DNS | ✗ | Works well ($0-1/mo) but is a vendor dependency |
| deSEC alone | ✗ | 3600s default TTL blocks sub-hour failover |
| KubeFed | ✗ | Not actively developed; alpha/beta resources |
| nginx-ingress | ✗ | Retired March 2026; must migrate to Traefik |
| Cloudflare Tunnel (as sole ingress) | ✗ | CF outages (2-3hr) exceed annual 99.99% downtime budget |
| Talos Linux | ✗ | NixOS already in use; operational familiarity wins |
| MongoDB Atlas M0 | ✗ | Vendor dependency; want to own all data; self-hosted with encryption-at-rest is zero cost anyway |

### 5.3 Conditional / Fallback

| Component | Status | Condition |
|-----------|--------|-----------|
| Cloudflare Tunnel | Fallback | Can be added as optional DDoS overlay on top of direct IPs |
| deSEC DNS | Fallback | If PowerDNS proves too operationally heavy, deSEC with TTL exception |
| Cloudflare free DNS | Fallback | If both PowerDNS and deSEC fail, CF free tier (60s TTL, in-tree ExternalDNS provider) |
| Home node | Optional | Can replace one paid node (~$14/mo savings) |
| Bunny CDN | Optional | Anycast CDN overlay (~$1-2/mo): 120+ PoPs, sub-second failover, edge caching, DDoS absorption. Flip DNS away to revert to k8gb-only. |

---

## 6. Cost Summary

### Chosen architecture: 2× US + 1× EU

| Component | Provider | Specification | Monthly |
|-----------|----------|---------------|---------|
| Node 1 (US East) | Hetzner Ashburn CPX21 | 3 vCPU / 4GB / 80GB SSD | $13.99 |
| Node 2 (US West) | Hetzner Hillsboro CPX21 | 3 vCPU / 4GB / 80GB SSD | $13.99 |
| Node 3 (EU) | Hetzner Nuremberg CX22 | 2 vCPU / 4GB / 40GB SSD | ~$4.99 |
| Hot storage (SeaweedFS) | Hetzner Cloud Volumes | 3× 100GB for 3-way replication | ~€15.00 |
| Cold backup (B2) | Backblaze B2 | 250GB encrypted, rclone crypt | ~$1.44 |
| Warm backup | Home RustFS | S3-compatible, encrypted, rclone crypt | $0 |
| Database | Self-hosted MongoDB | Encryption at rest, Longhorn PV | $0 |
| DNS | PowerDNS (self-hosted) | On existing nodes | $0 |
| DDoS extra IPs | Hetzner | 3× extra IPv4 (~€0.50/IP/mo) | ~$1.58 |
| All software | k8gb, ExternalDNS, Traefik, Cilium, CrowdSec, cert-manager, Prometheus, Grafana, ArgoCD, Longhorn, SeaweedFS | Open-source | $0 |
| Optional: Bunny CDN | Bunny.net pull zone | Anycast CDN, 120+ PoPs | ~$1-2 |
| **Total (without Bunny)** | | | **~$50.99** |
| **Total (with Bunny)** | | | **~$52.99** |

**Note**: Total exceeds the original $43 target due to SeaweedFS volume costs (~€15/mo) — a necessary addition for 3-way geo-distributed replication of 250GB. The original target was set before distributed encrypted object storage was in scope. The architecture provides dramatically higher reliability (3 nodes vs 1, anycast CDN option, dual encrypted backups) for ~$8-10/mo more than the current DO setup.

### Rejected architectures (for reference)

| Architecture | Monthly | vs. DO | Why rejected |
|-------------|---------|--------|-------------|
| Global Hetzner k3s (3× CX22 EU) | $15.55 | −64% | No US nodes; poor latency for 75% US users |
| US-only (2× Hetzner + BuyVM) | $44.48 | +$1.48 | Over budget; single-core BuyVM node |
| US-only (2× Hetzner + Linode) | $49.48 | +$6.48 | Over budget |
| Civo + Linode managed K8s | $45.43 | +$2.43 | Over budget; vendor lock-in |

---

## 7. Architecture Diagrams

### 7.1 Physical Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Traffic                              │
│         US East (30%)    US West (20%)    EU (25%)   Other (25%)│
└────────────┬───────────────────┬───────────────┬────────────────┘
             │                   │               │
             ▼                   ▼               ▼
┌────────────────────┐ ┌────────────────┐ ┌────────────────────┐
│  Ashburn, VA       │ │ Hillsboro, OR  │ │ Nuremberg, DE      │
│  Hetzner CPX21     │ │ Hetzner CPX21  │ │ Hetzner CX22       │
│  3 vCPU / 4GB      │ │ 3 vCPU / 4GB   │ │ 2 vCPU / 4GB       │
│  80GB SSD          │ │ 80GB SSD       │ │ 40GB SSD           │
│  $13.99/mo         │ │ $13.99/mo      │ │ ~$4.99/mo          │
│                    │ │                │ │                    │
│  PowerDNS (host)   │ │                │ │  PowerDNS (host)   │
│  k3s cluster       │ │ k3s cluster    │ │  k3s cluster       │
│  k8gb + CoreDNS    │ │ k8gb + CoreDNS │ │  k8gb + CoreDNS    │
│  Traefik           │ │ Traefik        │ │  Traefik           │
│  CrowdSec          │ │ CrowdSec       │ │  CrowdSec          │
│  MongoDB+Longhorn  │ │ MongoDB (stby) │ │  MongoDB (stby)   │
│  Apps              │ │ Apps           │ │  Apps              │
│  Protected IP      │ │ Protected IP   │ │  Protected IP      │
│  Raw IP (game/TS)  │ │ Raw IP         │ │  Raw IP            │
└────────┬───────────┘ └───────┬────────┘ └──────────┬─────────┘
         │                     │                      │
         └─────────────────────┼──────────────────────┘
                               │
              ┌────────────────▼────────────────┐
              │     Shared Infrastructure        │
              │  Backblaze B2 ($1.50/mo)        │
              │  ArgoCD (GitOps, both repos)    │
              └─────────────────────────────────┘
```

### 7.2 DNS Resolution Flow

```
User: john2143.com
      │
      ▼
Registrar: NS → ns1.john2143.com (Ashburn PowerDNS)
                ns2.john2143.com (Nuremberg PowerDNS)
      │
      ▼
PowerDNS (Ashburn or Nuremberg):
  john2143.com A → delegated to k8gb CoreDNS
      │
      ▼
k8gb geoip: user's resolver IP → closest healthy cluster
  US East resolver → Ashburn IP
  US West resolver → Hillsboro IP
  EU resolver → Nuremberg IP
      │
      ▼
Traefik (direct public IP) → CrowdSec bouncer → App pod
```
```

### 7.2.1 With Optional Bunny CDN (Anycast Overlay)

```
User → Bunny CDN (120+ anycast PoPs, sub-10ms globally)
         Cache hit → serve from edge
         Cache miss → pull from k8gb origin (closest healthy node)

If Bunny CDN goes down: flip DNS A record to k8gb CoreDNS IPs.
Reverts to k8gb-only failover. No lock-in — one DNS change.
```

### 7.3 Failover Flow (Ashburn fails)

```
T+0s     Ashburn node down. k8gb CoreDNS stops responding.
T+5-10s  Hillsboro + Nuremberg k8gb operators detect Ashburn's
         CoreDNS is unreachable (DNS queries timeout).
T+10-30s DNSEndpoint CRDs updated — Ashburn IPs removed.
         CoreDNS stops returning Ashburn A records.
T+30s    ExternalDNS reconciliation updates PowerDNS via RFC2136.
T+0-60s  User DNS caches expire (60s TTL).
         Users re-resolve → get Hillsboro or Nuremberg IP.
         US East users route to Hillsboro (~70ms) or Nuremberg (~95ms).
         Total real-world failover: 30-90 seconds.
```

### 7.4 Split-IP DDoS Architecture

```
┌─────────────────────────────────────────────┐
│              Hetzner CPX21                   │
│                                             │
│  ┌───────────────────┐  ┌────────────────┐  │
│  │ Protected IP       │  │ Raw IP          │  │
│  │ 5.9.x.x            │  │ 5.9.y.y         │  │
│  │                   │  │                 │  │
│  │ iptables:         │  │ iptables:       │  │
│  │  allow :80,:443   │  │  allow game     │  │
│  │  rate-limit SYN   │  │  ports UDP/TCP  │  │
│  │  drop all else    │  │  allow DERP     │  │
│  │         │          │  │  allow TS       │  │
│  │         ▼          │  │  drop all else  │  │
│  │  Traefik           │  │         │        │  │
│  │   RateLimit        │  │         ▼        │  │
│  │   InFlightConn     │  │  Game servers    │  │
│  │   CrowdSec plugin  │  │  TeamSpeak       │  │
│  │         │          │  │  derp-server     │  │
│  │         ▼          │  │  poe.sale        │  │
│  │  john2143-com      │  │                 │  │
│  │  openfront-pro     │  │                 │  │
│  └───────────────────┘  └────────────────┘  │
│                                             │
│  Hetzner native DDoS (automatic, all IPs)    │
│  Hetzner Cloud Firewall (per-node rules)    │
└─────────────────────────────────────────────┘
```

### 7.5 End-to-End Architecture (with Bunny CDN)

```
                        ┌──────────────────────────────────────┐
                        │           Users worldwide             │
                        └──────────────────┬───────────────────┘
                                           │
                        ┌──────────────────▼───────────────────┐
                        │   Bunny CDN ($1-2/mo, optional)      │
                        │   120+ anycast PoPs, sub-10ms edge   │
                        └──────────────────┬───────────────────┘
                                           │
             ┌─────────────────────────────┼─────────────────────────────┐
             │                             │                             │
   ┌─────────▼──────────┐       ┌─────────▼──────────┐       ┌─────────▼──────────┐
   │   Ashburn, VA      │       │  Hillsboro, OR     │       │  Nuremberg, DE     │
   │   Hetzner CPX21    │       │  Hetzner CPX21     │       │  Hetzner CX22      │
   │                    │       │                    │       │                    │
   │ PowerDNS (host)    │       │ k8gb + CoreDNS     │       │ PowerDNS (host)    │
   │ k8gb + CoreDNS     │       │ Traefik + CrowdSec │       │ k8gb + CoreDNS     │
   │ Traefik + CrowdSec │       │ MongoDB (stby)     │       │ Traefik + CrowdSec │
   │ MongoDB+Longhorn   │       │ SeaweedFS Volume   │       │ MongoDB (stby)     │
   │ SeaweedFS Volume   │       │ Your apps          │       │ SeaweedFS Volume   │
   │ Your apps          │       │                    │       │ Your apps          │
   │                    │       │                    │       │                    │
   │ Protected IP :443  │       │ Protected IP :443  │       │ Protected IP :443  │
   │ Raw IP (game/TS)   │       │ Raw IP             │       │ Raw IP             │
   └────────┬───────────┘       └────────┬───────────┘       └────────┬──────────┘
            │                            │                            │
            └────────────────────────────┼────────────────────────────┘
                                         │
            ┌────────────────────────────┼────────────────────────────┐
            │                            │                            │
   ┌────────▼──────────┐      ┌─────────▼──────────┐      ┌─────────▼──────────┐
   │ SeaweedFS Volume  │      │ SeaweedFS Volume   │      │ SeaweedFS Volume   │
   │ 100GB, LUKS2      │      │ 100GB, LUKS2       │      │ 100GB, LUKS2      │
   │ encryptVolumeData │      │ encryptVolumeData  │      │ encryptVolumeData │
   │ per-file AES-GCM  │      │ per-file AES-GCM   │      │ per-file AES-GCM  │
   └───────────────────┘      └────────────────────┘      └───────────────────┘
            │                            │                            │
            └────────────────────────────┼────────────────────────────┘
                                         │
                  ┌──────────────────────▼──────────────────────┐
                  │          Backups (async, daily CronJob)      │
                  │                                              │
                  │  rclone crypt ──► Backblaze B2 ($1.44/mo)   │
                  │  rclone crypt ──► Home RustFS (warm)         │
                  │  Healthchecks.io monitoring                  │
                  └─────────────────────────────────────────────┘
```

---

## 8. Source References

Complete bibliographies in individual research reports. Key primary sources:

- Hetzner pricing: `https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/`
- k3s docs: `https://docs.k3s.io/networking/distributed-multicloud`
- k8gb docs: `https://www.k8gb.io/intro/`
- etcd tuning: `https://etcd.io/docs/v3.2/tuning/`
- AWS inter-region latency: `https://www.cloudping.co/`
- CrowdSec: `https://github.com/crowdsecurity/crowdsec`
- PowerDNS: `https://doc.powerdns.com/`
- Backblaze B2: `https://www.backblaze.com/cloud-storage/pricing`
- MongoDB Atlas: `https://www.mongodb.com/pricing`
- Hetzner DDoS: `https://www.hetzner.com/pressroom/nokia-network-security/`

---

## 9. Final Architecture: 5-Nines Platform (~$92/mo)

**Target**: 99.999% uptime (≤5.26 minutes downtime/year)

### Node Layout (9 nodes total)

| Location | Node | Role | Plan | Monthly |
|----------|------|------|------|---------|
| **Ashburn, VA** | k3s server | PowerDNS, k8gb, MongoDB (active), CloudNativePG (primary), Temporal Server, SeaweedFS volume | CPX21 4GB | $13.99 |
| | k3s agent | Temporal Workers, HTTP apps, Istio sidecars, MongoDB backup | CPX11 2GB | ~$6.99 |
| **Hillsboro, OR** | k3s server | k8gb, Traefik, CrowdSec, MongoDB (standby), CloudNativePG (replica), SeaweedFS volume | CPX21 4GB | $13.99 |
| | k3s agent | Temporal Workers, HTTP apps, Istio sidecars | CPX11 2GB | ~$6.99 |
| **Nuremberg, DE** | k3s server | PowerDNS, k8gb, MongoDB (standby), CloudNativePG (replica), SeaweedFS volume | CPX21 4GB | ~$9.90 |
| | k3s agent | Temporal Workers, HTTP apps, Istio sidecars | CPX11 2GB | ~$4.95 |
| **Home (Raspberry Pi)** | Standalone | PowerDNS #3 (multi-provider tiebreaker), k8gb split-brain witness, Uptime Kuma monitoring, RustFS backup target | Pi 4/5 | $0 + power |

### New Components

| Component | Why |
|-----------|-----|
| **CloudNativePG** | Per-region streaming replication, automated failover (<60s), WAL archiving to B2 |
| **Temporal.io** | Durable execution engine; active on Ashburn, 18 workers across all 6 nodes |
| **Istio** | Service mesh: mTLS, retries, circuit breaking, distributed tracing |
| **2 nodes per region** | Single node failure → pods reschedule to sibling. DB has dedicated replica. |
| **Home Pi (PowerDNS #3)** | 3rd authoritative DNS on non-Hetzner hardware — breaks single-provider dependency |
| **Bunny CDN (default)** | Anycast edge, sub-second failover. If down, flip DNS to k8gb direct. |

### Cost Breakdown

| Component | Monthly |
|-----------|---------|
| 3× CPX21 servers | $37.88 |
| 3× CPX11/CX22 agents | $18.93 |
| SeaweedFS Volumes (3× 100GB) | ~$16.50 |
| Backblaze B2 (cold backup) | $1.44 |
| Bunny CDN (pull zone) | ~$2.00 |
| DDoS extra IPs | $1.58 |
| Home Pi (power) | ~$5.00 |
| All software — open-source | $0 |
| **Total** | **~$92/mo** |

### 5-Nines Downtime Budget

| Failure | Recovery | Events/yr | Budget used |
|---------|----------|-----------|-------------|
| Single node crash (pods reschedule) | 10-30s | 3× | 30-90s |
| Region down (Bunny CDN anycast) | Sub-second | 0.5× | <1s |
| CloudNativePG auto-promote | 30-60s | 0.5× | 15-30s |
| PowerDNS failure (requires 2/3 down) | 60s TTL | 0.1× | 6s |
| Bunny CDN outage → k8gb fallback | 60s flip | 0.5× | 30s |
| **Total consumed** | | | **~2-3 min/yr** |
| **99.999% budget** | | | **5.26 min/yr** ✅ |

**Critical risk**: All 6 VPS nodes are on Hetzner. A Hetzner outage takes down everything except the Home Pi DNS and B2. True 5-nines requires 1 multi-provider node (~$15/mo) for compute redundancy during a provider outage.

---

## 10. Final Enterprise Architecture (6-Node Symmetric HA, All-Hetzner)

**Target**: Self-healing per region. HA demo platform. 3 independent k3s clusters.

### Node Layout

| Region | Node | Plan | Monthly |
|--------|------|------|---------|
| **Ashburn, VA** | k3s server | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 |
| | k3s agent (hot standby) | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 |
| **Hillsboro, OR** | k3s server | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 |
| | k3s agent (hot standby) | CPX31 (8GB / 4 vCPU / 160GB) | $24.99 |
| **Nuremberg, DE** | k3s server | CPX32 (8GB / 4 vCPU / 160GB) | ~$15.20 |
| | k3s agent (hot standby) | CPX32 (8GB / 4 vCPU / 160GB) | ~$15.20 |
| **Home** | Raspberry Pi | Headscale (VPN), PowerDNS #3, Uptime Kuma, RustFS | $0 + power |

All 6 nodes symmetrically sized. Any node can run the full workload for its region. SeaweedFS uses local SSD (10GB per node, 3-way replication, ~10GB usable hot cache). B2 serves the full corpus. Popular images cached locally.

### Full Stack

| Layer | Component |
|-------|-----------|
| OS | NixOS on all nodes |
| K8s | k3s (3 independent clusters, SQLite per cluster) |
| CNI | Cilium (eBPF) |
| Service mesh | Istio (mTLS, retries, circuit breaking) |
| Ingress | Traefik + CrowdSec + split-IP DDoS |
| DNS hosting | PowerDNS + MariaDB Galera (3 locations) |
| DNS failover | k8gb (geoip) + ExternalDNS RFC2136 |
| CDN overlay | Bunny CDN (GeoIP pull zone) |
| Object storage | SeaweedFS (3-way replication on local SSD, 10GB hot cache, LUKS2 + encryptVolumeData) |
| Cold backup | Backblaze B2 (rclone crypt) |
| Warm backup | Home RustFS (rclone crypt) |
| PVC storage | Longhorn |
| MongoDB | Self-hosted, `--enableEncryption`, active-passive |
| PostgreSQL | CloudNativePG (streaming replica per region) |
| Temporal | Active-passive, MCR replication |
| GitOps | ArgoCD (App-of-Apps) |
| Monitoring | Prometheus + Grafana + Healthchecks.io |

### Cost

| Component | Monthly |
|-----------|---------|
| 6× 8GB nodes (Hetzner only) | ~$130.36 |
| Backblaze B2 | $1.44 |
| Bunny CDN | ~$2.00 |
| DDoS extra IPs | $1.58 |
| Home Pi | ~$5.00 |
| All software | $0 |
| **Total** | **~$140/mo** |

### LA/HA Mode Toggle

| Mode | Nodes | Cost | Use |
|------|-------|------|-----|
| **LA (Low Availability)** | 3 servers (1 per region) | ~$75/mo | Development, off-peak, cost saving |
| **HA (High Availability)** | 6 nodes (2 per region) | ~$140/mo | Production, peak hours, demonstrations |

Server nodes run 24/7 (host SeaweedFS volumes and DNS). Agent nodes are the HA toggle — provision/destroy via script. Agents join/leave k3s clusters. No data migration — all stateful workloads stay on server nodes.