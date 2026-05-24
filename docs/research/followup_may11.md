# Follow-up: Bootstrap Gap & NixOS Provisioning — May 11

## Context

The `2143-59s` ArgoCD GitOps repo is complete and validated by research. The next step is wiring it to actual clusters — this requires changes in this repo (`~/dotfiles/nixos/hetzner/`).

## What's Done

- `2143-59s`: full App-of-Apps monorepo with sync-wave ordering, per-cluster values, placeholder secrets, bootstrap helpers
- Research: 6-sub-topic validation confirming the approach follows best practice

## What's Needed Here

### 1. ArgoCD Installation During Bootstrap

**File**: `nixos/hetzner/scripts/provision.sh`

After k3s + PowerDNS are confirmed running, add an ArgoCD bootstrap step:

```bash
# ── Step 5: Install ArgoCD ──
echo "  [5/6] Installing ArgoCD..."

# Install CRDs (must precede core manifests)
kubectl apply --server-side --force-conflicts \
  -k https://github.com/argoproj/argo-cd/manifests/crds?ref=stable

# Install ArgoCD core
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for server
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# Apply the argocd-cm ConfigMap (health checks + resource tracking)
kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/refs/heads/master/argocd/argocd-cm.yaml

# Apply the root Application — wires ArgoCD to the GitOps repo
kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/refs/heads/master/argocd/root-app.yaml

echo "  ArgoCD installed. Cluster will reconcile from Git."
```

Alternative: if NixOS has a `services.argocd` module, use that instead of raw kubectl. Check `nixos-option` or nixpkgs search for availability.

### 2. agenix Secrets → /run/agenix/

**File**: `nixos/hetzner/modules/hetzner-k3s-server.nix` (or a new `hetzner-secrets.nix`)

Ensure agenix decrypts secrets to `/run/agenix/` on boot, making them available to the `secret-injector` Job in `2143-59s` (`base/argocd-bootstrap/secret-injector-job.yaml`).

The Job expects these files at `/run/agenix/`:
- `powerdns-tsig-key` → `external-dns/rfc2136-credentials`
- `mongodb-encryption-key` → `default/mongo-encryption-key`
- `mongodb-password` → `default/mongo-creds`
- `seaweedfs-master-key` → `seaweedfs/seaweedfs-master-key`
- `rclone-b2-password` → `backup/rclone-config`
- `b2-application-key` → `default/b2-credentials`

The README already documents the agenix generation commands. Verify each `.age` file exists and is referenced in `secrets/secrets.nix`.

### 3. Headscale on Home Pi

**File**: `rpi4b-configuration.nix` or similar

The architecture calls for Headscale running on the Home Pi as the VPN coordination point. This needs to be running before the Hetzner nodes try to join the Tailscale network. Verify the Pi config includes `services.headscale` and is deployed.

### 4. Order of Operations

The deployment order matters:

1. **Home Pi first**: Headscale + PowerDNS #3 + Uptime Kuma + RustFS
2. **Secrets**: Generate all age secrets in `nixos/hetzner/secrets/`
3. **Provision Ashburn server**: `./provision.sh ashburn server`
4. **Verify**: PowerDNS, MariaDB Galera, k3s, ArgoCD synced from Git
5. **Provision Hillsboro + Nuremberg servers**: same process
6. **Verify cross-cluster**: k8gb Gslb, ExternalDNS RFC2136, cert-manager
7. **Optional**: `./toggle-ha.sh` for HA mode (3 agent nodes)
8. **DNS cutover**: Point domain NS records at PowerDNS nameservers

### 5. Things to Check Before Hitting Provision

- [ ] Hetzner API token set in `hcloud-token.age`
- [ ] All 8 secrets generated (`ls nixos/hetzner/secrets/*.age`)
- [ ] Domain `9s.pics` NS records ready to point at PowerDNS
- [ ] Backblaze B2 bucket created + application key saved
- [ ] Healthchecks.io project created + ping URL saved
- [ ] `2143-59s` repo is public (or ArgoCD has deploy key access)
- [ ] Home Pi is running Headscale + RustFS
- [ ] SSH key `john@arch` exists in Hetzner

## Not in Scope (for now)

- Bunny CDN configuration (manual DNS change, not in K8s)
- ApplicationSet migration (deferred per research)
- Multi-provider node for true 5-nines (all-Hetzner accepted)
