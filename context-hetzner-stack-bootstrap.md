# Context: hetzner-stack-bootstrap

> Saved 2026-05-24, updated 2026-05-25 from branch `master` by `john@office`

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

**All 3 clusters operational (2026-05-25):**
| Component | Ashburn | Hillsboro | Nuremberg |
|-----------|---------|-----------|-----------|
| k3s | Ready | Ready | Ready |
| ArgoCD | 7/7 Running | 7/7 Running | 7/7 Running |
| cert-manager | 3/3 Running | 3/3 Running | 3/3 Running |
| CNPG | 1/1 Running | 1/1 Running | 1/1 Running |
| Traefik | 1/1 Running | 1/1 Running | 1/1 Running |
| Longhorn | 13/13 Running | 13/13 Running | 13/13 Running |
| ExternalDNS | 1/1 Running | 1/1 Running | 1/1 Running |
| SeaweedFS | 3/3 Running | 3/3 Running | 3/3 Running |
| Split-IP firewall | active | active | active |
| crowdsec-firewall-bouncer | ImagePullBackOff | ImagePullBackOff | ImagePullBackOff |
| mongo | ContainerCreating | ContainerCreating | ContainerCreating |

**ArgoCD sync status (resolved 2026-05-25):**
- 16 Applications across 8 waves created and syncing on ashburn
- Root app: Synced (was OutOfSync — fixed by removing `argocd-cm.yaml` from repo, applying health check inline)
- Known: cert-manager OutOfSync (DNS01 needs PowerDNS RFC2136 setup), k8gb/istio Missing (operators not installed)

**Git state (2026-05-25):**
- **dotfiles**: branch `master`, working tree dirty (bootstrap fixes pending commit)
- **2143-59s**: branch `master`, HEAD at `edd4d48` (secret key rename, doc fixes, base-values cleanup)


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

## Resolved (2026-05-25)

| # | Question | Resolution |
|---|----------|------------|
| 1 | ExternalDNS CrashLoopBackOff | **Two root causes**: (a) Secret key `rfc2136TsigSecret` vs Helm chart's expected `tsig-key` — file path mismatch in volume mount. (b) Helm chart v1.21.1 ignores rfc2136 values entirely — doesn't pass `--rfc2136-tsig-secret-alg` to deployment. Fixed by patching deployment args post-install in bootstrap. Secret key standardized to `tsig-key` everywhere. |
| 2 | ArgoCD root-app OutOfSync | `argocd-cm.yaml` in `argocd/` path caused `last-applied-configuration` annotation drift vs live ConfigMap. Removed from repo; health check now applied inline via heredoc in bootstrap script. |
| 4 | Wave ordering + cert-manager health | ArgoCD DOES gate waves on health. Lua health check defaulted to "Progressing", stalling on Certificate resources (no intrinsic health). Changed default to "Healthy", only "Degraded" blocks progression. Certificates/ClusterIssuers should be moved to wave 2+ (after DNS01 is working). |
| 5 | ExternalDNS in ArgoCD repo | Deferred — bootstrap Helm + post-patch working reliably. base/externaldns/ has ConfigMap+Secret. Full migration when Helm chart stabilizes. |
| 6 | Traefik hostPort/hostNetwork | Disabled — template errors in Traefik v34+ with hostPort. Can re-add when DDoS protection needed (hostPort on raw IP interface only). |

## Open Questions

- [ ] Should k3s-nuremberg stay in ashburn location? cpx32 boot bug blocks EU datacenters. Need to test when Hetzner updates hypervisor/KVM.
- [ ] How to handle CNPG pdns user password on rebuild? `bootstrap.initdb` generates random password. `hetzner-postgres-schema` needs a password reset step.
- [ ] Test cert-manager DNS01 challenge end-to-end (ClusterIssuer → PowerDNS via RFC2136)
- [ ] Create deSEC NS glue records delegating `9s.pics` to ns1/ns2/ns3

## Recent Artifacts

| Path | Description | Last Modified |
|------|-------------|---------------|
| `nixos/hetzner/modules/hetzner-k3s-common.nix` | Bootstrap: ArgoCD, CNPG, operators, secrets (updated: inline argocd-cm, secret key, Traefik pin, ExternalDNS patch) | 2026-05-25 |
| `nixos/hetzner/modules/hetzner-split-ip-firewall.nix` | Per-IP iptables DDoS firewall | May 24 |
| `nixos/hetzner/flake.nix` | Node configs with rawIP per-node | May 24 |
| `repos/2143-59s/argocd/root-app.yaml` | Root Application (directory.recurse) | May 24 |
| `repos/2143-59s/base/externaldns/rfc2136-secret.yaml` | RFC2136 secret placeholder (key: tsig-key) | 2026-05-25 |
| `repos/2143-59s/base/cert-manager/cluster-issuer-*.yaml` | DNS01 ClusterIssuers (key: tsig-key) | 2026-05-25 |
| `repos/2143-59s/clusters/base-values.yaml` | Shared Helm defaults (hostPort disabled) | 2026-05-25 |

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

- [x] Fix ExternalDNS CrashLoopBackOff (secret key name + missing TSIG args)
- [x] Fix ArgoCD root-app sync (remove argocd-cm.yaml, health check default)
- [x] Deploy Traefik and ExternalDNS on hillsboro and nuremberg
- [x] Rebuild hillsboro and nuremberg with updated bootstrap
- [x] Home-pi confirmed online (all services active, tailnet healthy)

### Remaining

- [ ] **crowdsec-firewall-bouncer**: ImagePullBackOff on all 3 nodes — check image registry/tag
- [ ] **mongo**: ContainerCreating on all 3 nodes — investigate dependency
- [ ] Install remaining operators: k8gb, Istio (currently Missing in ArgoCD)
- [ ] Fix cert-manager OutOfSync: move Certificates/ClusterIssuers to wave 2+ (after DNS01 working)
- [ ] CNPG password reset automation: add `ALTER USER pdns PASSWORD` step to `hetzner-postgres-schema`
- [ ] Test cert-manager DNS01 challenge end-to-end (ClusterIssuer → PowerDNS via RFC2136)
- [ ] Create deSEC NS glue records delegating `9s.pics` to ns1/ns2/ns3
- [ ] Should k3s-nuremberg stay in ashburn location? (cpx32 NixOS boot bug)

## Verification (2026-05-25)

- [x] All 3 nodes: `kubectl get nodes` shows Ready
- [x] All 3 nodes: `systemctl is-active k3s pdns tailscaled split-ip-firewall` returns active
- [x] All 3 nodes: `kubectl get pods -n external-dns` shows 1/1 Running
- [x] Ashburn ArgoCD: `kubectl get apps -n argocd` shows all 16 apps, root Synced
- [x] Home-pi: pdns + headscale + tailscaled active, all 3 Hetzner peers visible