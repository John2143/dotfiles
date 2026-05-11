# Hosting Next Steps: Migration to Self-Hosted k3s on Hetzner

**Status**: Plan (pre-implementation). To be refined via plan mode.

---

## 1. Target Architecture

3 independent k3s clusters running NixOS on Hetzner:
- **Ashburn, VA** (US East) — CPX21, 3 vCPU / 4GB / 80GB
- **Hillsboro, OR** (US West) — CPX21, 3 vCPU / 4GB / 80GB
- **Nuremberg, DE** (EU) — CX22, 2 vCPU / 4GB / 40GB

DNS via PowerDNS on host (NixOS systemd), k8gb geoip failover, Bunny CDN (optional anycast overlay), Traefik ingress with CrowdSec, SeaweedFS hot storage (3× 100GB volumes, per-file encrypted), Backblaze B2 cold storage, home RustFS warm backup, self-hosted MongoDB (encryption at rest, Longhorn PV). Full details in [`hosting-research.md`](hosting-research.md).

---

## 2. Changes to This Repository

### 2.1 New Files: NixOS k3s Node Configurations

**`nixos/modules/hetzner-k3s-server.nix`** — Shared module for all 3 nodes:

```nix
{ config, lib, pkgs, ... }:

{
  # PowerDNS — authoritative DNS, runs on host before k3s
  services.powerdns = {
    enable = true;
    extraConfig = ''
      launch=gsqlite3
      gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
      local-address=0.0.0.0
      local-port=53
      allow-axfr-ips=127.0.0.1
      api=yes
      api-key=@POWERDNS_API_KEY@
      default-ttl=60
      allow-dnsupdate-from=127.0.0.1
      dnsupdate=yes
    '';
  };

  # k3s — single-node cluster, SQLite backend
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--flannel-backend=none"       # Cilium replaces flannel
      "--disable-network-policy"     # Cilium handles network policy
      "--disable=traefik"            # We deploy Traefik ourselves
      "--disable=servicelb"          # Use Cilium or direct NodePort
      "--cluster-cidr=10.42.0.0/16"
      "--service-cidr=10.43.0.0/16"
      "--node-external-ip=@NODE_PUBLIC_IP@"
    ];
  };

  # k3s depends on PowerDNS being ready
  systemd.services.k3s = {
    after = [ "powerdns.service" ];
    wants = [ "powerdns.service" ];
  };

  # Cilium kernel requirements
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
  boot.kernelModules = [ "xt_socket" ];

  # DDoS kernel hardening
  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
    "net.ipv4.tcp_max_syn_backlog" = 4096;
    "net.core.somaxconn" = 4096;
  };

  # Firewall — per-IP rules for split-IP architecture
  networking.firewall.extraCommands = ''
    # Protected IP: allow only HTTP/HTTPS, rate-limit SYN
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --set
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --update --seconds 1 --hitcount 50 -j DROP
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -j ACCEPT
    iptables -A INPUT -d @PROTECTED_IP@ -j DROP

    # Raw IP: allow game/DERP/TS ports (customize per node)
    iptables -A INPUT -d @RAW_IP@ -p udp --dport 3478 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -p udp --dport 9987 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -p tcp -m multiport --dports 80,443,30033 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -j DROP
  '';

  networking.firewall.allowedTCPPorts = [ 6443 80 443 ];
  networking.firewall.allowedUDPPorts = [ 53 8472 ];

  environment.systemPackages = with pkgs; [
    k3s
    cilium-cli
    pdnsutil
  ];
}
```

**`nixos/k3s-ashburn.nix`**:
```nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ ./modules/hetzner-k3s-server.nix ];
  networking.hostName = "k3s-ashburn";
  # Hetzner Ashburn-specific: SSH keys, network, IPs
}
```

**`nixos/k3s-hillsboro.nix`**:
```nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ ./modules/hetzner-k3s-server.nix ];
  networking.hostName = "k3s-hillsboro";
}
```

**`nixos/k3s-nuremberg.nix`**:
```nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ ./modules/hetzner-k3s-server.nix ];
  networking.hostName = "k3s-nuremberg";
}
```

### 2.2 Updated Files

**`flake.nix`** — Add 3 new NixOS configurations:
```nix
nixosConfigurations.k3s-ashburn = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [ ./nixos/k3s-ashburn.nix ];
};
nixosConfigurations.k3s-hillsboro = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [ ./nixos/k3s-hillsboro.nix ];
};
nixosConfigurations.k3s-nuremberg = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [ ./nixos/k3s-nuremberg.nix ];
};
```

### 2.3 Existing Configs to Retire (post-migration)

These can be archived after DOKS is decommissioned:
- `nixos/home-cli.nix` — any DOKS-specific kubeconfig references
- DOKS-specific nixos configs if they exist

---

## 3. New Repository: `2143-k8s-infra`

### 3.1 Purpose

Multi-cluster infrastructure that spans all 3 k3s clusters — k8gb, ExternalDNS, Traefik, Cilium, CrowdSec, cert-manager. Separate from the app repo because these are infrastructure components with per-cluster configuration variance.

### 3.2 Repository Structure

```
2143-k8s-infra/
├── README.md
├── clusters/
│   ├── ashburn/
│   │   ├── k8gb-values.yaml
│   │   ├── externaldns-values.yaml
│   │   ├── traefik-values.yaml
│   │   └── crowdsec-values.yaml
│   ├── hillsboro/
│   │   ├── k8gb-values.yaml
│   │   ├── externaldns-values.yaml
│   │   ├── traefik-values.yaml
│   │   └── crowdsec-values.yaml
│   └── nuremberg/
│       ├── k8gb-values.yaml
│       ├── externaldns-values.yaml
│       ├── traefik-values.yaml
│       └── crowdsec-values.yaml
├── base/
│   ├── k8gb/
│   │   └── gslb-resources.yaml        # Gslb CRDs for all apps
│   ├── externaldns/
│   │   └── rfc2136-secret.yaml        # TSIG key for PowerDNS
│   ├── traefik/
│   │   └── middlewares.yaml           # RateLimit, CrowdSec, InFlightConn
│   ├── crowdsec/
│   │   ├── lapi-deployment.yaml
│   │   ├── agent-daemonset.yaml
│   │   └── firewall-bouncer.yaml
│   ├── cert-manager/
│   │   ├── cluster-issuer.yaml        # Let's Encrypt staging + prod
│   │   └── certificates.yaml
│   └── cilium/
│       └── cilium-values.yaml         # Shared Cilium config
└── argocd/
    └── root-app.yaml                  # App-of-Apps, sync waves
```

### 3.3 Key Configuration Files

**`clusters/ashburn/k8gb-values.yaml`**:
```yaml
k8gb:
  clusterGeoTag: "us-ashburn"
  extGslbClustersGeoTags: "us-hillsboro,eu-nuremberg"
  reconcileRequeueSeconds: 10
  dnsZones:
    - parentZone: "john2143.com"
      loadBalancedZone: "lb.john2143.com"
  edgeDNSServers:
    - "1.1.1.1"

coredns:
  isClusterService: false
  serviceType: "LoadBalancer"

extdns:
  enabled: true
  interval: 20s
  domainFilters:
    - "john2143.com"
  txtPrefix: "k8gb-ash-"
  txtOwnerId: "k8gb-ash"
```

**`clusters/hillsboro/k8gb-values.yaml`**:
```yaml
k8gb:
  clusterGeoTag: "us-hillsboro"
  extGslbClustersGeoTags: "us-ashburn,eu-nuremberg"
  # ... same dnsZones, coredns, extdns structure
```

**`clusters/nuremberg/k8gb-values.yaml`**:
```yaml
k8gb:
  clusterGeoTag: "eu-nuremberg"
  extGslbClustersGeoTags: "us-ashburn,us-hillsboro"
  # ... same dnsZones, coredns, extdns structure
```

**`base/externaldns/rfc2136-secret.yaml`**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rfc2136-credentials
  namespace: external-dns
data:
  rfc2136Host: <base64 ns1.john2143.com>
  rfc2136Port: "53"
  rfc2136Zone: <base64 john2143.com>
  rfc2136TsigKeyname: <base64 externaldns>
  rfc2136TsigSecretAlg: <base64 hmac-sha256>
  rfc2136TsigSecret: <base64 generated-key>
```

**`base/k8gb/gslb-resources.yaml`**:
```yaml
---
apiVersion: k8gb.absa.oss/v1beta1
kind: Gslb
metadata:
  name: john2143-com
spec:
  strategy:
    type: geoip
    dnsTtlSeconds: 60
  ingress:
    rules:
      - host: john2143.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: john2143-com
                  port:
                    number: 80
---
apiVersion: k8gb.absa.oss/v1beta1
kind: Gslb
metadata:
  name: openfront-pro
spec:
  strategy:
    type: geoip
    dnsTtlSeconds: 60
  ingress:
    rules:
      - host: openfront.john2143.com
        ...
---
# poe.sale — raw IP, NO Gslb (direct DNS A record to raw IPs)
# derp-server — raw IP, NO Gslb
# TeamSpeak — raw IP, NO Gslb
```

**`base/traefik/middlewares.yaml`**:
```yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: john2143-ratelimit
spec:
  rateLimit:
    average: 100
    period: 1s
    burst: 200
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: crowdsec-protected
spec:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      crowdsecMode: stream
      crowdsecLapiHost: "crowdsec-service.crowdsec.svc.cluster.local:8080"
      crowdsecAppsecEnabled: true
```

**`argocd/root-app.yaml`**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/2143-k8s-infra
    path: argocd
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
# Child apps reference paths in this repo:
#   base/cilium, base/cert-manager, base/traefik, base/k8gb,
#   base/externaldns, base/crowdsec
# Plus apps from 2143-k8s repo:
#   base/ (john2143-com, mongo, openfront, poe-sale, derp-server,
#          prometheus, grafana)
```

### 3.4 Traefik per-cluster values

```yaml
# clusters/ashburn/traefik-values.yaml
providers:
  kubernetesIngress:
    enabled: true
  kubernetesCRD:
    enabled: true
    allowCrossNamespace: true
experimental:
  plugins:
    crowdsec-bouncer-traefik-plugin:
      moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version: "v1.4.5"
ports:
  web:
    hostPort: 80
  websecure:
    hostPort: 443
service:
  type: ClusterIP
# Bind to protected IP only
hostNetwork: true
```

---

## 4. Application Configuration (new, in `2143-k8s-infra` or new app repo)
### 4.1 Ingress (Traefik replaces nginx-ingress)

- Deploy Traefik via Helm on all 3 clusters (per-cluster values in 2143-k8s-infra)
- Traefik v3.5+ nginx provider handles existing Ingress resources
- No migration needed — greenfield, deploy fresh

### 4.2 App Deployments

Deploy identically to all 3 clusters via ArgoCD:
- `john2143-com`: stateless, S3-backed (→ SeaweedFS S3 gateway)
- `mongo`: self-hosted with `--enableEncryption`, active on Ashburn, standby on others
- `openfront-pro`, `openfront-pro-simulation-api`: stateless
- `poe-sale-redirector`, `poe2-sale-redirector`: stateless, deploy to raw IP
- `derp-server`: UDP, deploy to raw IP via hostPort
- `prometheus`, `grafana`: monitoring

### 4.3 S3 Configuration

```yaml
# Point imagehost at SeaweedFS (hot, local, encrypted)
S3_ENDPOINT_URL: http://seaweedfs-s3.<cluster>.svc.cluster.local:8333
S3_ACCESS_KEY: <seaweedfs-access-key>
S3_SECRET_KEY: <seaweedfs-secret-key>
BUCKET: imagehost-files
```

Remove old `MINIO_*` env vars — SeaweedFS uses standard S3.

### 4.4 MongoDB

Greenfield — deploy fresh with `--enableEncryption` + encryption key in Secret:
- Active on Ashburn (Longhorn PV)
- Standby on Hillsboro and Nuremberg (scaled to 0, PVCs pre-provisioned)
- Hourly CronJob: `mongodump` → B2 (encrypted)

### 4.5 Monitoring

- Prometheus: k8gb metrics, CrowdSec metrics, PowerDNS metrics, SeaweedFS metrics
- Grafana: k8gb dashboard, CrowdSec dashboard, SeaweedFS dashboard
- Alert rules: node bandwidth >80%, CrowdSec ban spikes, k8gb endpoint count drops, backup failure

## 5. Greenfield Deployment Phases

**This is a greenfield deployment on a new domain.** No migration from DOKS. Build fresh, test fully, copy data later.

### Phase 0 — Provision Hetzner Nodes

1. Create 3 VMs in Hetzner Cloud (Ashburn CPX21, Hillsboro CPX21, Nuremberg CX22)
2. Create 3× 100GB Cloud Volumes (attach to each node for SeaweedFS)
3. Request additional IPv4 per node (for split-IP architecture)
4. Deploy NixOS via nixos-anywhere
5. Verify: PowerDNS starts, k3s running, Cilium healthy

### Phase 1 — Bootstrap Cluster Services

1. Configure PowerDNS: add new domain zone, set NS records with registrar, configure TSIG key
2. Install ArgoCD on each cluster
3. Deploy root App-of-Apps: cert-manager → Traefik → ExternalDNS → k8gb → CrowdSec → Longhorn
4. Verify: all 3 clusters synced, TLS certs issued, k8gb CoreDNS responding

### Phase 2 — Deploy SeaweedFS

1. Deploy SeaweedFS via Helm on all 3 clusters
2. Configure 3-way replication across zones (ashburn, hillsboro, nuremberg)
3. Enable `-encryptVolumeData` on filer
4. Create LUKS2-encrypted partitions on the 100GB Cloud Volumes
5. Create S3 buckets, access keys
6. Verify: upload test file, read from all 3 regions, confirm encryption at rest

### Phase 3 — Deploy Applications

1. Deploy MongoDB (active on Ashburn, standby on others) with `--enableEncryption`
2. Deploy john2143-com, openfront-pro, poe-sale-redirector, derp-server
3. Configure S3 endpoint → SeaweedFS S3 gateway
4. Deploy MongoDB backup CronJob → B2
5. Configure k8gb Gslb CRDs with geoip strategy
6. Smoke test: access via direct node IPs, upload images, verify DNS

### Phase 4 — Backup Layer

1. Create Backblaze B2 bucket (new key, separate from DO Spaces)
2. Generate rclone crypt keys (separate keys for B2 and RustFS)
3. Deploy backup CronJob: rclone crypt → B2 + rclone crypt → RustFS
4. Configure Healthchecks.io monitoring
5. Enable B2 Object Lock (governance mode, 30-day retention)
6. Test restore: rclone sync from B2 to a test bucket

### Phase 5 — DNS Go-Live

1. Verify everything works via direct IPs
2. Point new domain DNS at k8gb CoreDNS IPs
3. Monitor: error rates, DNS resolution, certificate renewal, backup health
4. Optional: enable Bunny CDN pull zone, point DNS at Bunny

### Phase 6 — Data Migration (from old domain)

1. rclone sync from DO Spaces → new B2 bucket (or direct to SeaweedFS)
2. mongodump from old DOKS mongo → mongorestore to new cluster
3. Update old domain DNS to redirect to new domain
4. Decommission DOKS when traffic has fully moved

---

## 6. Rollback

Greenfield = no rollback needed until Phase 5. Before go-live, tear down and rebuild freely. After go-live, old domain still works on DOKS — revert DNS if needed.

---

## 7. Open Decisions

| Decision | Options | Resolved |
|----------|---------|----------|
| DNS provider | PowerDNS vs. deSEC vs. CF free | **PowerDNS** |
| MongoDB | Atlas vs. self-hosted | **Self-hosted, encryption at rest** |
| Object storage | B2 only vs. SeaweedFS + B2 | **SeaweedFS hot + B2 cold** |
| CDN | None vs. Bunny CDN | **Bunny CDN optional overlay** |
| Third node | US provider vs. EU | **Nuremberg CX22 (EU)** |
| New domain | TBD | **Pick a new domain for greenfield** |

---

## 8. Timeline

| Phase | Effort | Notes |
|-------|--------|-------|
| Phase 0 — Provision | 0.5 day | nixos-anywhere is fast |
| Phase 1 — Bootstrap | 1-2 days | ArgoCD sync waves automate most |
| Phase 2 — SeaweedFS | 1 day | LUKS + layout config is the hard part |
| Phase 3 — Apps | 1 day | Mostly ArgoCD sync |
| Phase 4 — Backups | 0.5 day | rclone config + CronJob |
| Phase 5 — Go-live | 0.5 day | DNS + monitoring |
| Phase 6 — Data migration | 1-2 days | rclone + mongodump |
| **Total** | **5-7 days** | Stretch across 2-3 weeks |