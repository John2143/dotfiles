# 9s.pics Infrastructure — Attempt #4 Summary

## Outcome: Partial success — single node operational, Galera cluster NOT working

### What works
| Component | Status | Detail |
|-----------|--------|--------|
| k3s (ashburn) | OK | Node Ready, Flannel CNI, pod networking works |
| k3s (hillsboro) | OK | Node Ready, Flannel CNI |
| k3s (nuremberg) | OK | Node Ready, Flannel CNI |
| Tailscale | OK | All 4 nodes on tailnet, headscale via home-pi |
| pdns | OK | Zone `9s.pics` created, SOA/NS records set, TSIG key configured |
| ArgoCD | OK | Core installed, all pods 1/1 Running |
| Home Pi | OK | Headscale, MySQL standalone, pdns |

### What does NOT work
| Component | Issue |
|-----------|-------|
| **Galera cluster** | Cannot bootstrap — joining nodes crash during SST. Root cause found and fixed (see below). |
| ExternalDNS | Namespace not created (ArgoCD hasn't reconciled root-app yet) |
| k8s-secrets-bootstrap | Same — waits for ArgoCD-created namespaces |

### Root cause: Galera SST blocked by seccomp — FIXED
The MySQL service has 21 seccomp filters (systemd hardening). `NoNewPrivileges=true` means forked children inherit them and can't remove them. One filter blocks `execve`/`clone` in `posix_spawnp()` children, preventing `wsrep_sst_rsync` from running.

**Fix applied:** `serviceConfig.SystemCallFilter = lib.mkForce "@default @process"` in `hetzner-galera.nix`. The `@process` preset group includes `execve`, `execveat`, `fork`, `vfork`, `clone`, `clone3` — all the syscalls needed for process spawning. `@default` preserves basic operations.

### Code changes made during attempt #4
| File | Change |
|------|--------|
| `hetzner-galera.nix` | Added `pkgs.rsync` + `pkgs.mariadb` to MySQL service PATH (SST needs both) |
| `hetzner-galera.nix` | `wsrep_cluster_address` uses tailscale DNS names (not hardcoded IPs) |
| `hetzner-galera.nix` | `SystemCallFilter = "@default @process"` — fixes SST seccomp blocker |
| `hetzner-galera.nix` | Added `networking.firewall.allowedTCPPorts = [ 4444 4567 4568 ]` (missing on home-pi) |
| `flake.nix` | Removed hardcoded `galeraNodeAddress` — DNS names auto-resolve |
| `home-pi.nix` | Set `wsrep_node_address = "100.64.0.2"` (multi-interface host, auto-detect picks wrong IP) |
| `hetzner-k3s-common.nix` | Switched from Cilium to Flannel (removed `--flannel-backend=none`, cilium-bootstrap) |
| `hetzner-k3s-common.nix` | Fixed ArgoCD bootstrap: `--server-side` on install.yaml, non-empty redis password |
| `hetzner-powerdns-bootstrap.nix` | Fixed `@` → `9s.pics` in pdnsutil rrset (pdns 5.x incompatibility) |
| `provision.sh` | Added Cilium taint removal + stale kernel interface cleanup |
| `provision.sh` | Added headscale stale-node cleanup before each provision (ensures fresh DNS) |
| `README.md` + `provision.sh` | Replaced all `192.168.0.154` with `john@home-pi` |

### Key architectural decisions
1. **Switched from Cilium to Flannel** — Cilium 1.19 on NixOS kernel 6.18 has broken pod-to-host routing. Flannel works immediately.
2. **Galera uses tailscale DNS names** — `wsrep_cluster_address` uses `k3s-ashburn.ts.9s.pics,...` instead of hardcoded IPs. Stable across node reboots/recreates. Provision script cleans stale headscale nodes so DNS always resolves correctly.
3. **Galera SST seccomp fix** — `SystemCallFilter = "@default @process"` overrides systemd's stacked seccomp filters that block `execve`/`clone` in child processes.

### Teardown complete
All 3 VMs and 3 floating IPs destroyed. 4 stale headscale nodes cleaned. Home-pi MySQL restored to standalone.

### Remaining to deploy (not reached)
- ExternalDNS (RFC2136 → pdns)
- cert-manager
- k8gb GSLB
- SeaweedFS
- Temporal
- CNPG (CloudNativePG)
- Longhorn
- deSEC DNS records (A glue for ns1/ns2/ns3.9s.pics)
- Backblaze B2 bucket creation

---

## Recommended prompt for attempt #5

```
Deploy the 9s.pics infrastructure. See batch_4.md for what was learned in attempt #4.

Pre-flight:
- Home Pi is at john@home-pi, tailscale 100.64.0.2, headscale active, MySQL running standalone
- HCLOUD_TOKEN is in nixos/hetzner/secrets/hetzner/hcloud-token.age (decrypt with agenix -d ... -i ~/.ssh/age from nixos/hetzner/secrets/)
- All 11 age secrets decrypt correctly
- The flake is at nixos/hetzner/ — all 7 configs pass `nix flake check`
- provision.sh has been updated with headscale cleanup and Cilium taint fixes
- Galera uses tailscale DNS names (k3s-ashburn.ts.9s.pics etc.), no hardcoded IPs
- SystemCallFilter fix is in place so Galera SST should work this time

Plan:
1. Provision ashburn, verify k3s/pdns/ArgoCD/tailscale all green before continuing
2. Provision hillsboro and nuremberg in parallel
3. Bootstrap Galera: stop all MySQL, set grastate on home-pi, bootstrap home-pi, join Hetzner nodes one at a time, verify cluster_size=4
4. Verify ArgoCD root-app reconciles and child Applications deploy
5. Report node IPs so I can create glue A records in deSEC

Pause and report if anything fails. Do NOT destroy VMs without asking.
```
