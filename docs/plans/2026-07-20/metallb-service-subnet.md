# MetalLB Deployment — BGP mode, replace kube-vip

**WARNING: Service migration with real downtime.** Plan for a 2-hour window. Services blip individually during conversion. k8s API has a 5-15 second gap during kube-vip disconnection.

**SECURITY WARNING:** This plan includes commands with sensitive values (BGP passwords, secrets). Do NOT paste actual secrets into this file, git commits, or session logs. Use secret references (`$VAR`, file paths, k8s Secret names) only. The BGP password is generated locally and applied via kubectl—never committed to git.

## Context

### North Star

**Clean up the cluster's networking into one coherene, BGP-native system.** Today the cluster runs two overlapping network layers: kube-vip (announces the k8s API VIP `.10` via BGP) and k8s built-in LoadBalancer (assigns service IPs via node addresses). NodePort-based dst-nat rules duct-tape services to the outside world by routing through `.10:nodeport` — fragile, confusing, and full of indirection.

**End state:** MetalLB is the sole BGP speaker on all 5 nodes. It announces both the k8s API VIP (`192.168.5.10`) and service IPs (`192.168.6.x`). Services get dedicated, stable IPs from a clean `.6.0/24` subnet. dst-nat rules point to direct service IPs instead of VIP:nodeport hops. One BGP provider. One service subnet. No kube-vip. No NodePort routing gymnastics.

**Why BGP instead of Layer2:** The user explicitly chose BGP over ARP-based Layer2. "We need one BGP provider. MetalLB seems right." BGP provides ECMP distribution across all 5 nodes, immediate failover (not ~10s ARP), and aligns with the planned "BGP everywhere on switches" future. kube-vip is removed entirely — MetalLB handles both control-plane and workload announcement.

**Recoverability:** All 3 control-plane nodes have physical/console access. Pre-flight backups of kube-vip manifests, services, dst-nat, and BGP config are taken. Each step has explicit rollback commands. Nuclear rollback restores the original state in ~5 minutes.

---


**Pre-requisite:** Open BGP port 179 on all k3s nodes. Edit the shared modules:

In `dotfiles/nixos/modules/k3s-server.nix`, add `179 # BGP (MetalLB)` to `networking.firewall.allowedTCPPorts` (after line 83 `10250`).

In `dotfiles/nixos/modules/k3s-agent.nix`, add after the `gracefulNodeShutdown` block:
```nix
networking.firewall.allowedTCPPorts = [
  179 # BGP (MetalLB)
];
```

Then run `nixos-rebuild switch` on office (192.168.5.209) and pite (192.168.5.9) — the 3 control-plane nodes already have 179 open for kube-vip and will rebuild later.

**Cleanup (optional):** After control-plane nodes rebuild (step 0 or post-migration), remove the now-redundant `179 # BGP for kube-vip` entries from `dotfiles/nixos/arch-configuration.nix`, `dotfiles/nixos/closet-configuration.nix`, and `dotfiles/nixos/nas-configuration.nix` — the module now provides it.
**All kubectl commands assume:** `KUBECONFIG=~/.kube/config kubectl --context closet-as-developer`

## Approach

### Step 1 — Add service subnet to bridge

```bash
mikrotik-connect r '/ip address add address=192.168.6.1/24 interface=bridge'
```

Verify: `ping -c 1 192.168.6.1`

### Step 2 — ArgoCD apps

Write `apps/metallb.yaml` (Helm chart app):

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
    targetRevision: 0.14.9
    helm:
      releaseName: metallb
      values: |
        speaker:
          tolerateMaster: true
          frr:
            enabled: true
          frrk8s:
            enabled: false
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

`speaker.frr.enabled: true` + `speaker.frrk8s.enabled: false` — FRR sidecar mode for BGP. Version 0.14.9 may default `frrk8s` to enabled; we force the sidecar mode for direct `vtysh` access (used in Step 4 verification). `speaker.tolerateMaster: true` lets the DaemonSet run on control-plane nodes.

Write `apps/metallb-config.yaml` (workload manifests):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb-config
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/2143-Labs/argo.git
    targetRevision: HEAD
    path: workloads/metallb
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

Apply both apps (ArgoCD manages them afterward):

```bash
kubectl apply -f ~/repos/argo/apps/metallb.yaml
kubectl apply -f ~/repos/argo/apps/metallb-config.yaml
```

Verify: `kubectl get pods -n metallb-system` shows controller + speaker pods Running (5 speakers, one per node).

### Step 3 — CRDs: IP pool + BGP peer

Write `workloads/metallb/ipaddresspool.yaml`:

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

`autoAssign: false` on the VIP pool prevents MetalLB from giving `.10` to random services. Only the explicit k8s API service (below) gets it.

Write `workloads/metallb/bgppeer.yaml`:

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

Write `workloads/metallb/kubernetes-api-lb.yaml` — Service + EndpointSlice for k8s API VIP. No pod selector (k3s API runs from the binary, not labeled pods):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-api
  namespace: default
  annotations:
    metallb.universe.tf/address-pool: control-plane-vip
    metallb.universe.tf/loadBalancerIPs: 192.168.5.10
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
  - addresses: ["192.168.5.76"]
  - addresses: ["192.168.5.175"]
ports:
  - port: 6443
    protocol: TCP
```

Commit + push to `~/repos/argo` — ArgoCD syncs the `metallb-config` app. Verify:

```bash
kubectl get ipaddresspool,bgppeer -n metallb-system
kubectl get svc kubernetes-api -n default  # EXTERNAL-IP should be 192.168.5.10
```

### Step 3.5 — Security: BGP authentication + VIP protection

**BGP MD5 password** — prevents BGP session hijacking from unauthorized speakers on the LAN.

Create `workloads/metallb/bgp-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: metallb-bgp-secret
  namespace: metallb-system
type: Opaque
stringData:
  password: <GENERATE_32_CHAR_RANDOM>  # openssl rand -base64 32
```

**DO NOT commit this file to git.** Generate the password locally, `kubectl apply -f` it directly, then delete the file. The Secret stays in the cluster only.

Update `workloads/metallb/bgppeer.yaml`:

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
  password: metallb-bgp-secret  # references Secret.metadata.name
  ebgpMultiHop: false
```

MetalLB uses the Secret's `password` field for MD5 auth. Commit the updated bgppeer.yaml (without the Secret itself).

On MikroTik, add the password to each BGP connection:

```bash
BGP_PASS=$(kubectl get secret -n metallb-system metallb-bgp-secret -o jsonpath='{.data.password}' | base64 -d)
mikrotik-connect r "/routing/bgp/connection set [find name~\"metallb\"] tcp-md5-key=\"$BGP_PASS\""
```

Verify sessions re-establish: `mikrotik-connect r '/routing/bgp/session print where state="established"'`

**GTSM (TTL security)** — requires BGP packets have TTL=255 (single-hop only), prevents off-network injection.

On MikroTik:
```bash
mikrotik-connect r '/routing/bgp/connection set [find name~"metallb"] ttl=255'
```

In MetalLB, FRR automatically enforces single-hop for eBGP (no config needed).

**VIP theft prevention** — block services from requesting `192.168.5.10` except the k8s API service.

Install Kyverno (if not already present):

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.12.0/install.yaml
```

Create `workloads/metallb/kyverno-policy-vip.yaml`:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-control-plane-vip
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: block-vip-annotation
      match:
        any:
        - resources:
            kinds:
              - Service
      exclude:
        any:
        - resources:
            namespaces:
              - default
            names:
              - kubernetes-api
      validate:
        message: "Only the kubernetes-api service in default namespace can use 192.168.5.10"
        deny:
          conditions:
            any:
              - key: "{{ request.object.metadata.annotations.\"metallb.universe.tf/loadBalancerIPs\" || '' }}"
                operator: Equals
                value: "192.168.5.10"
              - key: "{{ request.object.metadata.annotations.\"metallb.universe.tf/address-pool\" || '' }}"
                operator: Equals
                value: "control-plane-vip"
```

Apply: `kubectl apply -f workloads/metallb/kyverno-policy-vip.yaml`

Test (should fail):
```bash
kubectl run test-vip-theft --image=nginx --restart=Never --overrides='{"spec":{"type":"LoadBalancer","metadata":{"annotations":{"metallb.universe.tf/loadBalancerIPs":"192.168.5.10"}}}}'
```

Expected: `Error from server: admission webhook denied the request`.

### Step 4 — Verify MetalLB BGP sessions

MetalLB speaker pods establish BGP with the router. **Both MetalLB and kube-vip coexist at this point** — router sees 3 kube-vip + 5 MetalLB peers. `.10` is announced via ECMP (both providers).

```bash
# All 5 speakers Running?
kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker

# BGP sessions Established?
kubectl exec -n metallb-system deploy/metallb-controller -c controller -- cat /dev/null 2>/dev/null || true
kubectl exec -n metallb-system <any-speaker-pod> -c frr -- vtysh -c "show bgp summary"
```

Look for `192.168.5.1` in state `Established`.

**Test kubectl through MetalLB's .10 announcement:**

```bash
kubectl --server=https://192.168.5.10:6443 get nodes
```

Must return 5 nodes. If this fails, MetalLB isn't routing `.10` — fix before proceeding. If it works, both providers are healthy and you can safely remove kube-vip.

### Step 5 — Move kube-vip into NixOS and disable it

kube-vip was set up manually outside NixOS (static pod manifest at `/etc/kubernetes/manifests/kube-vip.yaml`). To disable it declaratively, first bring it under NixOS management, then remove it.

**Phase A — Add kube-vip to NixOS (codifies current state):**

In the k3s-server module (`dotfiles/nixos/modules/k3s-server.nix`), add after the existing `gracefulNodeShutdown` block:

```nix
# kube-vip static pod — manually placed, now managed by NixOS.
# Disabled once MetalLB takes over BGP (see metallb-migration plan).
services.k3s.manifests.kube-vip = lib.mkIf (config.services.k3s.role == "server") {
  enable = lib.mkDefault true;
  content = builtins.readFile ../manifests/kube-vip.yaml;
};
```

Create `dotfiles/nixos/manifests/kube-vip.yaml` from the live manifest (backed up in Step 0). Commit both, push, then rebuild all 3 control-plane nodes:

```bash
ssh root@192.168.5.36 nixos-rebuild switch  # closet
ssh root@192.168.5.76 nixos-rebuild switch  # arch
ssh root@192.168.5.175 nixos-rebuild switch # nas
```

After rebuild, verify kube-vip pods are still running — NixOS now manages them.

**Phase B — Disable kube-vip (after Step 4 confirms MetalLB BGP works):**

In the same block in `dotfiles/nixos/modules/k3s-server.nix`, change `enable`:

```nix
services.k3s.manifests.kube-vip = lib.mkIf (config.services.k3s.role == "server") {
  enable = false;
  content = builtins.readFile ../manifests/kube-vip.yaml;
};
```

Commit, push, rebuild all 3 control-plane nodes. NixOS removes the manifest; kubelet stops the static pods.

Verify:

```bash
kubectl get pods -A | grep kube-vip  # should return nothing
kubectl get nodes  # kubectl still works via MetalLB's .10 announcement
```

If kubectl hangs, revert `enable` to `true`, rebuild, investigate MetalLB.

### Step 6 — Update router BGP peers

```bash
mikrotik-connect r '/routing/bgp/connection remove [find name~"kube-vip"]'
mikrotik-connect r '/routing/bgp/connection add name="metallb-arch" remote.address=192.168.5.76 remote.as=65000 local.role=ebgp as=65001'
mikrotik-connect r '/routing/bgp/connection add name="metallb-closet" remote.address=192.168.5.36 remote.as=65000 local.role=ebgp as=65001'
mikrotik-connect r '/routing/bgp/connection add name="metallb-nas" remote.address=192.168.5.175 remote.as=65000 local.role=ebgp as=65001'
mikrotik-connect r '/routing/bgp/connection add name="metallb-office" remote.address=192.168.5.209 remote.as=65000 local.role=ebgp as=65001'
mikrotik-connect r '/routing/bgp/connection add name="metallb-pite" remote.address=192.168.5.9 remote.as=65000 local.role=ebgp as=65001'
```

Verify: `mikrotik-connect r '/routing/bgp/session print where state="established"'` shows 5 sessions.

### Step 7 — Convert services to LoadBalancer

For each service, edit its YAML in `~/repos/argo/workloads/`:
- Change `type: NodePort` → `type: LoadBalancer` (or add annotation to existing LB services)
- Add annotation: `metallb.universe.tf/loadBalancerIPs: 192.168.6.<N>`
- Remove `nodePort:` from each port
- Keep the same selector and port definitions

| IP | Service | Namespace | Current |
|----|---------|-----------|---------|
| .6.10 | traefik | kube-system | LoadBalancer |
| .6.11 | unifi-inform | default | LoadBalancer |
| .6.12 | unifi-discovery | default | LoadBalancer |
| .6.13 | stalwart-stalwart | stalwart | LoadBalancer (25,587,993) |
| .6.15 | ts-voice | default | NodePort (9987/UDP) |
| .6.16 | ts-files | default | NodePort (30033/TCP) |
| .6.17 | openrct2-game | default | NodePort (11753/TCP) |
| .6.18 | headscale-stun | default | NodePort (3478/UDP) |
| .6.19 | mosquitto | default | NodePort (1883/TCP) |
| .6.20 | temporal-frontend | default | NodePort (7233,7243) |
| .6.21 | coturn | matrix | LoadBalancer (3478,5349) |
| .6.22 | livekit-server-rtc | matrix | LoadBalancer (7881,50000) |
| .6.30 | minecraft-game | default | NodePort → new LB (25565,32565) |

Example (ts-voice):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ts-voice
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.6.15
spec:
  type: LoadBalancer
  selector:
    app: teamspeak
  ports:
    - port: 9987
      targetPort: 9987
      protocol: UDP
```

**Minecraft** needs both ports on the same IP. Create or update the service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: minecraft-game
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.6.30
spec:
  type: LoadBalancer
  selector:
    app: minecraft-game
  ports:
    - port: 25565
      targetPort: 25565
      protocol: TCP
      name: game
    - port: 32565
      targetPort: 25565
      protocol: TCP
      name: game-alt
```

**Temporal-frontend** has two ports (7233 + 7243). Do NOT remove the headless service `temporal-frontend-headless`.

### Step 8 — Migration order by risk

Convert services one at a time in this order. For each: push YAML → wait for Argo sync → verify `.6.x` IP responds → update dst-nat → verify from WAN. Do NOT move to the next service until the current one works.

| Phase | Services | Impact |
|-------|----------|--------|
| 1. Warm-up | unifi-inform, unifi-discovery, mosquitto, openrct2 | APs re-discover in minutes |
| 2. Medium | ts-voice, ts-files, headscale-stun | Brief outage acceptable |
| 3. High | stalwart, coturn, livekit-rtc, minecraft, temporal-frontend | Mail/Matrix/Minecraft |
| 4. Critical | **traefik (80/443)** | All HTTP/HTTPS stops until dst-nat updated |

### Step 9 — Update dst-nat rules

For each converted service, after verifying the `.6.x` IP responds: update the corresponding dst-nat rule. Use `protocol + port` filters to avoid collisions (e.g., rules 15+16 share port 3478 but differ by protocol).

| Rule | Proto | Port | Old target | New target | Service |
|------|-------|------|-----------|-----------|---------|
| 0 | TCP | 18080 | .76:18080 | .76:18080 | Monero (leave) |
| 1 | UDP | 9987 | .10:30087 | .6.15:9987 | ts-voice |
| 2 | TCP | 30033 | .10:30034 | .6.16:30033 | ts-files |
| 3 | TCP | 80 | .10:80 | .6.10:80 | traefik HTTP |
| 4 | TCP | 443 | .10:443 | .6.10:443 | traefik HTTPS |
| 5 | TCP | 5432 | .35:5432 | .35:5432 | Postgres (leave) |
| 6 | UDP | 30478 | .10:30478 | .6.18:3478 | headscale-stun |
| 7 | TCP | 25565 | .175:32565 | .6.30:25565 | minecraft |
| 8 | TCP | 32565 | .175:32565 | .6.30:32565 | minecraft alt |
| 9 | TCP | 11753 | .10:31753 | .6.17:11753 | openrct2 |
| 10 | TCP | 25 | .10:25 | .6.13:25 | stalwart SMTP |
| 11 | TCP | 587 | .10:587 | .6.13:587 | stalwart submission |
| 12 | TCP | 993 | .10:993 | .6.13:993 | stalwart IMAPS |
| 13 | TCP | 7881 | .10:7881 | .6.22:7881 | livekit WebRTC |
| 14 | UDP | 50000-60000 | .10:50000-60000 | .6.22:50000-60000 | livekit media |
| 15 | TCP | 3478 | .10:3478 | .6.21:3478 | coturn TURN TCP |
| 16 | UDP | 3478 | .10:3478 | .6.21:3478 | coturn TURN UDP |
| 17 | TCP | 5349 | .10:5349 | .6.21:5349 | coturn TURN TLS |
| 18 | TCP | 7233 | .10:7233 | .6.20:7233 | temporal gRPC |
| 19 | TCP | 4143 | .36:4143 | .36:4143 | Linkerd (leave) |

Example commands:

```bash
# ts-voice
mikrotik-connect r '/ip firewall nat set [find dst-port=9987 protocol=udp] to-addresses=192.168.6.15 to-ports=9987'
# coturn — protocol filter required (port 3478 used by both TCP and UDP)
mikrotik-connect r '/ip firewall nat set [find dst-port=3478 protocol=tcp] to-addresses=192.168.6.21 to-ports=3478'
mikrotik-connect r '/ip firewall nat set [find dst-port=3478 protocol=udp] to-addresses=192.168.6.21 to-ports=3478'
# traefik
mikrotik-connect r '/ip firewall nat set [find dst-port=80 protocol=tcp] to-addresses=192.168.6.10 to-ports=80'
mikrotik-connect r '/ip firewall nat set [find dst-port=443 protocol=tcp] to-addresses=192.168.6.10 to-ports=443'
```

Verify each from WAN (cellular, Tailscale exit node) immediately after. Revert with: `set [find dst-port=N protocol=P] to-addresses=192.168.5.10 to-ports=OLD_PORT`.

### Step 10 — Commit and push

Commit the MetalLB config now (Steps 2-3 were `kubectl apply`'d, but git needs them for ArgoCD ownership). Service conversions are committed individually as each converts — do NOT batch them all at the end.

```bash
cd ~/repos/argo
git add main.yaml apps/metallb.yaml apps/metallb-config.yaml workloads/metallb/
git commit -m "feat(metallb): BGP mode on 192.168.6.0/24, replace kube-vip"
git push origin main
```

For each service in Steps 7-8 (per-service commits during conversion):
```bash
cd ~/repos/argo
git add workloads/<service-path>/
git commit -m "feat(metallb): convert <service> to LB at 192.168.6.<N>"
git push origin main
```


## Post-migration docs

After all services are converted and verified, update these files to reflect the new state.
Use the `network-engineer` skill's snapshot commands to re-capture live state:


1. **`dotfiles/.claude/skills/network-engineer/SKILL.md`** — replace the BGP section (kube-vip → MetalLB), update dst-nat table (`.10:nodeport` → `.6.x:serviceport`), update k3s service table.
2. **`dotfiles/.claude/skills/network-engineer/SKILL.md`** — Update the UniFi section's inform note (LB IPs may change to `.6.11/.6.12`).
3. **`dotfiles/docs/`** — Write a new `metallb-migration.md` capturing: why kube-vip was replaced, the `.6.0/24` subnet layout, BGP AS topology, dst-nat rule mapping, recovery procedures.
## Verification

1. `ping 192.168.6.1` — subnet reachable
2. `kubectl get pods -n metallb-system` — controller + 5 speakers Running
3. `kubectl get svc -A | grep LoadBalancer | grep '192.168.6'` — all services have .6.x IPs
4. `curl -sk https://192.168.6.10` — traefik responds
5. `nc -zu 192.168.6.15 9987` — teamspeak reachable
6. From WAN: `curl -sk https://<public-ip>` returns same as step 4
7. Delete a speaker pod, verify service IP re-claims on another node within 10 seconds

## Assumptions & contingencies

1. **MikroTik authentication:** `mikrotik-connect` uses SSH key-based auth (no passwords). The SSH key is in `~/.ssh/` and the router's host key is already in `known_hosts`. If `mikrotik-connect` prompts for a password, abort—this means SSH keys aren't configured. Set up key-based auth first: `ssh-copy-id admin@192.168.5.1`.

2. **BGP MD5 password storage:** The password is generated once with `openssl rand -base64 32`, applied to the k8s Secret and MikroTik router, then the plaintext file is deleted. If you lose the password, retrieve it from the cluster: `kubectl get secret -n metallb-system metallb-bgp-secret -o jsonpath='{.data.password}' | base64 -d`. Rotating the password requires updating both the Secret and all 5 MikroTik BGP connections simultaneously—expect 5-10s BGP session downtime during rotation.

3. **Kyverno installation:** If Kyverno is already installed (check with `kubectl get pods -n kyverno`), skip the `kubectl create -f https://...` step. If a different policy engine (OPA Gatekeeper, etc.) is present, translate the VIP policy to that engine's format instead—the deny logic is: block services with `metallb.universe.tf/loadBalancerIPs: 192.168.5.10` OR `metallb.universe.tf/address-pool: control-plane-vip` unless `metadata.name == "kubernetes-api"` AND `metadata.namespace == "default"`.

4. **Service IP order:** The table in Step 7 assigns IPs out of numeric order (`.30` for minecraft, `.20` for temporal). This is intentional—grouped by risk tier, not IP. If you prefer sequential assignment, renumber before committing. Once a service has an IP, changing it requires dst-nat rule updates and WAN verification again.

5. **Argo repo branch protection:** The plan commits to `main` branch of `https://github.com/2143-Labs/argo.git`. If branch protection requires PR review, either temporarily disable it for the migration window, or create a feature branch (`git checkout -b metallb-migration`), commit there, PR after testing, then merge. If you use a feature branch, ArgoCD won't auto-sync—you'll need to manually sync the `metallb-config` app after each commit during testing.

6. **EndpointSlice for k8s API:** k3s doesn't label API server pods, so the Service can't use a selector. The manual EndpointSlice points to the 3 control-plane node IPs (.36, .76, .175) on port 6443. If a control-plane node is replaced (different IP), update the EndpointSlice. If MetalLB refuses to assign `.10` because it can't find healthy endpoints, check: `kubectl get endpointslice kubernetes-api -n default -o yaml` and verify the IPs are correct and reachable on port 6443.

7. **Traefik conversion timing:** Traefik (80/443) is converted LAST (Step 8, phase 4). All HTTP/HTTPS traffic stops until its dst-nat rules update. Schedule the migration during a low-traffic window. If you must keep HTTP/HTTPS up continuously, convert traefik first (before other services) so the bulk of the migration happens while HTTP/HTTPS is stable, then do one final traefik dst-nat update at the end. This inverts the risk order—your choice.

8. **New home nodes:** Adding another node on 192.168.5.0/24 (e.g., a new Pi) automatically gets a MetalLB speaker (DaemonSet via k3s-agent module). Add a BGP peer on MikroTik: `mikrotik-connect r '/routing/bgp/connection add name="metallb-<name>" remote.address=192.168.5.<N> remote.as=65000 local.role=ebgp as=65001'`. Services can migrate to the new node with zero config changes.

9. **Cross-site nodes (DigitalOcean, Hetzner):** MetalLB BGP is site-local — speakers on remote networks cannot peer with 192.168.5.1. Service IPs (192.168.6.x) are not routable from the public internet. Remote k3s nodes need their own load balancer per site (native cloud LB, Cloudflare Tunnel, or external-dns). Site-to-site WireGuard can make `.6.x` IPs reachable from remote pods (for service discovery), but BGP route distribution across sites is not supported. This migration neither blocks nor enables cross-site nodes — they're a separate problem.

## Recovery & Rollback

### Pre-flight backups (run before Step 1)

```bash
# kube-vip manifests (used as source for dotfiles/nixos/manifests/kube-vip.yaml in Step 5 Phase A)
ssh root@192.168.5.76 'cat /etc/kubernetes/manifests/kube-vip.yaml' > /tmp/kube-vip-arch.yaml
ssh root@192.168.5.36 'cat /etc/kubernetes/manifests/kube-vip.yaml' > /tmp/kube-vip-closet.yaml
ssh root@192.168.5.175 'cat /etc/kubernetes/manifests/kube-vip.yaml' > /tmp/kube-vip-nas.yaml

# All services
KUBECONFIG=~/.kube/config kubectl --context closet-as-developer get svc -A -o yaml > /tmp/all-services-before.yaml

# dst-nat + BGP
mikrotik-connect r '/ip firewall nat export file=backup-before-metallb'
mikrotik-connect r '/routing/bgp/connection print detail' > /tmp/bgp-peers-before.txt
```

### Scenario 1: kubectl stops after Step 5 (kube-vip disabled)

Revert kube-vip to `enable = true` in `dotfiles/nixos/modules/k3s-server.nix`, commit, push, then rebuild control-plane nodes:

```bash
ssh root@192.168.5.36 nixos-rebuild switch
ssh root@192.168.5.76 nixos-rebuild switch
ssh root@192.168.5.175 nixos-rebuild switch
```

If SSH is unavailable (entire cluster down), use console access. Once kube-vip is back and kubectl works, investigate MetalLB failure:

### Scenario 2: ArgoCD sync failures

```bash
kubectl get applications -n argocd metallb -o yaml
kubectl get applications -n argocd metallb-config -o yaml
# Fix YAML, delete and reapply or let Argo self-heal
```

### Scenario 3: Service conversion breaks external access

Revert the dst-nat rule first (immediate fix):

```bash
mikrotik-connect r '/ip firewall nat set [find dst-port=443 protocol=tcp] to-addresses=192.168.5.10 to-ports=443'
```

If that doesn't work, revert service YAML via git, push, let Argo sync back to NodePort.

### Scenario 4: Full disaster — nuclear rollback

Requires console/physical access to control-plane nodes.

1. Revert kube-vip to `enable = true` in `dotfiles/nixos/modules/k3s-server.nix`, commit, push, then rebuild all 3 control-plane nodes (Scenario 1 rebuild commands)
2. `kubectl apply -f /tmp/all-services-before.yaml`
3. `mikrotik-connect r '/import file-name=backup-before-metallb.rsc'`
4. `mikrotik-connect r '/routing/bgp/connection remove [find name~"metallb"]'`
5. Restore kube-vip BGP peers:
   ```bash
   mikrotik-connect r '/routing/bgp/connection add name="kube-vip" remote.address=192.168.5.76 remote.as=65000 local.role=ebgp as=65001'
   mikrotik-connect r '/routing/bgp/connection add name="kube-vip-closet" remote.address=192.168.5.36 remote.as=65000 local.role=ebgp as=65001'
   mikrotik-connect r '/routing/bgp/connection add name="kube-vip-nas" remote.address=192.168.5.175 remote.as=65000 local.role=ebgp as=65001'
   ```
6. `kubectl delete application metallb -n argocd && kubectl delete application metallb-config -n argocd && kubectl delete namespace metallb-system`
7. `mikrotik-connect r '/ip address remove [find address="192.168.6.1/24"]'`

**Break-glass access:** Console access to .36 (closet), .175 (nas), .76 (arch).
