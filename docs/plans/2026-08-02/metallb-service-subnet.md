# MetalLB Deployment — BGP mode, replace kube-vip (v3 — verified)

- **Date:** 2026-08-02
- **Status:** Plan only — nothing implemented yet
- **Supersedes:** `docs/plans/2026-08-02/metallb-service-subnet.md` (v2) and `docs/plans/2026-07-20/metallb-service-subnet.md` (v1)
- **Verification:** every fact below was independently verified 2026-08-02 by 5 parallel read-only research agents (router, MetalLB internals, k3s internals, live service inventory, docs inventory) — see Appendix A for the evidence ledger.

---

## 0. Verification results — what changed vs v2, and why

Three real bugs in v2 would have broken the migration. Fixes are folded into the steps below:

| # | Finding | Severity | Verdict |
|---|---|---|---|
| 1 | **`BGPAdvertisement` CR is missing.** MetalLB assigns pool IPs but announces nothing without it — every service stays `<pending>`, the Step 8 API-VIP takeover silently fails. (source: `speaker/bgp_controller.go`, docs) | **CRITICAL** | Add `workloads/metallb/bgpadvertisement.yaml` (empty spec = applies to all pools). **Step 3** |
| 2 | **MD5 Secret type wrong.** `kubectl create secret generic` makes `Opaque`; frr-k8s enforces `kubernetes.io/basic-auth` and hard-fails MD5 auth otherwise (source: frr-k8s `api_to_config.go`). | **CRITICAL** | Add `--type=kubernetes.io/basic-auth`. **Step 10** |
| 3 | **`192.168.5.10:port` consumers die with kube-vip removal.** After Step 8, `.10` is a MetalLB LB serving **6443 only**. Two live consumers break: pite's Prometheus remoteWrite (`pite-canary.nix:124` → `.10:30674` mimir) and UniFi web UI access (`https://192.168.5.10:30443`, documented in network-engineer SKILL.md:386/392). | **CRITICAL** | Convert `mimir-lb` (`.6.23`) + `loki-push-lb` (`.6.24`) + `unifi-web` (`.6.25`) to MetalLB; repoint pite remoteWrite at `.6.23:8080`; update docs. **Steps 5, 6, 11** |

Corrected mechanics (conclusions unchanged, reasons fixed):

| # | Finding | Effect on plan |
|---|---|---|
| 4 | **k3s `#6773` is CLOSED.** k3s v1.35.6 **does** skip services with `spec.loadBalancerClass` (CCM `wantsLoadBalancer()` requires `class == nil`). v2's cited reason was wrong; the conclusion (disable servicelb) still holds because v2 assigns IPs via annotations without a class. | Keep annotation path + `--disable=servicelb`. Class-based coexistence documented as alternative (**Appendix B**). |
| 5 | **`externalTrafficPolicy: Local` IS functional in BGP mode** — MetalLB skips announcing from nodes without a healthy local endpoint. v2's "drops traffic" rationale was wrong. Only **coturn** is `Local` cluster-wide; traefik and livekit are already `Cluster`. | Keep converting coturn to `Cluster` (full 6-node ECMP is the north star) — corrected rationale. Traefik/livekit ETP rows deleted (no-ops). |
| 6 | **traefik annotation mechanism:** `services.k3s.extraManifests` **does not exist** in the pinned nixpkgs. The live mechanism is `services.k3s.manifests.traefik-config.content` (`closet-configuration.nix:140-153`) — a HelmChartConfig that **already exists** (merge, don't create). NixOS tmpfiles only runs at boot → after editing valuesContent, run `systemd-tmpfiles --create` (or reboot) before the k3s watcher picks it up. | **Step 5** rewritten. |
| 7 | **dst-nat indices off by one** from rule 9: live rule 9 is the srcnat masquerade. Unchanged rules are live **0** (Monero→.76), **5** (Postgres→.35), **20** (Linkerd→.36); 7/8 (minecraft→.175 bare-metal) stay unchanged because minecraft row is dropped. `set [find dst-port=N protocol=P]` commands are port-based and correct. | **Step 5** table renumbered. |
| 8 | **RouterOS v7 moved `ttl` under the local group** — `ttl=255` errors; use `local.ttl=255`. `tcp-md5-key` valid. | **Step 10** command fixed. |
| 9 | **`/routing bgp connection print detail` returns EMPTY** on this router — backup must use `/routing bgp connection export`. | **Step 0** fixed. |
| 10 | **big (.68) and office (.209) are dynamic DHCP leases** (30m lease-time, pool .50–.254; closet/arch/nas/pit are statically pinned). BGP peer IPs pinned to dynamic leases silently break on lease relocation. | NEW **Step 2.0**: static DHCP leases (big `BC:24:11:19:22:F9`, office `C4:3D:1A:F3:0E:76`) before BGP connections. |
| 11 | **Same-remote-ASN coexistence is proven live**: 3 kube-vip eBGP connections all `remote.as=65000`, all Established. v2's "fallback to AS 65002" is unnecessary. | Removed fallback; verified. |
| 12 | **Minecraft row dropped.** No k8s minecraft exists (live + argo grep); bare-metal paperMC on nas (`nas-configuration.nix:562`, dst-nat 7/8 → `.175:32565`). | Table row + rules 7/8 removed. |
| 13 | **stalwart needs a template change** — `charts/stalwart/templates/service.yaml` (lines 16-35) does not render `service.annotations`; values alone do nothing. | **Step 5**: 2-file change. |
| 14 | **mosquitto 1883 has no dst-nat rule** live (LAN-only MQTT today) — conversion needs no dst-nat change. | Table note. |
| 15 | **`tuwunel/livekit-rtc-svc.yaml` is a dead duplicate** (byte-identical, unreferenced — live svc is owned by the livekit app). | Optional cleanup. |
| 16 | **`spec.password` is NOT removed in 0.16.1** (v2's claim wrong); `passwordSecret` remains the right choice. | Step 10 text fixed. |
| 17 | **Annotation prefix:** `metallb.universe.tf/*` is deprecated-but-honored in 0.16.1; current prefix is `metallb.io/*`. | All examples use `metallb.io/`. |
| 18 | **EndpointSlice ready conditions:** not required (nil = ready) but recommended. | Add `conditions: {ready: true}` to kubernetes-api EndpointSlice. |
| 19 | **frr-k8s verification pinned:** pods `metallb-frr-k8s-<hash>` (`-c frr` vtysh), plus `bgpsessionstates.frrk8s.metallb.io` + `servicebgpstatuses` CRs. Chart needs **no values overrides** (`frrk8s.enabled: true`, `speaker.tolerateMaster: true`, `crds.enabled: true` all default). | **Steps 3-4** commands exact. |
| 20 | **`.6.0/24` routes with no firewall-filter change**: forward rule 1 accepts `192.168.0.0/16` (⊃ .6.0/24); no filter rule touches 179; WAN dst-nat is exempt. RouterOS 7.19.6, bridge named `bridge`. | Steps 1-2 confirmed. |
| 21 | **traefik svc is PreferDualStack** (IPv4+IPv6 families) but the pool is IPv4-only — v6 family of the svc will have no LB address after conversion. Tolerable; confirm nothing depends on traefik's ULA service IP. | Plan note. |
| 22 | **Staggered-rebuild hazard** (Step 7): between the first and last server rebuild, not-yet-rebuilt CCMs can transiently re-create svclb DaemonSets. Mitigation: keep services quiescent; final state clean (deleteAllDaemonsets on restart — verified, no orphans). | Step 7 note. |

---

## 1. Context — verified live state (2026-08-02)

### Cluster
| Node | IP | Role | DHCP |
|---|---|---|---|
| arch | 192.168.5.76 | control-plane, etcd | static lease |
| closet | 192.168.5.36 | control-plane, etcd (joins via `--server=https://192.168.5.10:6443`) | static lease |
| nas | 192.168.5.175 | control-plane, etcd | static lease |
| big | 192.168.5.68 | worker (joined ~2026-07-29) | **DYNAMIC** |
| office | 192.168.5.209 | worker | **DYNAMIC** |
| pite | 192.168.5.9 | worker | static lease |

- k3s **v1.35.6+k3s1**, flannel VXLAN (`10.42.0.0/16` + `fd42:42:42::/56`, dual-stack), NodePort range 30000-32767. Pod CIDR is **/16** (SKILL.md says /24 — stale, fix in docs).
- LoadBalancer provider today = **k3s klipper ServiceLB**: 6 svclb DaemonSets (traefik, unifi-inform, unifi-discovery, stalwart-stalwart, coturn, livekit-server-rtc), 24 pods. LB services show node-IP lists as EXTERNAL-IP. coturn svc is `<pending>` (status empty) despite its svclb DS — confirmed.
- **kube-vip** (ArgoCD-managed DaemonSet, `apps/kube-vip.yaml`) runs BGP, `--controlplane` only; API VIP `192.168.5.10/32` announced via BGP. 3 connections on the router (arch .76, closet .36, nas .175), all `remote.as=65000`, ebgp, **no MD5**. Sessions Established; closet is current leader (prefix-count=1, VIP route `gateway 192.168.5.36 distance 20`). VIP never on physical NICs (prevents Flannel FDB corruption — L2/ARP modes are off the table).
- kubectl context `closet-as-developer`, server `https://192.168.5.10:6443`.

### Router (MikroTik)
- RouterOS **7.19.6** (stable), RB5009. Bridge named **`bridge`** (multi-subnet: .5.1/24, .1.1/24, .88.254/24). `192.168.6.0/24` absent.
- DHCP pool `192.168.5.50-254`, 30m lease. Static leases pin closet/arch/nas/pite + cameras; **big/office dynamic**.
- dst-nat: 21 rules (0-20); live rule 9 = srcnat masquerade (hence index offsets). No rule for 1883 (mosquitto), 30108/30674 (observability), 30443 (unifi-web) — all LAN-only.
- Firewall filter: nothing blocks BGP 179 from LAN nodes; `.6.0/24 ⊂ 192.168.0.0/16` routes and forwards with zero filter changes.
- Same-ASN multi-peer: proven (3× remote.as=65000 Established).

### Service inventory (conversion target + untouched)
16 LB/NodePort services. 15 convert (below), the rest stay NodePort/ClusterIP.

### Pre-existing unrelated issues (out of scope, do not fix during migration)
- Noted 2026-08-02: unifi pod (2/2 Running) and desec-webhook (Running) — earlier CrashLoopBackOffs have self-healed; no action needed. UniFi controller healthy: `https://192.168.5.10:30443/status` → `{"up":true,"server_version":"10.4.57"}`.

### Before / After (plain English)

**Before (today):**
- A `LoadBalancer` service does **not** get its own IP — k3s klipper hands it a list of *node IPs* that changes as nodes come and go. Verified live 2026-08-02: `unifi-inform` = `192.168.5.175, 192.168.5.36, 192.168.5.68, 192.168.5.76` — the list already grew to include new worker `big` (.68). coturn's is stuck `<pending>`. No service has a stable, dedicated address.
- LAN access = a node IP + a high NodePort (`192.168.5.175:30443`) or `192.168.5.10:<nodePort>`.
- WAN access = router dst-nat forwards port → `192.168.5.10:<nodePort>` — i.e. WAN → VIP → node → NodePort → pod. Two indirect hops; the VIP hop only works because kube-vip floats `.10` on a single leader node's loopback (5-15s failover, single announcement point).
- kube-vip's only job is announcing the k8s API VIP `.10`.

**After:**
- Every exposed service gets its **own dedicated IP from `192.168.6.10-.50`** (e.g. traefik `.6.10`, ts-voice `.6.15`, coturn `.6.21`), announced by MetalLB over BGP to the MikroTik.
- The router ECMPs each `.6.x` across all 6 nodes — traffic lands on *any* node and kube-proxy DNATs it to the right pod. No leader, no loopback VIP; failover is seconds and moves nothing.
- WAN dst-nat forwards **directly** to `.6.x:servicePort` — one hop, no NodePort in the path.
- `.10` keeps its address but now serves only the k8s API (MetalLB-announced) — same IP, so `kubectl` config, TLS SANs, and Tailscale routes are untouched.

```
BEFORE
  WAN ──dst-nat──▶ 192.168.5.10:nodePort ──▶ kube-vip VIP (leader node) ──▶ pod
  LAN ───────────▶ node-IP:nodePort ──────────────────────────────────────▶ pod   (no stable IP)

AFTER
  WAN ──dst-nat──▶ 192.168.6.x:servicePort ──▶ BGP/ECMP (any of 6 nodes) ──▶ kube-proxy DNAT ──▶ pod
  LAN ───────────▶ 192.168.6.x:servicePort ──▶ same path                            (stable IP, instant failover)
```

### What changes where (one-line map)

| Where | Change |
|---|---|
| `~/repos/argo` | + `apps/metallb.yaml`, `apps/metallb-config.yaml`, `workloads/metallb/` (2 pools, BGPPeer, BGPAdvertisement, kubernetes-api svc); + `https://metallb.github.io/metallb` in `main.yaml` sourceRepos; 15 service files get the `.6.x` annotation (+ 3 type → LoadBalancer); `apps/kube-vip.yaml` + `workloads/kube-vip/` deleted |
| `~/repos/dotfiles` | `k3s-agent.nix` port 179; `closet/arch/nas-configuration.nix` `--disable=servicelb`; `closet-configuration.nix` traefik annotation; `pite-canary.nix` remoteWrite URL; network-engineer/argo-engineer skills + docs |
| MikroTik (not in git) | 2 static DHCP leases (big/office), `192.168.6.1/24`, 6 BGP connections, 13 dst-nat target updates, (optional) BGP MD5 + `local.ttl` |
| Cluster only (kubectl, not in git) | `metallb-bgp-secret` (optional MD5; `kubernetes.io/basic-auth`) |

---

## 2. North star (unchanged)

One coherent BGP-native system: **MetalLB is the sole BGP speaker** on all 6 nodes, announcing the k8s API VIP (`192.168.5.10`) and service IPs from `192.168.6.0/24`. dst-nat rules point at direct service IPs instead of `.10:nodeport` hops. No kube-vip. No klipper. BGP (not L2/ARP) — ECMP across all nodes, instant failover; L2 previously caused Flannel FDB corruption in this cluster.

## 3. Decisions (all resolved by verification)

1. **Maintenance window:** 2 hours, low-traffic. Traefik (80/443) converts last. k8s API has **no gap** during kube-vip removal (MetalLB takes over `.10` first; removal = ECMP losing a path).
2. **`--disable=servicelb` in all 3 host configs** (module `mkDefault` is overridden by hosts — verified). Class-based alternative in Appendix B.
3. **`externalTrafficPolicy`: only coturn converts to `Cluster`.** Traefik/livekit already Cluster. If coturn client-IP preservation is ever required, use `Local` + BGPAdvertisement `nodeSelector` — not `Cluster`-without-thought.
4. **Kyverno: skipped** (not installed; single-admin; `autoAssign: false` prevents random `.10` grabs). Explicit-request risk documented and accepted.
5. **minecraft: NOT in scope** (bare-metal on nas).
6. **MD5 auth: optional (Step 10)**. If skipped, session-hijack risk on the LAN is accepted.
7. **Annotation prefix: `metallb.io/*`** (current; `metallb.universe.tf/*` deprecated-but-works).

## 4. Pre-flight (Step 0) — backups + hygiene

```bash
cd ~/repos/argo && git status          # clean or resolve nvidia-device-plugin decision first

kubectl --context closet-as-developer get svc -A -o yaml > /tmp/all-services-before.yaml
mikrotik-connect r '/ip firewall nat export file=backup-before-metallb'
mikrotik-connect r '/export' > /tmp/router-backup-before-metallb.rsc   # FULL config: addresses, leases, filter, nat, bgp
mikrotik-connect r '/routing bgp connection export' > /tmp/bgp-peers-before.txt   # print detail returns EMPTY on 7.19.6!
ssh closet.local "kubectl get ds -n kube-system kube-vip -o yaml" > /tmp/kube-vip-ds-before.yaml

# Find every .10:<port> consumer that will die when .10 becomes 6443-only
grep -rn "192.168.5.10:" ~/repos/dotfiles --include="*.nix" --include="*.md" | grep -v 6443
grep -rn "192.168.5.10:" ~/repos/argo --include="*.yaml" --include="*.md" | grep -v 6443
```
Known consumers (verified): `pite-canary.nix:124` (remoteWrite 30674 → fixed in Step 6), network-engineer SKILL.md:386/392 (unifi-web 30443 → fixed in Step 5/11). The grep must return **no other** hits before Step 8.

**Repo hygiene:** decide on untracked `workloads/nvidia-device-plugin/` in `~/repos/argo` — commit separately or stash, before starting.

## 5. Step 1 — NixOS: open port 179 on workers

Add to `dotfiles/nixos/modules/k3s-agent.nix` (after the `gracefulNodeShutdown` block, ~line 45; NixOS merges with each host's own lists — big/office/pite):
```nix
networking.firewall.allowedTCPPorts = [
  179 # BGP (MetalLB speaker)
];
```
Control planes already have 179 (arch:157, closet:192, nas:564 — comments say "for kube-vip"; update comment to MetalLB). Rebuild the 3 workers (firewall only — no k3s restart):
```bash
ssh root@192.168.5.68 nixos-rebuild switch   # big
ssh root@192.168.5.209 nixos-rebuild switch  # office
ssh root@192.168.5.9 nixos-rebuild switch    # pite
```

## 6. Step 2 — MikroTik: static leases, service subnet, BGP connections

### 2.0 Static DHCP leases for big + office (REQUIRED — they're the only dynamic ones)
4 of 6 k3s nodes already have router reservations (closet .36, arch .76, nas .175, pite .9 — verified live 2026-08-02). **big (.68) and office (.209) are the only dynamic leases** (30m lease-time, pool .50-.254). A relocated lease would silently break: the MetalLB BGP peer pins (`remote.address` above), the flannel VXLAN underlay to that node, and kubelet re-registration. Add reservations to match the house pattern (address is inside the pool — the client's current IP is unchanged, no disruption):
```bash
mikrotik-connect r '/ip dhcp-server lease add address=192.168.5.68 mac-address=BC:24:11:19:22:F9 server=dchp1 comment="big k3s node (static)"'
mikrotik-connect r '/ip dhcp-server lease add address=192.168.5.209 mac-address=C4:3D:1A:F3:0E:76 server=dchp1 comment="office k3s node (static)"'
mikrotik-connect r '/ip dhcp-server lease print'   # both now static
```

### 2.1 Subnet + BGP connections
```bash
mikrotik-connect r '/ip address add address=192.168.6.1/24 interface=bridge'
ping -c 1 192.168.6.1

# 6 connections — same shape as existing kube-vip config (add local.address for parity)
mikrotik-connect r '/routing bgp connection add name="metallb-arch"   remote.address=192.168.5.76  remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
mikrotik-connect r '/routing bgp connection add name="metallb-closet" remote.address=192.168.5.36  remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
mikrotik-connect r '/routing bgp connection add name="metallb-nas"    remote.address=192.168.5.175 remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
mikrotik-connect r '/routing bgp connection add name="metallb-office" remote.address=192.168.5.209 remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
mikrotik-connect r '/routing bgp connection add name="metallb-pite"   remote.address=192.168.5.9   remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
mikrotik-connect r '/routing bgp connection add name="metallb-big"    remote.address=192.168.5.68  remote.as=65000 local.address=192.168.5.1 local.role=ebgp as=65001'
```
Sessions show down until MetalLB speakers come up — expected. Same-ASN coexistence with the 3 kube-vip peers is proven (no fallback needed).

## 7. Step 3 — ArgoCD: MetalLB chart + config apps

**`argo/main.yaml`** — add to `default` AppProject `sourceRepos` (after line 18):
```yaml
    - https://metallb.github.io/metallb
```
No `clusterResourceWhitelist` change: CRDs, RBAC, Namespace already whitelisted; chart ships no PriorityClass (verified — metallb + frr-k8s subchart).

**`argo/apps/metallb.yaml`** — chart 0.16.1, **no values overrides** (defaults are correct: `frrk8s.enabled: true`, `crds.enabled: true`, `speaker.tolerateMaster: true`; do **not** set `speaker.frr` — deprecated):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: metallb
    repoURL: https://metallb.github.io/metallb
    targetRevision: 0.16.1
    helm:
      releaseName: metallb
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**`argo/apps/metallb-config.yaml`** — same shape as above but `path: workloads/metallb`, repoURL `https://github.com/2143-Labs/argo.git`, targetRevision HEAD.

**`argo/workloads/metallb/ipaddresspool.yaml`**:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: services
  namespace: metallb-system
spec:
  addresses:
  - 192.168.6.10-192.168.6.50
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: control-plane-vip
  namespace: metallb-system
spec:
  addresses:
  - 192.168.5.10-192.168.5.10
  autoAssign: false
```

**`argo/workloads/metallb/bgppeer.yaml`** (no password until Step 10):
```yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: mikrotik-router
  namespace: metallb-system
spec:
  myASN: 65000
  peerASN: 65001
  peerAddress: 192.168.5.1
```

**`argo/workloads/metallb/bgpadvertisement.yaml`** — **THE MISSING PIECE (finding 1). Empty spec = applies to ALL pools**:
```yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp
  namespace: metallb-system
```

Commit + push, verify:
```bash
cd ~/repos/argo
git add main.yaml apps/metallb.yaml apps/metallb-config.yaml workloads/metallb/
git commit -m "feat(metallb): BGP mode on 192.168.6.0/24 (chart 0.16.1), replaces kube-vip"
git push origin main

kubectl --context closet-as-developer get pods -n metallb-system -o wide
# EXPECT: metallb-controller (1) + metallb-speaker-* (6) + metallb-frr-k8s-* (6, has `frr` container) + metallb-frr-k8s-statuscleaner (1)
kubectl --context closet-as-developer get ipaddresspool,bgppeer,bgpadvertisement -n metallb-system
```

## 8. Step 4 — Verify BGP + warm-up conversion

```bash
FRR_POD=$(kubectl --context closet-as-developer get pod -n metallb-system -l app.kubernetes.io/component=frr-k8s -o jsonpath='{.items[0].metadata.name}')
kubectl --context closet-as-developer exec -n metallb-system $FRR_POD -c frr -- vtysh -c "show bgp summary"
# EXPECT 192.168.5.1 State=Established, 6 peers (one per node)
kubectl --context closet-as-developer get bgpsessionstates.frrk8s.metallb.io -n metallb-system
kubectl --context closet-as-developer get servicebgpstatuses -n metallb-system
```

**Warm-up — `unifi-inform` → `.6.11`** (`argo/workloads/unifi/unifi-service.yaml`, insert annotations after the `labels:` block, line 5):
```yaml
  annotations:
    metallb.io/loadBalancerIPs: "192.168.6.11"
```
klipper keeps serving node-IPs in parallel (double coverage, zero downtime). Commit, push, wait sync, verify `nc -zv 192.168.6.11 8080`. If it fails, STOP — BGP/ECMP path is broken; fix before touching anything else.

## 9. Step 5 — Convert remaining services (one at a time, risk-ordered)

Per service: edit → commit → push → sync → verify `.6.x` → update dst-nat (where a rule exists) → verify from WAN → next. **Do NOT batch.**

| IP | Service | ns | File to edit | Change |
|---|---|---|---|---|
| .6.10 | traefik | kube-system | `dotfiles/nixos/closet-configuration.nix:140-153` (HelmChartConfig) | **Merge** `service.annotations` into EXISTING valuesContent — see below. Convert LAST. No ETP change (already Cluster). |
| .6.11 | unifi-inform | default | `workloads/unifi/unifi-service.yaml:1-15` | annotation only (Step 4) |
| .6.12 | unifi-discovery | default | `workloads/unifi/unifi-service.yaml:34-48` | annotation only |
| .6.13 | stalwart-stalwart | stalwart | `charts/stalwart/values.yaml:39-44` **+** `charts/stalwart/templates/service.yaml:16-35` | values `service.annotations` + template must render it (below) |
| .6.15 | ts-voice | default | `workloads/teamspeak/service.yaml:21-34` | annotation + `type: NodePort → LoadBalancer` |
| .6.16 | ts-files | default | `workloads/teamspeak/service.yaml:36-49` | annotation + type → LB |
| .6.17 | openrct2-game | default | `workloads/openrct2/openrct2.yaml:61-74` | annotation + type → LB (deployment is replicas:0 — trivial) |
| .6.18 | headscale-stun | default | `workloads/headscale/service.yaml:21-36` | annotation + type → LB |
| .6.19 | mosquitto-nodeport | default | `workloads/mosquitto/service.yaml:17-32` | annotation + type → LB; **no dst-nat rule exists** (LAN-only) |
| .6.20 | temporal-frontend | default | `apps/temporal.yaml:64-66` | `type: NodePort → LoadBalancer` + `annotations` (chart keys verified: `frontend.service.annotations`) |
| .6.21 | coturn | matrix | `workloads/coturn/coturn-svc.yaml` | line 7: swap `kube-vip.io/loadbalancerIPs` → `metallb.io/loadBalancerIPs: "192.168.6.21"`; line 10: `Local → Cluster` |
| .6.22 | livekit-server-rtc | matrix | `workloads/livekit/rtc-service.yaml:7` | annotation swap only (already Cluster; no ETP field) |
| .6.23 | mimir-lb | observability | `workloads/observability/lb-services.yaml:1-16` | annotation + type → LB; port 8080 |
| .6.24 | loki-push-lb | observability | `workloads/observability/lb-services.yaml:18-35` | annotation + type → LB; port 3100 |
| .6.25 | unifi-web | default | `workloads/unifi/unifi-service.yaml:17-32` | annotation + `type: NodePort → LoadBalancer` (port 8443) — **replaces the `.10:30443` access path**; verify `curl -sk https://192.168.6.25:8443/status` → `{"up":true}` |

**Removed vs v2:** minecraft (no k8s service; bare-metal on nas), traefik ETP change (already Cluster), livekit ETP change (already Cluster).

**Representative diffs:**

traefik — merge into `closet-configuration.nix` valuesContent (keep `providers.kubernetesGateway`!):
```nix
      spec.valuesContent = ''
        providers:
          kubernetesGateway:
            enabled: true
            experimentalChannel: true
        service:
          annotations:
            metallb.io/loadBalancerIPs: "192.168.6.10"
      '';
```
Then (tmpfiles caveat — finding 6): `ssh root@192.168.5.36 nixos-rebuild switch` followed by `ssh closet.local "sudo systemd-tmpfiles --create"` (or reboot closet); the k3s deploy controller re-applies the HelmChartConfig (helm job re-runs; svc gains the annotation — no k3s restart needed). Verify: `ssh closet.local "kubectl get svc traefik -n kube-system -o yaml | grep -A2 annotations"`.
Note: traefik svc is PreferDualStack — the IPv6 family will have no LB address (IPv4-only pool). Confirm nothing depends on traefik's ULA service IP before proceeding.

stalwart — `charts/stalwart/values.yaml`:
```yaml
service:
  type: LoadBalancer
  annotations:
    metallb.io/loadBalancerIPs: "192.168.6.13"
```
and `charts/stalwart/templates/service.yaml` (main svc, lines 18-21):
```yaml
  metadata:
    name: {{ include "stalwart.fullname" . }}
    labels:
      {{- include "stalwart.labels" . | nindent 4 }}
    {{- with .Values.service.annotations }}
    annotations:
      {{- toYaml . | nindent 4 }}
    {{- end }}
```

coturn:
```yaml
  annotations:
    metallb.io/loadBalancerIPs: "192.168.6.21"   # was kube-vip.io/loadbalancerIPs
...
  externalTrafficPolicy: Cluster                  # was Local
```

**dst-nat updates (live indices — finding 7; port-based `find` commands are correct as written):**

| Live rule | Proto | Port | New target | Service | Old |
|---|---|---|---|---|---|
| 1 | udp | 9987 | .6.15:9987 | ts-voice | .10:30087 |
| 2 | tcp | 30033 | .6.16:30033 | ts-files | .10:30034 |
| 3 | tcp | 80 | .6.10:80 | traefik HTTP | .10:80 |
| 4 | tcp | 443 | .6.10:443 | traefik HTTPS | .10:443 |
| 6 | udp | 30478 | .6.18:3478 | headscale-stun | .10:30478 |
| 10 | tcp | 11753 | .6.17:11753 | openrct2 | .10:31753 |
| 11-13 | tcp | 25/587/993 | .6.13:* | stalwart | .10:* |
| 14 | tcp | 7881 | .6.22:7881 | livekit WebRTC | .10:7881 |
| 15 | udp | 50000-60000 | .6.22:* | livekit media | .10:* |
| 16 | tcp | 3478 | .6.21:3478 | coturn TURN TCP | .10:3478 |
| 17 | udp | 3478 | .6.21:3478 | coturn TURN UDP | .10:3478 |
| 18 | tcp | 5349 | .6.21:5349 | coturn TURN TLS | .10:5349 |
| 19 | tcp | 7233 | .6.20:7233 | temporal gRPC | .10:7233 |

**Unchanged:** live 0 (Monero→.76:18080), 5 (Postgres→.35:5432), 7/8 (minecraft→.175:32565, bare-metal), 20 (Linkerd→.36:4143). No new rules needed for .6.23/.6.24/.6.25 (mimir/loki/unifi-web are LAN-only — no dst-nat exists for 30108/30674/30443).
```bash
mikrotik-connect r '/ip firewall nat set [find dst-port=9987 protocol=udp] to-addresses=192.168.6.15 to-ports=9987'
mikrotik-connect r '/ip firewall nat set [find dst-port=3478 protocol=tcp] to-addresses=192.168.6.21 to-ports=3478'
mikrotik-connect r '/ip firewall nat set [find dst-port=3478 protocol=udp] to-addresses=192.168.6.21 to-ports=3478'
```
Revert: `set [find dst-port=N protocol=P] to-addresses=192.168.5.10 to-ports=OLD_PORT`.

UniFi: APs on old inform node-IPs re-adopt via `.6.12` (L2 discovery); re-point statically configured inform IPs to `.6.11`.

## 10. Step 6 — Repoint pite Prometheus remoteWrite (finding 3)

With mimir-lb now on `.6.23` (Step 5), edit `dotfiles/nixos/pite-canary.nix:121-127`:
```nix
    # Remote write to home-cluster Mimir for long-term storage.
    # MetalLB service IP (was kube-vip NodePort 192.168.5.10:30674).
    remoteWrite = [
      {
        url = "http://192.168.6.23:8080/api/v1/push";
        headers = {"X-Scope-OrgID" = "anonymous";};
      }
    ];
```
Rebuild pite, verify: `curl -s http://192.168.6.23:8080/mimir/ready` from pite, then confirm series land in Mimir.

## 11. Step 7 — Disable k3s ServiceLB (coordinated cutover)

Add `--disable=servicelb` to `services.k3s.extraFlags` in **all 3 host configs** (hosts override the module's `mkDefault` — verified): `closet-configuration.nix:112` list, `arch-configuration.nix:109` list, `nas-configuration.nix:283` list.

**Sequential** (HA etcd, quorum 2/3; kube-vip still serves `.10` during this, so closet's `--server=https://192.168.5.10:6443` join stays healthy):
```bash
ssh root@192.168.5.36 nixos-rebuild switch && ssh closet.local kubectl wait --for=condition=Ready node/closet --timeout=120s
ssh root@192.168.5.76 nixos-rebuild switch && ssh closet.local kubectl wait --for=condition=Ready node/arch --timeout=120s
ssh root@192.168.5.175 nixos-rebuild switch && ssh closet.local kubectl wait --for=condition=Ready node/nas --timeout=120s
```
Mechanism (verified): each server's CCM starts with `LBEnabled: false` → `deleteAllDaemonsets()` deletes every svclb DS (label `svccontroller.k3s.cattle.io/nodeselector`) — pods cascade. No orphans. **Hazard (finding 22):** between rebuilds, a not-yet-rebuilt CCM can transiently re-create svclb DSes (leader-election resync or any LB svc change). Keep services quiescent during the window.

Verify:
```bash
kubectl --context closet-as-developer get ds -n kube-system | grep svclb        # empty
kubectl --context closet-as-developer get svc -A | grep LoadBalancer           # all .6.x (or .10) only
```
After this, un-converted LB services would stay Pending — none should remain. Optional cleanup: strip `nodePort:` + set `allocateLoadBalancerNodePorts: false` (note: this also kills any remaining `.10:nodeport` paths — the Step 0 grep guarantees none exist).

## 12. Step 8 — k8s API VIP takeover (MetalLB announces .10)

**`argo/workloads/metallb/kubernetes-api-lb.yaml`** — Service + EndpointSlice, no selector (k3s API is a host process); `ready: true` hardening included (finding 18):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-api
  namespace: default
  annotations:
    metallb.io/address-pool: control-plane-vip
    metallb.io/loadBalancerIPs: 192.168.5.10
spec:
  type: LoadBalancer
  ports:
    - port: 6443
      targetPort: 6443
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: kubernetes-api
  namespace: default
  labels:
    kubernetes.io/service-name: kubernetes-api
addressType: IPv4
endpoints:
  - addresses: ["192.168.5.36"]
    conditions:
      ready: true
  - addresses: ["192.168.5.76"]
    conditions:
      ready: true
  - addresses: ["192.168.5.175"]
    conditions:
      ready: true
ports:
  - port: 6443
    protocol: TCP
```
(`autoAssign: false` does NOT block explicit assignment — verified in allocator source; explicit `loadBalancerIPs` + `address-pool` both honored. Do NOT set both `spec.loadBalancerIP` and the annotation.)

Commit, push. Now kube-vip AND MetalLB both announce `.10` → router ECMPs both (kube-vip: leader loopback; MetalLB: kube-proxy DNAT to cp endpoints). Verify:
```bash
kubectl --context closet-as-developer get svc kubernetes-api -n default     # EXTERNAL-IP 192.168.5.10
kubectl --server=https://192.168.5.10:6443 get nodes                        # still 6 nodes
```

## 13. Step 9 — Remove kube-vip (ArgoCD app deletion)

Delete `apps/kube-vip.yaml` + `workloads/kube-vip/` (DaemonSet + RBAC). `app-of-apps` (main.yaml, `path: apps`, prune+selfHeal) prunes them. **No API gap** — MetalLB already announces `.10`; kube-vip withdrawal = ECMP losing a path.
```bash
cd ~/repos/argo && git rm apps/kube-vip.yaml workloads/kube-vip/ && git commit -m "feat(metallb): remove kube-vip, MetalLB now sole BGP speaker" && git push origin main
kubectl --context closet-as-developer get pods -A | grep kube-vip          # empty
kubectl --context closet-as-developer get nodes                            # works via MetalLB .10
```

## 14. Step 10 — Router cleanup + optional BGP hardening

```bash
mikrotik-connect r '/routing bgp connection remove [find name~"kube-vip"]'
mikrotik-connect r '/routing bgp session print where state="established"'   # 6 metallb sessions
```

**Optional — BGP MD5 (finding 2 — secret type is enforced):**
```bash
openssl rand -base64 32 > /tmp/metallb-bgp-pass
kubectl --context closet-as-developer create secret -n metallb-system generic metallb-bgp-secret \
  --type=kubernetes.io/basic-auth --from-file=password=/tmp/metallb-bgp-pass
rm /tmp/metallb-bgp-pass
```
Update `workloads/metallb/bgppeer.yaml` (Secret is untracked → ArgoCD won't prune it):
```yaml
spec:
  myASN: 65000
  peerASN: 65001
  peerAddress: 192.168.5.1
  passwordSecret:
    name: metallb-bgp-secret
    namespace: metallb-system
```
```bash
BGP_PASS=$(kubectl --context closet-as-developer get secret -n metallb-system metallb-bgp-secret -o jsonpath='{.data.password}' | base64 -d)
mikrotik-connect r "/routing bgp connection set [find name~\"metallb\"] tcp-md5-key=\"$BGP_PASS\""
mikrotik-connect r '/routing bgp connection set [find name~"metallb"] local.ttl=255'    # v7: ttl is under local — bare ttl=255 FAILS (finding 8)
```
Expect 5-10s session flap; verify all 6 re-establish (vtysh). Do the router side only AFTER the Secret exists (order matters: Secret → router, else sessions drop without recovery).

## 15. Step 11 — Post-migration docs (complete checklist — finding from docs inventory)

1. `dotfiles/.claude/skills/network-engineer/SKILL.md` — rewrite from LIVE state (not edit-in-place):
   - `:298-323` dst-nat table → `.6.x:port`, re-captured live (current table is missing 7881/50000-60000/3478/5349/7233 and has a phantom 6767 row)
   - `:345-404` UniFi: inform `.6.11`, discovery `.6.12`, `set-inform http://192.168.6.11:8080/inform`, **`https://192.168.5.10:30443` → `https://192.168.6.25:8443`** (finding 3)
   - `:481-500` k3s service table: all `.6.x` EXTERNAL-IPs + `kubernetes-api` `.10`; fix stale `pite (.213)` → `.9`, 5 → 6 nodes (add big), pod CIDR `/24` → `/16`
   - `:515`, `:520-604` BGP section: MetalLB/frr-k8s, 6 peers, ECMP (no leader lease, no loopback VIP); add/remove-node = edit `workloads/metallb/bgppeer.yaml` + router connection; troubleshooting = vtysh on `metallb-frr-k8s` pods, `kubectl get bgpsessionstates`
   - Keep: Source NAT comment; `:502-509` DNS table. (The `.10:30443` UniFi URLs at `:386/392` change to `.6.25:8443` in the UniFi block above.)
2. `dotfiles/.claude/skills/argo-engineer/SKILL.md:274` — "kube-vip VIP at 192.168.5.10" → "MetalLB-announced .10"
3. `argo/docs/adding-a-workload.md:108-134` — add a MetalLB section (LoadBalancer + `metallb.io/loadBalancerIPs: 192.168.6.x` + dst-nat); demote NodePort guidance to legacy
4. `dotfiles/docs/metallb-migration.md` — NEW: why, `.6.0/24` layout, AS topology, dst-nat mapping, recovery
5. This plan's header → DONE + execution date
6. NixOS comment cleanup: `arch:157`, `closet:123,156,192`, `nas:564`, `k3s-server.nix:6,58` — "kube-vip" → "MetalLB"
7. `pite-canary.nix:121` — comment already fixed in Step 6
8. `dotfiles/network-configs/network-diagram.dot` (+ regenerated `.svg`) — stale: pite listed as `.213` (live `.9`), `big` node missing; update node list/IPs
9. No change: `spire.md`, `linkerd-federation.md`, genai-* plans, `cluster.typ`/`cluster.pdf`, headscale `configmap.yaml` extra_records (all tailscale IPs), v1/v2 plans (historical), `context-ts-restart-context.md`, `new-k8s-infra.md`, `nixos/cluster/README.md` (never names kube-vip)

## 16. Verification checklist

1. `ping 192.168.6.1` — subnet reachable
2. `kubectl get pods -n metallb-system` — controller + 6 speakers + 6 frr-k8s + statuscleaner Running
3. vtysh `show bgp summary` — 6 sessions Established to 192.168.5.1
4. `kubectl get svc -A | grep LoadBalancer` — every service `.6.x` (or `.10` kubernetes-api); **no node-IP lists, no `<pending>`**
5. `curl -sk https://192.168.6.10` — traefik; same from WAN via dst-nat
6. `nc -zu 192.168.6.15 9987` — teamspeak
7. `kubectl get ds -n kube-system | grep svclb` — empty
8. `kubectl get nodes` via `--server=https://192.168.5.10:6443` — 6 nodes
9. `curl -s http://192.168.6.23:8080/mimir/ready` from pite — Mimir remoteWrite path OK
10. `curl -sk https://192.168.6.25:8443/status` — UniFi web UI on `.6.25` (baseline today: `https://192.168.5.10:30443/status` → `{"up":true,"server_version":"10.4.57"}`)
11. Kill a speaker pod — service IP re-announced from remaining speakers within ~10s
12. `kubectl get pods -A | grep kube-vip` — empty
13. Step 0 grep re-run: no remaining `192.168.5.10:` consumers (except 6443)

## 17. Rollback

- **Pre-flight:** backups in `/tmp` (Step 0); router export file `backup-before-metallb`.
- **S1 — BGP broken after Step 4:** revert warm-up commit, restore dst-nat, keep klipper (never disabled) — minutes. MetalLB apps can stay or go.
- **S1b — Step 2 additive router changes:** remove the 6 `metallb-*` BGP connections (`remove [find name~"metallb"]`), remove the `192.168.6.1/24` address, remove the 2 static leases (comment "k3s node (static)"). If uncertain, restore from `/tmp/router-backup-before-metallb.rsc`.
- **S2 — kubectl fails after Step 8/9:** if kube-vip still present, revert kubernetes-api commit; if already removed, `git revert` the kube-vip deletion commit, wait for DaemonSet, verify `.10` returns.
- **S3 — servicelb disable breaks services (Step 7):** revert extraFlags commits + rebuild 3 servers; klipper returns; `.6.x` services unaffected (MetalLB still runs).
- **S4 — pite remoteWrite broken (Step 6):** revert URL to `.10:30674` ONLY if kube-vip still alive; otherwise point at closet node IP `.36:30674` temporarily.
- **Nuclear:** restore router backup, re-apply kube-vip ArgoCD app from git history, revert argo commits, delete metallb apps. ~5 min.

**Break-glass:** console to .36 (closet), .175 (nas), .76 (arch).

---

## Appendix A — Evidence ledger (5 research agents, 2026-08-02)

| Agent | Verified | Key sources |
|---|---|---|
| RouterVerifier | RouterOS 7.19.6, bridge name, DHCP leases, BGP connections/sessions, 21 dst-nat rules, firewall filter, VIP route, same-ASN peers, `local.ttl` | live `mikrotik-connect r` prints/exports |
| MetalLBVerifier | BGPAdvertisement REQUIRED; CRD versions (BGPPeer v1beta2 storage); frr-k8s 0.0.25 pod layout + vtysh; `Local` functional in BGP; `passwordSecret` shape + `kubernetes.io/basic-auth` enforcement; autoAssign semantics; annotation prefixes; chart defaults; flannel compat; k3s docs `--disable servicelb` | metallb v0.16.1 chart+source, frr-k8s source, k8s v1.35.6 source, metallb docs |
| K3sTraefikVerifier | `#6773` CLOSED; v1.35.6 skips classed services (`wantsLoadBalancer`); `--disable=servicelb` deletes svclb DSes (`deleteAllDaemonsets`); server-side only; traefik HelmChartConfig exists (`closet-configuration.nix:140-153`, chart 40.1.x `service.annotations`); tmpfiles-at-boot caveat; host extraFlags override | k3s v1.35.6+k3s1 sources, k3s docs, traefik chart v40.1.0, nixpkgs be9e214982e2 |
| ServiceInventory | 16-service live inventory; per-service before→after (file:line); traefik/livekit already Cluster (only coturn Local); stalwart template gap; minecraft absent (bare-metal nas); dead tuwunel duplicate; temporal chart keys | live kubectl dumps, argo repo reads, temporal chart tag source |
| DocsInventory | Complete post-migration doc checklist; SKILL.md stale facts (pite .213→.9, 6 nodes, /16); argo-engineer SKILL.md:274; adding-a-workload.md; pite remoteWrite; cluster.typ/headscale-DNS no-change verdicts | repo greps + full reads |

## Appendix B — Alternative: loadBalancerClass coexistence (not chosen)

k3s v1.35.6 skips services with `spec.loadBalancerClass` (finding 4). Setting `loadBalancerClass: metallb` on converted services + chart value `loadBalancerClass: metallb` would let MetalLB claim them while klipper skips — no `--disable=servicelb` restart needed. **Not chosen as primary** because: (a) the claim semantics of MetalLB with `--lb-class` set (classed-only vs classed+unclassed) are not source-verified — an unverified assumption in the critical path, and (b) the north star is klipper-free. If ever needed, verify first with: deploy with the class, confirm un-converted services stay klipper-owned, and confirm a classed service is claimed by MetalLB.
