# Plan: 2143-k8s-infra — ArgoCD GitOps Repository

## Purpose

This repo is the single source of truth for all cluster infrastructure deployed by ArgoCD across 3 independent k3s clusters (Ashburn, Hillsboro, Nuremberg). The root App-of-Apps pattern deploys everything in sync-wave order.

## Context

- **3 independent k3s clusters** — not a single stretched cluster. Each cluster has its own control plane, SQLite backend, and ArgoCD instance.
- **ArgoCD is already installed** on each cluster (bootstrapped during Phase 1 of the NixOS provisioning).
- **Per-cluster variance**: k8gb geo-tags, ExternalDNS TSIG host, Traefik hostNetwork IPs, CrowdSec LAPI host, Istio mesh ID.
- **Shared manifests**: k8gb Gslb CRDs, cert-manager Issuers, Traefik middlewares, CrowdSec LAPI, backup CronJobs.
- **Secrets**: RFC2136 TSIG key, rclone crypt passwords, MongoDB encryption key — all deployed as Kubernetes Secrets (values sourced from agenix on the NixOS host, or created manually).

## Repository Structure

```
2143-k8s-infra/
├── README.md
├── clusters/
│   ├── ashburn/
│   │   ├── k8gb-values.yaml
│   │   ├── externaldns-values.yaml
│   │   ├── traefik-values.yaml
│   │   ├── istio-values.yaml
│   │   └── crowdsec-values.yaml
│   ├── hillsboro/
│   │   ├── k8gb-values.yaml
│   │   ├── externaldns-values.yaml
│   │   ├── traefik-values.yaml
│   │   ├── istio-values.yaml
│   │   └── crowdsec-values.yaml
│   └── nuremberg/
│       ├── k8gb-values.yaml
│       ├── externaldns-values.yaml
│       ├── traefik-values.yaml
│       ├── istio-values.yaml
│       └── crowdsec-values.yaml
├── base/
│   ├── namespaces.yaml
│   ├── k8gb/
│   │   └── gslb-resources.yaml          # Gslb CRDs for all apps
│   ├── externaldns/
│   │   ├── rfc2136-secret.yaml          # TSIG key (values from agenix)
│   │   └── rfc2136-config.yaml
│   ├── cert-manager/
│   │   ├── cluster-issuer-staging.yaml
│   │   ├── cluster-issuer-prod.yaml
│   │   └── certificates.yaml
│   ├── traefik/
│   │   ├── dashboard-ingressroute.yaml
│   │   └── middlewares/
│   │       ├── ratelimit.yaml
│   │       ├── crowdsec.yaml
│   │       └── inflightconn.yaml
│   ├── crowdsec/
│   │   ├── lapi-deployment.yaml
│   │   ├── lapi-service.yaml
│   │   ├── agent-daemonset.yaml
│   │   └── firewall-bouncer-config.yaml
│   ├── istio/
│   │   ├── istio-operator.yaml           # IstioOperator CR
│   │   ├── peer-authentication.yaml      # mTLS STRICT
│   │   └── telemetry.yaml
│   ├── cilium/
│   │   └── cilium-values.yaml
│   ├── longhorn/
│   │   └── longhorn-values.yaml
│   ├── seaweedfs/
│   │   ├── seaweedfs-helmrelease.yaml
│   │   └── seaweedfs-buckets.yaml
│   ├── mongodb/
│   │   ├── deployment.yaml               # Active (ashburn) or standby (others)
│   │   ├── pvc.yaml
│   │   ├── encryption-secret.yaml
│   │   └── backup-cronjob.yaml           # mongodump → B2
│   ├── cloudnativepg/
│   │   └── cluster.yaml                  # CloudNativePG Cluster CR
│   ├── temporal/
│   │   ├── temporal-server-values.yaml
│   │   └── temporal-worker-values.yaml
│   ├── monitoring/
│   │   ├── prometheus-values.yaml
│   │   ├── grafana-values.yaml
│   │   └── healthchecks-cronjob.yaml
│   ├── backups/
│   │   ├── rclone-config-secret.yaml
│   │   └── backup-cronjob.yaml           # rclone crypt → B2 + RustFS
│   └── apps/
│       ├── john2143-com/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── ingress.yaml
│       ├── mongo/                          # Standalone mongo for imagehost
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── pvc.yaml
│       ├── openfront-pro/
│       ├── openfront-pro-simulation-api/
│       ├── poe-sale-redirector/
│       ├── poe2-sale-redirector/
│       ├── derp-server/
│       └── teamspeak/
│           ├── deployment.yaml            # Active-passive, like mongo
│           └── service.yaml
└── argocd/
    └── root-app.yaml                      # App-of-Apps entrypoint
```

## Sync Wave Ordering

ArgoCD deploys in waves. Lower numbers deploy first.

| Wave | What | Why first/last |
|------|------|---------------|
| **-2** | Namespaces | Everything needs a namespace to exist |
| **-1** | Secrets (RFC2136, rclone, mongodb encryption) | Other components reference these secrets |
| **0** | cert-manager, Cilium | cert-manager needed for TLS; Cilium is CNI (already running but may need config updates) |
| **1** | Traefik, Longhorn | Ingress and storage must exist before apps |
| **2** | ExternalDNS, k8gb | DNS must be ready before Gslb CRDs are applied |
| **3** | CrowdSec, Istio | Security and mesh after ingress |
| **4** | SeaweedFS | Object storage before apps that use S3 |
| **5** | MongoDB, CloudNativePG, Temporal | Stateful services before stateless apps |
| **6** | Apps (john2143-com, openfront, poe, derp, teamspeak) | Everything else is ready |
| **7** | Monitoring (Prometheus, Grafana) | Scrape everything deployed above |
| **8** | Backups (rclone CronJobs, Healthchecks.io) | Back up after everything is running |

## Key Per-Cluster Values

### k8gb (per cluster)

```yaml
# clusters/ashburn/k8gb-values.yaml
k8gb:
  clusterGeoTag: "us-ashburn"
  extGslbClustersGeoTags: "us-hillsboro,eu-nuremberg"
  reconcileRequeueSeconds: 10
  dnsZones:
    - parentZone: "<YOUR_DOMAIN>"
      loadBalancedZone: "lb.<YOUR_DOMAIN>"
  edgeDNSServers:
    - "1.1.1.1"
  splitBrainCheck: true
  splitBrainTXTTTL: 30

coredns:
  isClusterService: false
  serviceType: "LoadBalancer"

extdns:
  enabled: true
  interval: 20s
  domainFilters:
    - "<YOUR_DOMAIN>"
  txtPrefix: "k8gb-ash-"
  txtOwnerId: "k8gb-ash"
```

Hillsboro: `clusterGeoTag: "us-hillsboro"`, `txtPrefix: "k8gb-hil-"`, `txtOwnerId: "k8gb-hil"`.
Nuremberg: `clusterGeoTag: "eu-nuremberg"`, `txtPrefix: "k8gb-nur-"`, `txtOwnerId: "k8gb-nur"`.

### ExternalDNS (per cluster)

All three clusters share the same RFC2136 TSIG key. The ExternalDNS provider is `rfc2136` with multiple hosts:

```yaml
# clusters/ashburn/externaldns-values.yaml
provider: rfc2136
rfc2136:
  host: "k3s-ashburn.<YOUR_DOMAIN>"
  port: 53
  zone: "<YOUR_DOMAIN>"
  tsigKeyname: "externaldns"
  tsigSecretAlg: "hmac-sha256"
  tsigSecret: "<from-secret>"
  loadBalancingStrategy: "round-robin"
```

Hillsboro: `host: "k3s-hillsboro.<YOUR_DOMAIN>"`.
Nuremberg: `host: "k3s-nuremberg.<YOUR_DOMAIN>"`.

### Traefik (per cluster)

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

hostNetwork: true  # Bind to protected IP on the node
```

### Istio (per cluster)

```yaml
# clusters/ashburn/istio-values.yaml
meshConfig:
  accessLogFile: /dev/stdout
  defaultConfig:
    terminationDrainDuration: 45s

pilot:
  resources:
    requests:
      cpu: 100m
      memory: 512Mi

global:
  meshID: "mesh-ashburn"     # Unique per cluster
  network: "ashburn-network"
  multiCluster:
    clusterName: "ashburn"
```

Hillsboro: `meshID: "mesh-hillsboro"`, `clusterName: "hillsboro"`.
Nuremberg: `meshID: "mesh-nuremberg"`, `clusterName: "nuremberg"`.

## Critical CRDs and Manifests

### k8gb Gslb Resources (`base/k8gb/gslb-resources.yaml`)

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
      - host: john2143.com            # Replace with actual domain
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
      - host: openfront.<DOMAIN>
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: openfront-pro
                  port:
                    number: 80
---
# poe.sale, poe2.sale, derp-server, TeamSpeak:
#   These are raw-IP services — NO Gslb CRD.
#   DNS A records point directly at the raw IPs.
#   No k8gb involvement. No geoip routing.
```

### Traefik Middlewares (`base/traefik/middlewares/`)

```yaml
# ratelimit.yaml
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
# crowdsec.yaml
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
---
# inflightconn.yaml
apiVersion: traefik.io/v1alpha1
kind: MiddlewareTCP
metadata:
  name: john2143-inflight
spec:
  inFlightConn:
    amount: 10
```

### cert-manager (`base/cert-manager/`)

```yaml
# cluster-issuer-prod.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: john@john2143.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          rfc2136:
            nameserver: "k3s-ashburn.<DOMAIN>"
            tsigKeyName: "externaldns"
            tsigAlgorithm: "HMACSHA256"
            tsigSecretSecretRef:
              name: rfc2136-credentials
              key: rfc2136TsigSecret
```

### CloudNativePG Cluster (`base/cloudnativepg/cluster.yaml`)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: temporal-postgres
spec:
  instances: 1               # 1 per cluster (only active on Ashburn)
  storage:
    size: 10Gi
    storageClass: longhorn
  wal:
    size: 2Gi
  backup:
    barmanObjectStore:
      destinationPath: "s3://temporal-backups/"
      s3Credentials:
        accessKeyId:
          name: b2-credentials
          key: S3_ACCESS_KEY
        secretAccessKey:
          name: b2-credentials
          key: S3_SECRET_KEY
      wal:
        compression: gzip
        maxParallel: 2
    retentionPolicy: "30d"
```

### MongoDB (`base/mongodb/`)

Active on Ashburn, standby (scaled to 0) on Hillsboro and Nuremberg.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongo
spec:
  replicas: 1               # 0 on standby clusters
  template:
    spec:
      containers:
      - name: mongo
        image: mongo:7
        args:
          - "--auth"
          - "--enableEncryption"
          - "--encryptionKeyFile=/etc/mongo/encryption.key"
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: admin
        - name: MONGO_INITDB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mongo-creds
              key: password
        volumeMounts:
        - mountPath: /data/db
          name: mongodata
        - mountPath: /etc/mongo
          name: mongo-encryption-key
      volumes:
      - name: mongodata
        persistentVolumeClaim:
          claimName: mongo-pvc
      - name: mongo-encryption-key
        secret:
          secretName: mongo-encryption-key
---
# backup-cronjob.yaml — hourly mongodump → B2
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongo-backup
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mongodump
            image: mongo:7
            command:
              - /bin/sh
              - -c
              - |
                mongodump --uri="mongodb://admin:$MONGO_PASSWORD@mongo:27017" --archive --gzip | \
                rclone rcat b2-crypt:mongo-backups/$(date +%Y%m%d-%H%M).archive.gz
            env:
            - name: MONGO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongo-creds
                  key: password
```

### rclone Backup CronJob (`base/backups/`)

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: object-store-backup
spec:
  schedule: "0 3 * * *"       # 3 AM UTC daily
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: rclone
            image: rclone/rclone:latest
            command:
              - /bin/sh
              - -c
              - |
                set -e
                curl -fsS "${HC_URL}/start" > /dev/null || true
                rclone sync /data b2-crypt: --fast-list --transfers 32
                B2_RC=$?
                rclone sync /data rustfs-crypt: --fast-list --transfers 16
                RUSTFS_RC=$?
                [ $B2_RC -ne 0 ] || [ $RUSTFS_RC -ne 0 ] && RC=1 || RC=0
                curl -fsS "${HC_URL}/${RC}" > /dev/null || true
                exit $RC
            envFrom:
            - secretRef:
                name: healthchecks-url
            volumeMounts:
            - name: rclone-config
              mountPath: /etc/rclone
              readOnly: true
          volumes:
          - name: rclone-config
            secret:
              secretName: rclone-config
```

### ArgoCD Root App-of-Apps (`argocd/root-app.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/John2143/2143-k8s-infra
    targetRevision: HEAD
    path: argocd
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
---
# Each child Application references a subdirectory path and a sync wave.
# Example child app:
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: namespaces
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  project: default
  source:
    repoURL: https://github.com/John2143/2143-k8s-infra
    targetRevision: HEAD
    path: base
    # Uses kustomize or plain YAML — just the namespaces.yaml file
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
# cert-manager (wave 0), Traefik (wave 1), ExternalDNS (wave 2), etc.
# Each is a separate Application with its own sync-wave annotation
# and path pointing at base/<component>/.
```

## Secrets That Need to Be Created Manually (Not in Git)

The following Kubernetes Secrets must exist before ArgoCD syncs. They are created by the NixOS host config (agenix decryption at boot) or manually with `kubectl create secret`:

| Secret | Namespace | Keys | Source |
|--------|-----------|------|--------|
| `rfc2136-credentials` | `external-dns` | `rfc2136TsigSecret` | `agenix -d hetzner/powerdns-tsig-key.age` |
| `rclone-config` | `backup` | `rclone.conf` | Generated from `agenix -d hetzner/rclone-b2-password.age` etc. |
| `healthchecks-url` | `backup` | `HC_URL` | Healthchecks.io ping URL (manual) |
| `mongo-creds` | `default` | `password` | `agenix -d hetzner/mongodb-encryption-key.age` |
| `mongo-encryption-key` | `default` | `encryption.key` | Same age secret |
| `b2-credentials` | `default` | `S3_ACCESS_KEY`, `S3_SECRET_KEY` | Backblaze B2 Application Key (manual) |
| `seaweedfs-master-key` | `seaweedfs` | `master.key` | `agenix -d hetzner/seaweedfs-master-key.age` |
| `temporal-postgres-password` | `default` | `password` | Generated random |

## Helm Charts Used

| Component | Chart | Repo |
|-----------|-------|------|
| cert-manager | `cert-manager` | https://charts.jetstack.io |
| Traefik | `traefik` | https://helm.traefik.io/traefik |
| ExternalDNS | `external-dns` | https://kubernetes-sigs.github.io/external-dns/ |
| k8gb | `k8gb` | https://www.k8gb.io |
| Istio | `istio-base` + `istiod` | https://istio-release.storage.googleapis.com/charts |
| CrowdSec | `crowdsec` | https://crowdsecurity.github.io/helm-charts |
| Longhorn | `longhorn` | https://charts.longhorn.io |
| SeaweedFS | `seaweedfs` | https://seaweedfs.github.io/seaweedfs/helm |
| CloudNativePG | `cloudnative-pg` | https://cloudnative-pg.github.io/charts |
| Temporal | `temporal` | https://helm.temporal.io |
| Prometheus | `kube-prometheus-stack` | https://prometheus-community.github.io/helm-charts |
| Grafana | `grafana` | https://grafana.github.io/helm-charts |

## What This Repo Does NOT Include

- **NixOS configurations** — those live in the dotfiles repo (`nixos/hetzner/`)
- **ArgoCD installation itself** — bootstrapped during Phase 1 of NixOS provisioning
- **PowerDNS/Galera configuration** — handled by NixOS modules on the host
- **k3s installation** — handled by NixOS services.k3s
- **Tailscale** — handled by NixOS services.tailscale
- **The Home Pi** — separate NixOS config (`rpi4b-configuration.nix`)
- **Bunny CDN configuration** — manual DNS change, not in K8s
- **Backblaze B2 bucket creation** — manual, one-time, via Backblaze web console

## New Domain

The deployment uses a **new domain** (greenfield). All Ingress hosts, cert-manager certificates, and Gslb CRDs use this new domain. The old domain (`john2143.com`) continues on DOKS until Phase 6 data migration.

Replace `<YOUR_DOMAIN>` / `<DOMAIN>` placeholders throughout this repo with the actual new domain name.
