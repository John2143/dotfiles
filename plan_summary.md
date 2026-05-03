# Cilium migration — plan summary

Operative plan: `~/.claude/plans/actually-lets-make-a-dapper-lemur.md`. This file is the executive summary; the full plan has the procedures, rollback details, and known gotchas.

## Goals

1. **Stop lateral pod movement.** Today: zero NetworkPolicies, full lateral movement from any compromised pod.
2. **Per-app authz.** Today: Longhorn UI is wide-open destructive admin. Authentik is installed but unused.
3. **East-west encryption.** Today: pod-to-pod plaintext on the wire.

Optimization target: most-maintainable steady state.

## Architecture target

| Layer | Today | After |
|---|---|---|
| CNI | Flannel | **Cilium 1.16.5** (eBPF, dual-stack, tunnel/vxlan) |
| kube-proxy | k3s default | **Replaced** (Cilium kpr) |
| Service-LB | klipper-lb | **Removed** — Gateway uses `externalIPs: [192.168.5.35, <arch-static>]` |
| NetworkPolicy | unused k3s built-in | Standard `NetworkPolicy` + targeted `CiliumNetworkPolicy` |
| East-west encryption | none | **Cilium WireGuard** `nodeEncryption: true` |
| Ingress | Traefik | **Cilium Gateway API** |
| North-south auth | Authentik (no consumers) | Authentik Proxy Provider (Longhorn first) |
| Cert issuance | cert-manager | unchanged |

**Why Cilium-only, not Cilium + Istio Ambient**: per-workload SPIFFE mTLS doesn't change the blast radius in a 4-node single-CP cluster — a compromised node already holds kubelet creds and reads every Secret. The maintenance cost of istiod + ztunnel + waypoints isn't justified at this scale. Authentik forward-auth at the Gateway covers per-user authz; WireGuard `nodeEncryption` covers wire encryption.

**Why externalIPs over Cilium L2 announcements**: LAN is a router DHCP range with no carve-outs; nodes may move VLANs; reusing closet's existing IP keeps the WAN port-forward (`WAN:80/443 → 192.168.5.35`) working unchanged. Adding arch's static IP gives data-plane ingress HA on tailnet via dual-A DNS.

## Phase ordering

| # | Phase | Repo | Disruption |
|---|---|---|---|
| 0 | Pre-flight (ZFS snapshot every node) | both | none |
| 3a | Authentik Proxy → Longhorn UI | argo | none |
| 1 | Cilium swap (Flannel + kube-proxy + servicelb out) | dotfiles | ~30 min |
| — | Soak ≥ 1 week | — | — |
| 1.5 | Cilium Gateway replaces Traefik | dotfiles + argo | 5–10 min ingress |
| — | Soak ≥ 1 week | — | — |
| 1.7 | WireGuard `nodeEncryption: true` | dotfiles | ~30s blip |
| 2 | NetworkPolicy default-deny (audit then enforce) | argo | 0 if audit catches all flows |
| 3+ | Authentik expansion (argocd, immich, unifi) | argo | per-app, ~30s each |

## Current state (branch `cilium-migration`)

- **Phase 1 dotfiles change is staged** — `nixos/closet-configuration.nix` now installs Cilium 1.16.5 via helm-controller and disables Flannel / kube-proxy / servicelb. Phase 1.5 (`gatewayAPI`) and Phase 1.7 (`encryption`) toggles are pre-staged as commented blocks for one-line uncomments at their respective windows.
- **Not yet executed.** `nixos-rebuild switch` happens during the maintenance window per dapper-lemur's "Migration day procedure".
- **Phase 3a** (argo-side, Authentik forward-auth for Longhorn UI) is owned by the argo-side agent and runs in parallel.

## Pre-flight gates before running `nixos-rebuild switch` on closet

- ZFS snapshot every node (closet, office, arch, pite). Record snapshot names.
- ArgoCD auto-sync paused on every Application.
- `kubectl get nodes,pods,ingress,svc,gateway,httproute -A -o wide > pre-cutover.txt`.
- Node `/etc/resolv.conf` set to `1.1.1.1` for the window.
- Kernel features verified: `zgrep -E 'BPF|NETFILTER_XT_SET' /proc/config.gz`.
- arch assigned a static LAN IP (DHCP reservation) ahead of Phase 1.5; pite stays DHCP.
- Authentik outpost CRD state recorded: `kubectl -n authentik get outposts.authentik.goauthentik.io`.
- Cilium 1.16.5 values syntax pinned to a docs URL (don't carry "verify at install time" into the window).

## Rollback (Phase 1)

ZFS-based:
1. `zfs rollback` each node to the Phase-0 snapshot.
2. Reboot each node.

K3s comes back exactly as it was — Flannel + kube-proxy + servicelb. ArgoCD reconciles workloads. No `git revert` strictly required (the dotfiles commit can stay; `nixos-rebuild switch` doesn't re-run after a ZFS rollback unless triggered).
