# Context: hetzner-stack-bootstrap

> Saved 2026-05-24 from branch `master` by `john@office`

## Goal

Bootstrap 3 Hetzner k3s clusters (ashburn, hillsboro, nuremberg) plus a home-pi as a self-hosted Kubernetes platform with CNPG PostgreSQL, PowerDNS, ArgoCD GitOps, split-IP DDoS firewall, and deSEC DNS management for domain `9s.pics`.

## Current State

**Nodes operational:**
| Node | Primary IP | Raw IP | k3s | CNPG | PowerDNS | Firewall | Tailscale |
|------|-----------|--------|-----|------|----------|----------|-----------|
| home-pi | 192.168.0.154 | N/A | N/A | N/A | active | N/A | 100.64.0.2 |
| ashburn | 5.161.100.206 | 5.161.17.173 | active | healthy | active | active | 100.64.0.1 |
| hillsboro | 5.78.186.134 | 5.78.29.145 | active | healthy | active | active | 100.64.0.3 |
| nuremberg | 178.156.133.181 | 5.161.26.226 | active | healthy | active | active | 100.64.0.4 |

**Ashburn cluster state (operators + apps):**
| Component | Status | Deployed via |
|-----------|--------|-------------|
| cert-manager | 3/3 Running | Systemd bootstrap |
| Traefik | 1/1 Running | Helm (manual, simplified config) |
| Longhorn | 13/13 Running (CSI + engine) | Helm (bootstrap) |
| ExternalDNS | CrashLoopBackOff (148 restarts) | Raw kubectl manifest |
| CNPG | 1/1 Running, cluster healthy | Systemd bootstrap |
| ArgoCD | 7/7 Running | Systemd bootstrap |
| Split-IP firewall | active | NixOS module |

**ArgoCD sync status** (stalled):
- Wave -2 (namespaces): Synced, Healthy
- Wave 0 (cert-manager): Synced, Progressing
- Waves 1-8: Not created — root-app OutOfSync, `argocd-cm.yaml` blocks child Application creation

**Git state:**
- **dotfiles**: branch `master`, clean working tree, 4 stashes
- **2143-59s**: branch `master`, clean working tree, HEAD at revert commit `8db90ac` (restored pre-Helm-migration manifests)

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Operators via systemd bootstrap, config CRDs via ArgoCD | ArgoCD Helm multi-source approach had chart compatibility issues (Traefik v34/35 template errors, ExternalDNS TSIG args not passed by Helm chart). Bootstrap is reliable; ArgoCD manages config layer. |
| 2 | Flannel CNI, not Cilium | Cilium 1.19 broken on NixOS kernel 6.18. Flannel works immediately. |
| 3 | CNPG 1.25 uses `bootstrap.initdb` not `spec.managed` | `spec.managed` introduced in CNPG 1.26+. Current operator (1.25.1) uses initdb for database creation. |
| 4 | Home-pi pdns/postgres-schema not auto-started | Both depend on k3s-ashburn PostgreSQL being reachable. Overrode `wantedBy` to prevent `nixos-rebuild switch` failures when VMs are down. |
| 5 | `pdnsutil` needs `--config-dir=/run/pdns` | Runtime config with decrypted secrets is at `/run/pdns/pdns.conf`. The default config at `/etc/pdns/pdns.conf` has template placeholders. |
| 6 | `postgres-pdns-password` must be owned by `pdns` user | PowerDNS runs as `pdns` user. Agenix secret was owned by `root` — fixed in code. |
| 7 | Each node has independent CNPG PostgreSQL (instances: 1) | ArgoCD syncs the same Cluster CR to all 3 clusters, creating 3 separate instances. Bootstrap design — multi-primary replication deferred. |
| 8 | Split-IP firewall resolves raw IP from DNS at build time | Detected interface is `enp1s0` (Hetzner Cloud predictable names), not `eth0`. Raw IP passed from flake config per-node. |
| 9 | Provision script uses `john@office` SSH key | `john@arch` was the only key in Hetzner. Added office key via `hcloud ssh-key create`. |
| 10 | deSEC DNS records for raw IPs kept private | `ash-raw.9s.pics` etc. are infrastructure plumbing, not user-facing. User-facing names (`ts.9s.pics`) published when services go live. |

## Ruled Out

| Approach | Why rejected |
|----------|-------------|
| ArgoCD Helm multi-source Applications | Helm chart template errors (Traefik v34/35, ExternalDNS TSIG args). Rolled back — manifests reverted to directory-type. |
| Cilium CNI (via ArgoCD wave-0) | Broken on NixOS kernel 6.18. Switched to k3s default Flannel. Removed `cilium.yaml` from wave-0, removed `base/cilium/`, removed per-cluster cilium values. |
| `spec.managed` in CNPG Cluster CR | Not available in CNPG 1.25.1. Replaced with `bootstrap.initdb`. |
| Longhorn `storageClass` in CNPG Cluster CR | Longhorn not installed when CNPG creates cluster. Using default `local-path` storage. |
| Galera MariaDB for PowerDNS backend | Replaced by CNPG PostgreSQL. Galera firewall ports (4567, 4568) removed from config. |
| Duplicate secret injection (ArgoCD Job) | `k8s-secrets-bootstrap` systemd oneshot handles it. Removed `secret-injector-job.yaml`. |
| `inetutils`/`gawk` in firewall PATH | Triggered full GCC bootstrap from source (700+ derivations). Switched to `iptables` + `iproute2` only. |
| Hetzner `cpx32` in EU datacenters | NixOS fails to boot on cpx32 in nbg1/fsn1. Nuremberg provisioned in ashburn location. |
| cert-manager operator via ArgoCD Helm | The existing systemd bootstrap install matches; ArgoCD detects it as synced. Keeping systemd for now. |

## Open Questions

- [ ] How to fix ExternalDNS CrashLoopBackOff (148 restarts)? Logs show `is not supported TSIG algorithm` — TSIG args may have trailing whitespace or wrong format. Need to check raw deployment args.
- [ ] Why is ArgoCD root-app OutOfSync? `argocd-cm.yaml` present in `argocd/` path — was removed then re-added in revert. Removing it from root's scope may fix child app creation.
- [ ] Should k3s-nuremberg stay in ashburn location? cpx32 boot bug blocks EU datacenters. Need to test when Hetzner updates hypervisor/KVM.
- [ ] How to handle CNPG pdns user password on rebuild? `bootstrap.initdb` generates random password. `hetzner-postgres-schema` needs a password reset step.
- [ ] ArgoCD sync-wave ordering: cert-manager ClusterIssuer needs DNS01 (PowerDNS) before becoming Healthy. This blocks wave progression? Or does ArgoCD ignore health for wave ordering?
- [ ] Should we move ExternalDNS back into the ArgoCD repo as a proper manifest? Currently deployed via raw kubectl on ashburn only.
- [ ] Traefik is deployed without `hostPort`/`hostNetwork` (simplified for initial bootstrap). Should restore for split-IP DDoS when services go live.

## Recent Artifacts

| Path | Description | Last Modified |
|------|-------------|---------------|
| `nixos/hetzner/modules/hetzner-k3s-common.nix` | Bootstrap: ArgoCD, CNPG, Helm operators, secrets | May 24 04:23 |
| `nixos/hetzner/modules/hetzner-split-ip-firewall.nix` | Per-IP iptables DDoS firewall | May 24 02:42 |
| `nixos/hetzner/flake.nix` | Node configs with rawIP per-node | May 24 02:40 |
| `nixos/hetzner/modules/hetzner-k3s-server.nix` | Server imports (incl. split-ip-firewall) | May 24 02:23 |
| `nixos/hetzner/scripts/provision.sh` | VM create + nixos-anywhere + floating IP | May 24 02:22 |
| `nixos/hetzner/scripts/desec-dns.sh` | deSEC DNS management (PUT→POST fallback) | May 24 01:27 |
| `nixos/hetzner/README.md` | Updated docs: deSEC, CNPG, known issues | May 24 01:26 |
| `repos/2143-59s/argocd/argocd-cm.yaml` | ArgoCD ConfigMap (restored in revert) | May 24 04:21 |
| `repos/2143-59s/argocd/wave-1/traefik.yaml` | Traefik Application (directory-type, reverted) | May 24 04:21 |
| `repos/2143-59s/argocd/wave-1/longhorn.yaml` | Longhorn Application (directory-type, reverted) | May 24 04:21 |
| `repos/2143-59s/base/cloudnativepg/cluster.yaml` | CNPG Cluster CR (bootstrap.initdb) | May 24 02:00 |
| `repos/2143-59s/base/cloudnativepg/nodeport-service.yaml` | NodePort 30432 Service for CNPG | May 24 01:50 |

## Constraints

- All 3 nodes must be on Hetzner (no multi-provider)
- Nuremberg stuck in ashburn location due to cpx32 NixOS boot bug
- Home-pi must be provisioned first (Headscale required for tailnet)
- Headscale port forward 6767 → home-pi must be active on home router
- All secrets via agenix, no plaintext credentials in repos
- `nixos-rebuild switch` must succeed without failed units (exit code 4 blocks switch)
- Remote builders (`arch.local`, `nas.local`) may be down — use `NIX_CONFIG="builders ="` to bypass
- deSEC token encrypted at `secrets/hetzner/desec-token.age`
- HCLOUD_TOKEN decrypted from `secrets/hetzner/hcloud-token.age` at runtime

## Next Steps

1. [ ] **PICK UP HERE**: Fix ExternalDNS CrashLoopBackOff on ashburn — check `kubectl logs -n external-dns deploy/external-dns` and `kubectl get deploy external-dns -n external-dns -o yaml | grep -A5 tsig` for the exact TSIG config being passed
2. [ ] Fix ArgoCD root-app sync — either remove `argocd-cm.yaml` from `argocd/` directory permanently, or add a sync window/ignore annotation. Once root syncs, child Applications (waves 1-8) will be created and can sync independently
3. [ ] Deploy Traefik and ExternalDNS on hillsboro and nuremberg (currently only on ashburn)
4. [ ] Rebuild hillsboro and nuremberg with updated bootstrap (helm PATH, operator installs, split-IP firewall)
5. [ ] Install remaining operators: k8gb, Istio, CrowdSec, SeaweedFS (via systemd bootstrap or Helm)
6. [ ] Deploy applications via ArgoCD waves 5-8: MongoDB, Temporal, apps, monitoring, backups
7. [ ] CNPG password reset automation: add `ALTER USER pdns PASSWORD` step to `hetzner-postgres-schema` systemd oneshot
8. [ ] Test cert-manager DNS01 challenge end-to-end (ClusterIssuer → PowerDNS via RFC2136)
9. [ ] Create deSEC NS glue records delegating `9s.pics` to ns1/ns2/ns3
10. [ ] Port forward 6767 → home-pi must remain active (currently confirmed permanent)

## Verification

- All 3 nodes: `kubectl get nodes` shows Ready, `tailscale status` shows all 4 peers
- All 3 nodes: `systemctl is-active k3s pdns tailscaled split-ip-firewall` returns active
- Ashburn: `kubectl get pods -n external-dns` shows 1/1 Running (not CrashLoopBackOff)
- ArgoCD: `kubectl get apps -n argocd` shows all waves present and Synced
- DNS: `dig @5.161.100.206 NS 9s.pics` returns ns1/ns2/ns3 records
- CNPG: `kubectl get cluster temporal-postgres` shows healthy on all 3 nodes
- Firewall: `iptables -L PROTECTED_IN -n` and `iptables -L RAW_IN -n` show populated chains
