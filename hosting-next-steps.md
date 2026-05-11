# Hosting Next Steps: Migration to Self-Hosted k3s on Hetzner

**Status**: Plan (pre-implementation). To be refined via plan mode.

---

## 1. Target Architecture

3 independent k3s clusters running NixOS on Hetzner:
- **Ashburn, VA** (US East) — CPX21, 3 vCPU / 4GB / 80GB
- **Hillsboro, OR** (US West) — CPX21, 3 vCPU / 4GB / 80GB
- **Nuremberg, DE** (EU) — CX22, 2 vCPU / 4GB / 40GB

DNS via PowerDNS on host (NixOS systemd), k8gb geoip failover, Traefik ingress with CrowdSec, Backblaze B2 object storage, self-hosted MongoDB (encryption at rest, Longhorn PV). Full details in [`hosting-research.md`](hosting-research.md).

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

## 4. Changes to Existing Repository: `2143-k8s`

### 4.1 Ingress Migration (nginx → Traefik)

- Remove `apps-gateway-nginx` Deployment and Service
- Convert nginx Ingress annotations to Traefik-compatible equivalents
- Traefik v3.5+ nginx provider handles existing Ingress resources automatically
- Run `ingress-nginx-migration` tool for compatibility report

### 4.2 App Deployments

Existing deployments deploy identically to all 3 clusters via ArgoCD — no changes needed:
- `john2143-com`: stateless, S3-backed, S3 endpoint already configurable via env
- `mongo`: self-host with encryption at rest, active-passive across clusters
- `openfront-pro`, `openfront-pro-simulation-api`: stateless
- `poe-sale-redirector`, `poe2-sale-redirector`: stateless, deploy to raw IP
- `derp-server`: UDP, deploy to raw IP via hostPort
- `prometheus`, `grafana`: monitoring

### 4.3 S3 Endpoint Change

Update `s3-creds` Secret to point at Backblaze B2 instead of DO Spaces:
```yaml
S3_ENDPOINT_URL: https://s3.us-west-004.backblazeb2.com
S3_ACCESS_KEY: <b2-application-key-id>
S3_SECRET_KEY: <b2-application-key>
```

The `MINIO_*` env vars can be removed if no longer using MinIO, or kept if running a local MinIO cache.

### 4.4 MongoDB Migration

Self-hosted with encryption at rest (active-passive across clusters):
- Deploy mongo on Ashburn as active with `--enableEncryption` + encryption key in Kubernetes Secret
- Nuremberg and Hillsboro run standby mongo (scaled to 0), PVCs pre-provisioned via Longhorn
- Hourly CronJob: `mongodump` → B2 bucket for backup
- Failover: restore latest dump to standby, scale up, update DB connection string
- Longhorn provides volume snapshots as secondary recovery point
### 4.5 Monitoring

- Prometheus: Add k8gb metrics scrape config, CrowdSec metrics, PowerDNS metrics
- Grafana: Import k8gb dashboard, CrowdSec dashboard
- Alert rules: node bandwidth >80%, CrowdSec ban spikes, k8gb endpoint count drops

---

## 5. Migration Phases (Summary)

### Phase 0 — Preparation (DOKS side, no downtime)

1. Lower DNS TTL on all DOKS A records to 300s (do 48h before cutover)
2. Install Velero on DOKS, create full backup to S3-compatible bucket
3. Export MongoDB: `mongodump --archive --gzip`
4. Run Traefik ingress-nginx-migration compatibility check
5. Prepare `2143-k8s-infra` repo with all configs
6. Create Backblaze B2 bucket, generate MongoDB encryption key

### Phase 1 — Provision Hetzner Nodes

1. Create 3 VMs in Hetzner Cloud (Ashburn, Hillsboro, Nuremberg)
2. Deploy NixOS via nixos-anywhere + Disko: `nix run github:nix-community/nixos-anywhere -- --flake .#k3s-ashburn --target-host root@<IP>`
3. Verify PowerDNS starts, k3s is running on each node
4. Cilium install: `cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16`
5. Configure PowerDNS: add zone, set NS records, configure TSIG key for ExternalDNS

### Phase 2 — Bootstrap Cluster Services

1. Install ArgoCD on each cluster
2. Configure root App-of-Apps pointing at `2143-k8s-infra` (with per-cluster values)
3. Sync waves deploy: cert-manager → Traefik → ExternalDNS → k8gb → CrowdSec → apps
4. Verify: all 3 clusters show synced, Traefik pods running, Cilium healthy

### Phase 3 — Storage and Stateful Migration

1. Restore PVCs from Velero backup to Hetzner
2. Deploy self-hosted MongoDB with `--enableEncryption` on Ashburn (active), standby on others
3. Update app connection strings (S3 endpoint → B2, DB → self-hosted mongo)
4. Deploy identical workloads to all 3 clusters
5. Smoke test: access each cluster via direct node IP

### Phase 4 — DNS Cutover

1. Register PowerDNS NS records with domain registrar
2. Verify k8gb CoreDNS serves correct geoip responses
3. Test failover: scale down primary cluster pods, verify DNS shifts
4. Update DNS to point at k8gb CoreDNS IPs (replacing DOKS LB)
5. Monitor for 24h: error rates, DNS resolution, certificate renewal

### Phase 5 — Decommission DOKS

1. 72-hour observation period with DOKS still running
2. Final Velero backup for archive
3. Raise DNS TTLs back to operational values (3600s)
4. Delete DOKS cluster, LB, volumes from DigitalOcean
5. Cancel DO subscription

### Rollback Plan

- Phases 0-3: terminate Hetzner VMs, no production impact
- Phase 4: revert DNS record to DOKS LB IP (300s TTL = 5-min window)
- Phase 5: restore from archival Velero backup to new DOKS cluster

---

## 6. Open Decisions (to resolve before implementation)

| Decision | Options | Recommended |
|----------|---------|-------------|
| deSEC TTL exception | Request 60s exception vs. PowerDNS vs. CF free DNS | **PowerDNS** — maximum independence |
| MongoDB | Atlas M0 free vs. self-hosted active-passive | **Self-hosted** — encryption at rest, Longhorn PV, hourly backup to B2 |
| Third US node | BuyVM $15 vs. Linode $20 vs. home node | **N/A** — using EU node (Nuremberg CX22) instead of third US node |
| Cloudflare Tunnel overlay | Add as optional DDoS shield vs. skip entirely | **Skip initially** — add only if DDoS exceeds CrowdSec |
| Monitoring | Central Grafana vs. per-cluster vs. both | **Per-cluster Prometheus + central Grafana** (or Grafana Cloud free tier) |
| cert-manager DNS challenge | Let's Encrypt HTTP-01 vs. DNS-01 | **HTTP-01** via Traefik (simpler); DNS-01 if wildcard certs needed |
| ArgoCD repo strategy | Single root app vs. per-cluster apps | **Single root App-of-Apps** with per-cluster values files |

---

## 7. Timeline Estimate

| Phase | Effort | Calendar (assuming part-time) |
|-------|--------|------------------------------|
| Phase 0 — Preparation | 1-2 days | Week 1 |
| Phase 1 — Provision | 0.5 day | Week 1 |
| Phase 2 — Bootstrap | 1-2 days | Week 1-2 |
| Phase 3 — Storage migration | 0.5-1 day | Week 2 |
| Phase 4 — DNS cutover | 0.5 day + 24h monitoring | Week 2-3 |
| Phase 5 — Decommission | 0.5 day | Week 3 |
| **Total** | **4-7 days** | **~3 weeks** |
