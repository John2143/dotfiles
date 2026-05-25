# Context: re-bootstrap-hetzner

> Saved 2026-05-25T21:30:00Z from branch `master` by `<user>`

## Goal
Bootstrap 3 Hetzner k3s clusters (ashburn, hillsboro, nuremberg) with all pods 100% Running on first try. All prior pod issues were root-caused and permanently fixed in GitOps. Attic binary cache on home-pi was fixed and verified. All 3 previous VMs were torn down. Ready for a clean re-deploy.

## Current State
- **Branch**: `master` (both `~/dotfiles` and `~/repos/2143-59s`)
- **Modified files**: 0 (clean working trees)
- **Last dotfiles commit**: `54661a4` fix(attic): deduplicate token reading — read first matching file only
- **Last 2143-59s commit**: `21e42ae` fix: remove all placeholder secrets (anti-pattern — IgnoreExtraneous doesn't prevent selfHeal overwrite)
- **Stashes**: 4 in dotfiles (pre-existing WIPs, not session-related)
- **All VMs destroyed**: 0 servers, 0 floating IPs on Hetzner Cloud
- **deSEC DNS**: Only `headscale.9s.pics` A record remains; NS delegation shell exists but glue A records removed

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Remove crowdsec-firewall-bouncer DaemonSet from GitOps | No official iptables bouncer Docker image exists from CrowdSec; split-IP firewall handles this at NixOS level |
| 2 | Remove all placeholder secrets from GitOps | ArgoCD selfHeal WILL overwrite injected values even with `IgnoreExtraneous` annotation; secrets injected by k8s-secrets-bootstrap must NOT exist in GitOps |
| 3 | Remove Mongo encryption flags + volume mount | `mongo:7` is Community Edition; `--enableEncryption` and `--encryptionKeyFile` are Enterprise-only |
| 4 | Remove mongo-backup CronJob from GitOps | Requires rclone binary (not in `mongo:7` image) + full rclone.conf with B2 keyID + crypt password (not yet provisioned) |
| 5 | Remove mongo-encryption-key from k8s-secrets-bootstrap | No longer needed after encryption flag removal |
| 6 | Fix healthchecks-url namespace | Was injecting to `backup`, corrected to `monitoring` to match CronJob |
| 7 | Fix Attic agenix path | Agenix deploys to `/run/agenix.d/N/secret-name`, not `/run/agenix/secret-name`; use first-match glob |
| 8 | Fix Attic public key | Config had `Ysam0oz...`, cache actual key is `LvE5AP...` |
| 9 | Destroy all VMs + floating IPs + DNS + Headscale + known_hosts | Clean teardown for re-bootstrap |

## Ruled Out

| Approach | Why rejected |
|----------|-------------|
| Installing rclone at runtime in mongo:7 container | `apt-get install rclone` is slow per-cron-run AND still needs full rclone.conf with B2 keyID + crypt password |
| Keeping placeholder secrets with `IgnoreExtraneous` | ArgoCD selfHeal WILL reconcile and overwrite; annotation prevents drift detection but NOT overwrite |
| Using MongoDB Enterprise for encryption-at-rest | No enterprise license available |
| Fixing crowdsec image tag | No `crowdsecurity/firewall-bouncer` or `crowdsecurity/crowdsec-firewall-bouncer` image exists; iptables bouncer is host binary only |

## Open Questions
- [ ] Should mongo-backup CronJob be re-enabled? Needs B2 application key ID + crypt password provisioned as agenix secrets + custom Docker image with rclone
- [ ] Is the attic JWT token still valid? It was generated with `atticadm make-token --sub "hetzner-nodes" --validity "10y"` — should be fine
- [ ] Do any new agenix secrets need to be generated before re-bootstrap?

## Recent Artifacts

### `~/dotfiles` (key files modified this session)

| Path | Description | Status |
|------|-------------|--------|
| `nixos/hetzner/README.md` | Added "Kubernetes Pod Troubleshooting" section (94 lines) | Committed |
| `nixos/hetzner/modules/hetzner-k3s-common.nix` | Removed mongo-encryption-key injection, fixed healthchecks namespace, fixed attic agenix path + public key + token dedup | Committed |
| `nixos/modules/attic-server.nix` | Reviewed — no changes needed | Unchanged |

### `~/repos/2143-59s` (key files modified this session)

| Path | Change | Status |
|------|--------|--------|
| `base/crowdsec/firewall-bouncer-config.yaml` | Deleted (no Docker image exists) | Committed |
| `base/mongodb/encryption-secret.yaml` | Deleted (placeholder anti-pattern) | Committed |
| `base/mongodb/deployment.yaml` | Removed encryption flags + volume mount | Committed |
| `base/mongodb/backup-cronjob.yaml` | Deleted (needs rclone config) | Committed |
| `base/apps/mongo/deployment.yaml` | Same encryption/volume fixes for imagehost mongo | Committed |
| `base/backups/rclone-config-secret.yaml` | Deleted (placeholder anti-pattern) | Committed |
| `base/crowdsec/lapi-deployment.yaml` | Removed crowdsec-bouncer-key placeholder secret | Committed |
| `base/monitoring/healthchecks-cronjob.yaml` | Removed healthchecks-url placeholder secret | Committed |
| `README.md` | Updated with placeholder secrets anti-pattern docs | Committed |

## Constraints
- All 3 server nodes identical (`mkServer`), drop-in replaceable
- MongoDB Community Edition only (no `--enableEncryption`)
- Secrets injected by `k8s-secrets-bootstrap` MUST NOT exist as placeholders in GitOps
- deSEC DNS NS delegation pattern (one-time NS+glue on deSEC, dynamic records via PowerDNS)
- Home-pi runs Headscale + Attic binary cache + PowerDNS
- Floating IPs mask primary Hetzner IPs
- Nuremberg deploys in ashburn location (cpx32 NixOS boot bug in EU DCs)

## Bootstrap Checklist (priority order)

### 1. Verify home-pi services
- [ ] Atticd running (`systemctl status atticd` on home-pi)
- [ ] PowerDNS running
- [ ] Headscale running
- [ ] Port forward `8280 → home-pi:8280` active on home router

### 2. Verify deSEC DNS baseline
- [ ] `headscale.9s.pics` A record resolves to home public IP
- [ ] No stale NS glue A records (ns1, ns2, ns3 should be gone)
- [ ] Run `nixos/hetzner/scripts/desec-dns.sh bootstrap-dns <region> <floating-ip>` during provision (script handles NS+glue)

### 3. Verify agenix secrets exist
- [ ] `nixos/hetzner/secrets/hetzner/hcloud-token.age`
- [ ] `nixos/hetzner/secrets/hetzner/desec-token.age`
- [ ] `nixos/hetzner/secrets/hetzner/attic-token.age` (JWT for clients)
- [ ] `nixos/hetzner/secrets/hetzner/attic-server-secret.age` (HS256 for home-pi)
- [ ] `nixos/hetzner/secrets/hetzner/k3s-token.age`
- [ ] `nixos/hetzner/secrets/hetzner/mongodb-encryption-key.age` (used for mongo-creds password generation)
- [ ] `nixos/hetzner/secrets/hetzner/postgres-pdns-password.age`
- [ ] `nixos/hetzner/secrets/hetzner/powerdns-tsig-key.age`
- [ ] `nixos/hetzner/secrets/hetzner/headscale-preauth-key.age`
- [ ] `nixos/hetzner/secrets/hetzner/rclone-b2-password.age`
- [ ] `nixos/hetzner/secrets/hetzner/seaweedfs-master-key.age`
- [ ] `~/.ssh/age` identity present

### 4. Provision in order
- [ ] **Pick up here**: `export HCLOUD_TOKEN=$(agenix -d nixos/hetzner/secrets/hetzner/hcloud-token.age -i ~/.ssh/age)`
- [ ] Ashburn first: `cd nixos/hetzner/scripts && ./provision.sh ashburn server`
- [ ] Hillsboro second: `./provision.sh hillsboro server`
- [ ] Nuremberg third: `./provision.sh nuremberg server`
- [ ] After all 3 up: `./desec-dns.sh update-all-nodes`

### 5. Verify success
- [ ] All 3 nodes reachable via SSH
- [ ] Tailscale connected (100.64.0.x addresses)
- [ ] `kubectl get pods -A --no-headers | grep -vE 'Running|Completed'` returns 0 on each node
- [ ] Attic watch-store running on all 3
- [ ] PowerDNS responding on floating IPs:53
- [ ] CNPG PostgreSQL healthy
- [ ] ArgoCD all apps Synced/Healthy

## Verification
Successful bootstrap means: 3 VMs running, `kubectl get pods -A` shows zero non-Running/non-Completed pods across all 3 clusters, attest watch-store `👀 Pushing...` on all 3, deSEC DNS NS+glue resolves, and `curl http://headscale.9s.pics:8280/` returns the Attic ASCII art page.
