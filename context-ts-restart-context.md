# Context: ts-restart-context

> Saved 2026-06-02 from branch `master` by `<user>`

## Goal
Recover closet's k3s cluster membership after it was reset as the original bootstrap node. Closet was the first control-plane node but was wiped and needs to rejoin the existing 2-node HA etcd cluster (NAS + arch).

## Current State
- **Branch**: `master`
- **Modified files**: 19 files (all age secrets — noise from `agenix -r` rekey, can be discarded)
- **Last commit**: `95e8663 fix(closet): add k3s-server module + k3s token access`
- **Committed changes**:
  - `flake.nix` — added `./nixos/modules/k3s-server.nix` to closet's NixOS imports
  - `secrets/secrets.nix` — added `closet` to `k3s-local-token.age` publicKeys
  - `secrets/k3s-local-token.age` — re-encrypted with closet key
  - `nixos/closet-configuration.nix` — changed `--cluster-init` to `--server=https://192.168.5.10:6443`
  - `nixos/shared-configuration.nix` — removed `xdg-desktop-portal-hyprland`
- **Cluster state**: 2 healthy etcd members (arch + nas), quorum = 2. VIP (192.168.5.10) working. Closet removed from cluster (etcd member + k8s node deleted).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Replace `--cluster-init` with `--server` for closet rejoin | closet is no longer the bootstrap node; must join the existing cluster |
| 2 | Keep `--node-ip=192.168.5.35` | etcd membership is keyed to this IP; routing metrics handle 10G preference |
| 3 | Add `./nixos/modules/k3s-server.nix` to closet's flake.nix imports | Module sets `tokenFile` → generates `--token-file` in ExecStart, matching NAS/arch |
| 4 | Add `closet` to `k3s-local-token.age` publicKeys and re-encrypt | Closet needs access to the shared agenix cluster token |
| 5 | Nuclear clean of `/var/lib/rancher/k3s/server` between attempts | Partial cleanups left stale CAs that caused TLS cert chain mismatches |
| 6 | Use `--server=https://nas.local:6443` instead of VIP for join test | Suspect kube-vip on closet might route join requests back to itself |

## Ruled Out

| Approach | Why rejected |
|----------|-------------|
| Partial cleanup (delete only `db/`, `tls/`, `cred/`) | Stale CAs caused local kine→etcd TLS handshake failures |
| Using closet's old token (`/var/lib/rancher/k3s/server/token`) | Old token was different from agenix token used by NAS/arch |
| Running k3s without `--token-file` | k3s creates local SQLite cluster instead of joining |
| Pointing `--server` at VIP vs NAS directly | Same TLS failure pattern with both — kube-vip not the cause |
| Using `--server=https://192.168.5.10:6443` (VIP) | Same TLS failure as NAS direct; kube-vip not the issue |

## Open Questions

- [ ] Why does local kine→etcd TLS handshake always fail despite valid certs (verified with `openssl verify`)?
- [ ] Would the TLS issue self-resolve if k3s were left running for 5+ minutes? (never tested — always restarted)
- [ ] Are the stale containerd-shim processes interfering with k3s startup?
- [ ] Is closet currently online and reachable? Last seen: unreachable ("No route to host")

## Recent Artifacts

| Path | Description | Last Modified |
|------|-------------|---------------|
| `dotfiles/flake.nix` | Added k3s-server.nix to closet imports | session |
| `dotfiles/nixos/closet-configuration.nix` | Changed --cluster-init to --server, dual-stack cidrs | session |
| `dotfiles/secrets/secrets.nix` | Added closet to k3s-local-token publicKeys | session |
| `dotfiles/secrets/k3s-local-token.age` | Re-encrypted with closet key | session |
| `dotfiles/nixos/modules/k3s-server.nix` | Shared module: tokenFile, firewall, tailscale | earlier |
| `dotfiles/nixos/shared-configuration.nix` | Removed xdg-desktop-portal-hyprland | earlier |

## Constraints

- All changes must be via NixOS configuration, pushed to GitHub
- k3s is a 3-node HA cluster (arch, nas, closet) with embedded etcd
- VIP `192.168.5.10` via kube-vip floats between control-plane nodes
- Quorum must be maintained — never go below 2 members during recovery
- No destructive operations without understanding root cause

## Anatomy of the Failure

The TLS issue manifests as:

1. k3s on closet contacts cluster, authenticates with token → OK
2. k3s downloads bootstrap data and cluster CA → OK
3. k3s adds itself as etcd learner → OK (peer-to-peer etcd connections work)
4. etcd starts and listens on `127.0.0.1:2379` → OK (verified with `ss -tlnp`)
5. kine client (kube-apiserver) tries to connect to local etcd via HTTPS → **FAILS**
6. Error: `transport: authentication handshake failed: context deadline exceeded`
7. Without local etcd access, k3s cannot promote learner → stuck forever

The cert chain is valid (verified with `openssl verify`):
- `client.crt` signed by `server-ca.crt` ✅
- `server-client.crt` signed by `server-ca.crt` ✅  
- etcd server trusts `server-ca.crt` for client auth ✅
- kube-apiserver uses `client.crt` + `client.key` with `server-ca.crt` as CA ✅

TCP connect to 127.0.0.1:2379 succeeds. TLS handshake times out.

## Next Steps

1. [ ] **Pick up here**: Check if closet is online. Try `ssh closet.local` or `ssh 192.168.5.35`. If not, physical power cycle required.
2. [ ] Once online, kill all leftover containerd-shim processes: `sudo killall -9 containerd-shim`
3. [ ] Nuclear clean: `sudo rm -rf /var/lib/rancher/k3s/server && sudo systemctl reset-failed k3s`
4. [ ] Verify systemd unit has `--token-file /run/agenix/k3s-local-token` in ExecStart
5. [ ] Verify agenix token is decrypted: `sudo cat /run/agenix/k3s-local-token`
6. [ ] Start k3s: `sudo systemctl start k3s`
7. [ ] Wait 5+ minutes — do NOT restart. Watch logs for "Adding member" and etcd join messages
8. [ ] Check if learner promotes to voting member: `etcdctl member list` — last column should be `false` (not learner)
9. [ ] Verify closet appears as k8s node: `k3s kubectl get nodes` — should show `Ready, control-plane,etcd`

## Verification

- `k3s kubectl get nodes` from NAS shows closet as Ready, control-plane,etcd
- `etcdctl member list` shows 3 members (arch, nas, closet) with closet NOT flagged as learner
- All pods healthy, no stuck pods related to closet Longhorn replicas
- closet's `k3s kubectl` works locally (no "ServiceUnavailable")

## Critical Note

The Nix config fix is committed and pushed. If closet was rebuilt before going offline, the systemd unit already has the corrected ExecStart. If NOT rebuilt yet, user must `nixos-rebuild switch` on closet after it comes back online, before starting k3s.
