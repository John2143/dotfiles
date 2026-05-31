#!/usr/bin/env bash
# provision.sh — Create Hetzner VM and deploy NixOS via nixos-anywhere
#
# End-to-end provisioning for a single Hetzner k3s node. Automates:
#   1. VM creation (cpx31, ubuntu-24.04 base)
#   2. Floating IP allocation + assignment (for IP masking / DDoS protection)
#   3. deSEC DNS bootstrap (NS delegation + glue A records)
#   3b. deSEC node A record (k3s-<region>.9s.pics → floating IP)
#
#   4. nixos-anywhere deploy (kexec → disko format → NixOS install)
#   5. Post-deploy: age key copy, agenix decrypt, headscale cleanup
#   6. deSEC node A record (k3s-<region>.9s.pics → floating IP)
#   7. Tailscale connect (via Headscale preauth key)
#   8. Service verification (k3s, tailscaled)
#
#   hillsboro NEXT → pulls cache from ashburn (when Attic cache is set up)
#   nuremberg LAST → same cache benefits
#
# Usage: ./provision.sh <region> <role>
#   region: ashburn | hillsboro | nuremberg
#   role:   server  | agent
#
# Requires: HCLOUD_TOKEN env var, hcloud CLI, nixos-anywhere, age key at ~/.ssh/age
#
# Example:
#   export HCLOUD_TOKEN="$(agenix -d ../secrets/hetzner/hcloud-token.age -i ~/.ssh/age)"
#   ./provision.sh ashburn server

set -euo pipefail

REGION="${1:?Usage: $0 <ashburn|hillsboro|nuremberg> <server|agent>}"
ROLE="${2:?Usage: $0 <ashburn|hillsboro|nuremberg> <server|agent>}"

HOSTNAME="k3s-${REGION}"
[[ "$ROLE" == "agent" ]] && HOSTNAME="${HOSTNAME}-agent"

# ── Region → Hetzner location mapping ──
# NOTE: EU datacenters (nbg1, fsn1) fail to boot NixOS with cpx32.
# Nuremberg runs in ashburn until this is resolved.
case "$REGION" in
  ashburn)   LOCATION="ash"   ;;
  hillsboro) LOCATION="hil"   ;;
  nuremberg) LOCATION="ash"   ;;  # TODO: move to nbg1/fsn1 when cpx32 NixOS boot fixed
  *) echo "Unknown region: $REGION"; exit 1 ;;
esac

# Region → Plan mapping
# ash is out of cpx31 capacity; use ccx13 (dedicated 2-core/8GB/80GB) as fallback
case "$LOCATION" in
  ash) PLAN="ccx13"  ;;
  hil) PLAN="cpx31"  ;;
  *)   PLAN="cpx31"  ;;
esac

FLAKE=".#${HOSTNAME}"

echo "=== Provisioning ${HOSTNAME} (${PLAN}, ${LOCATION}) ==="



# ── Step 1: Create Hetzner VM ──
echo "  [1/7] Creating VM..."
SERVER_ID=$(hcloud server create \
  --name "${HOSTNAME}" \
  --image ubuntu-24.04 \
  --type "${PLAN}" \
  --location "${LOCATION}" \
  --ssh-key john@office \
  -o json \
  | jq -r '.server.id')

echo "  VM created: ${SERVER_ID}"

# Wait for IP
echo "  Waiting for IP..."
sleep 5
IP=$(hcloud server ip "${SERVER_ID}")
echo "  IP: ${IP}"

# ── Step 2: Allocate floating IP for raw services ──
echo "  [2/7] Allocating raw IP..."
RAW_IP_ID=$(hcloud floating-ip create \
  --description "${HOSTNAME}-raw" \
  --home-location "${LOCATION}" \
  --type ipv4 \
  -o json | jq -r '.floating_ip.id')
hcloud floating-ip assign "${RAW_IP_ID}" "${SERVER_ID}"
RAW_IP=$(hcloud floating-ip describe "${RAW_IP_ID}" -o json 2>/dev/null | jq -r '.floating_ip.ip // .ip // "unknown"')
echo "  Raw IP: ${RAW_IP}"
# ── deSEC DNS bootstrap: NS + glue A records ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "  deSEC DNS bootstrap..."
"${SCRIPT_DIR}/desec-dns.sh" bootstrap-dns "${REGION}" "${RAW_IP}" 2>/dev/null || {
  echo "    WARNING: deSEC DNS bootstrap failed — continuing (DNS may need manual setup)"
}
echo "    NS + glue records set on deSEC"

# ── Step 3: Deploy NixOS via nixos-anywhere ──
echo "  [3/7] Deploying NixOS..."
nix run --builders '' github:nix-community/nixos-anywhere -- \
  --flake "${FLAKE}" \
  --target-host "root@${IP}"

# ── Step 4: Wait for NixOS to boot ──
echo "  [4/7] Waiting for NixOS boot..."
ssh-keygen -R "${IP}" 2>/dev/null || true
for i in $(seq 1 20); do
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "root@${IP}" "hostname" 2>/dev/null && break
  echo "    waiting... ($i/20)"
  sleep 10
done
echo "  NixOS booted: $(ssh -o StrictHostKeyChecking=accept-new "root@${IP}" hostname 2>/dev/null || echo unknown)"

# ── Step 5: Post-deploy setup ──
echo "  [5/7] Post-deploy setup..."
# Copy age identity so agenix can decrypt secrets
scp ~/.ssh/age "root@${IP}:/etc/ssh/age-identity"
ssh "root@${IP}" "chmod 600 /etc/ssh/age-identity"
echo "    age identity copied"

# Rebuild to decrypt agenix secrets
nixos-rebuild switch --flake "${FLAKE}" --target-host "root@${IP}" --use-remote-sudo 2>/dev/null || true
echo "    agenix secrets decrypted"

# Delete stale headscale nodes with same hostname (ensures fresh DNS)
ssh john@192.168.0.154 "sudo headscale nodes list -o json 2>/dev/null" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for n in data:
    if n['given_name'] == '${HOSTNAME}':
        print(f\"Cleaning stale headscale node: {n['given_name']} ({n['ip_addresses'][0] if n.get('ip_addresses') else 'no ip'})\")
        import subprocess
        subprocess.run(['ssh', 'john@192.168.0.154', 'sudo', 'headscale', 'nodes', 'delete', '--identifier', str(n['id']), '--force'])
" 2>/dev/null || true
echo "    stale headscale nodes cleaned"
# ── deSEC node A record (k3s-<region>.9s.pics → floating IP) ──
echo "  deSEC node A record..."
"$(cd "$(dirname "$0")" && pwd)/desec-dns.sh" set-a "k3s-${REGION}" "${RAW_IP}" 2>/dev/null || {
  echo "    WARNING: node A record failed — continuing"
}
echo "    k3s-${REGION}.9s.pics → ${RAW_IP}"
# Label the floating IP for the health checker to discover it
hcloud floating-ip add-label "${RAW_IP}" "region=${REGION}" 2>/dev/null || echo "    WARNING: floating IP labeling failed"
echo "    Floating IP labeled region=${REGION}"

# ── Step 6: Connect tailscale ──
echo "  [6/7] Connecting tailscale..."
AUTHKEY=$(ssh "root@${IP}" "cat /run/agenix/hetzner/headscale-preauth-key 2>/dev/null" || echo "")
if [ -n "$AUTHKEY" ]; then
  ssh "root@${IP}" "systemctl restart tailscaled 2>/dev/null || true; sleep 3; tailscale up --reset --login-server=http://headscale.9s.pics:6767 --authkey=${AUTHKEY} --accept-routes 2>&1 || true"
  echo "    tailscale connected"
else
  echo "    WARNING: no preauth key found, tailscale not connected"
fi

# ── Step 7: Verify services ──
echo "  [7/7] Restarting services..."
if [[ "$ROLE" == "server" ]]; then
  ssh "root@${IP}" "systemctl restart k3s 2>/dev/null || true"
  echo "  k3s instance ready"
  echo "  --- Service Status ---"
  ssh "root@${IP}" "echo 'k3s:' \$(systemctl is-active k3s); echo 'tailscaled:' \$(systemctl is-active tailscaled)"
  ssh "root@${IP}" "kubectl get nodes 2>/dev/null" || echo "    (k3s not ready yet)"
  # Remove stale Cilium taint if present
  ssh "root@${IP}" "kubectl taint node --all node.cilium.io/agent-not-ready:NoSchedule- 2>/dev/null || true"
  # Clean up stale kernel interfaces on restart
  if ! ssh "root@${IP}" "kubectl get nodes &>/dev/null"; then
    ssh "root@${IP}" "ip link delete flannel.1 2>/dev/null || true; ip link delete cilium_vxlan 2>/dev/null || true; ip link delete cilium_host 2>/dev/null || true; ip link delete cilium_net 2>/dev/null || true; systemctl restart k3s; sleep 15" 2>/dev/null || true
  fi
  ssh "root@${IP}" "tailscale status 2>/dev/null" || echo "    (tailscale not connected yet)"
else
  ssh "root@${IP}" "systemctl is-active k3s-agent 2>/dev/null || echo 'inactive'"
fi

echo ""
echo "=== ${HOSTNAME} provisioned successfully ==="
echo "  IP: ${IP}  |  Raw IP: ${RAW_IP}"
echo "  SSH: ssh root@${IP}"
