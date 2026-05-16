#!/usr/bin/env bash
# provision.sh — Create Hetzner VM and deploy NixOS via nixos-anywhere
#
# Usage: ./provision.sh <region> <role>
#   region: ashburn | hillsboro | nuremberg
#   role:   server  | agent
#
# Requires: HCLOUD_TOKEN env var, hcloud CLI, nixos-anywhere, age key at ~/.ssh/age
#
# Example:
#   export HCLOUD_TOKEN="your-token"
#   ./provision.sh ashburn server   # Deploy ashburn server node
#   ./provision.sh hillsboro agent  # HA toggle — deploy agent

set -euo pipefail

REGION="${1:?Usage: $0 <ashburn|hillsboro|nuremberg> <server|agent>}"
ROLE="${2:?Usage: $0 <ashburn|hillsboro|nuremberg> <server|agent>}"

HOSTNAME="k3s-${REGION}"
[[ "$ROLE" == "agent" ]] && HOSTNAME="${HOSTNAME}-agent"

# ── Region → Hetzner location mapping ──
case "$REGION" in
  ashburn)   LOCATION="ash"   ;;
  hillsboro) LOCATION="hil"   ;;
  nuremberg) LOCATION="nbg1"  ;;
  *) echo "Unknown region: $REGION"; exit 1 ;;
esac

# ── Region + Role → Plan mapping ──
PLAN=""
case "${REGION}-${ROLE}" in
  ashburn-server|hillsboro-server)   PLAN="cpx31" ;;  # CPX31 (8GB, 4vCPU)
  nuremberg-server|nuremberg-agent)  PLAN="cpx32" ;;  # CPX32 (8GB, 4vCPU) — EU-only
  ashburn-agent|hillsboro-agent)     PLAN="cpx31" ;;  # Same as server for symmetric HA
  *) echo "Unknown region/role: ${REGION}-${ROLE}"; exit 1 ;;
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
  --ssh-key john@arch \
  -o json \
  | jq -r '.server.id')

echo "  VM created: ${SERVER_ID}"

# Wait for IP
echo "  Waiting for IP..."
sleep 5
IP=$(hcloud server ip "${SERVER_ID}")
echo "  IP: ${IP}"

# ── Step 2: Get additional IPs for split-IP architecture ──
PROTECTED_IP="${IP}"
echo "  Protected IP: ${PROTECTED_IP}"

# Allocate a second floating IP for raw game/TS/DERP traffic
RAW_IP=""
if hcloud floating-ip list | grep -q "${HOSTNAME}" ; then
  RAW_IP_ID=$(hcloud floating-ip list -o json | jq -r '.[] | select(.description=="'"${HOSTNAME}-raw"'") | .id')
  echo "  Reusing existing raw IP ID: ${RAW_IP_ID}"
else
  RAW_IP_ID=$(hcloud floating-ip create \
    --description "${HOSTNAME}-raw" \
    --home-location "${LOCATION}" \
    --type ipv4 \
    -o json | jq -r '.floating_ip.id')
  hcloud floating-ip assign "${RAW_IP_ID}" "${SERVER_ID}"
  echo "  Raw IP created and assigned"
fi
# Get the actual raw IP for display
RAW_IP=$(hcloud floating-ip describe "${RAW_IP_ID}" -o json 2>/dev/null | jq -r '.floating_ip.ip // .ip // "unknown"')

# ── Step 3: Deploy NixOS via nixos-anywhere ──
echo "  [3/7] Deploying NixOS..."
nix run github:nix-community/nixos-anywhere -- \
  --flake "${FLAKE}" \
  --target-host "root@${IP}" \
  --build-on-remote

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

# Import pdns schema (needed before pdns can start)
if [[ "$ROLE" == "server" ]]; then
  PDNS_SCHEMA=$(ssh "root@${IP}" "find /nix/store -path '*/pdns*schema.mysql.sql' -not -name '*to_*' -not -name '*dnssec*' | head -1")
  ssh "root@${IP}" "mysql -u root --socket=/run/mysqld/mysqld.sock -e 'CREATE DATABASE IF NOT EXISTS pdns; DROP USER IF EXISTS \"pdns\"@\"localhost\"; CREATE USER \"pdns\"@\"localhost\" IDENTIFIED BY \"pdns\"; GRANT ALL PRIVILEGES ON pdns.* TO \"pdns\"@\"localhost\"; FLUSH PRIVILEGES;' 2>/dev/null"
  ssh "root@${IP}" "mysql -u pdns -ppdns pdns < ${PDNS_SCHEMA} 2>/dev/null || true"
  echo "    pdns schema imported"
fi

# ── Step 6: Connect tailscale ──
echo "  [6/7] Connecting tailscale..."
AUTHKEY=$(ssh "root@${IP}" "cat /run/agenix/hetzner/headscale-preauth-key 2>/dev/null" || echo "")
if [ -n "$AUTHKEY" ]; then
  ssh "root@${IP}" "systemctl restart tailscaled 2>/dev/null || true; sleep 3; tailscale up --reset --login-server=http://headscale.9s.pics:6767 --authkey=${AUTHKEY} --accept-routes 2>&1 || true"
  echo "    tailscale connected"
else
  echo "    WARNING: no preauth key found, tailscale not connected"
fi

# ── Step 7: Restart services and verify ──
echo "  [7/7] Restarting services..."
if [[ "$ROLE" == "server" ]]; then
  ssh "root@${IP}" "systemctl restart pdns 2>/dev/null || true"
  sleep 3
  echo "  --- Service Status ---"
  ssh "root@${IP}" "echo 'k3s:' \$(systemctl is-active k3s); echo 'mysql:' \$(systemctl is-active mysql); echo 'pdns:' \$(systemctl is-active pdns); echo 'tailscaled:' \$(systemctl is-active tailscaled)"
  ssh "root@${IP}" "kubectl get nodes 2>/dev/null" || echo "    (k3s not ready yet)"
  ssh "root@${IP}" "tailscale status 2>/dev/null" || echo "    (tailscale not connected yet)"
else
  ssh "root@${IP}" "systemctl is-active k3s-agent 2>/dev/null || echo 'inactive'"
fi

echo ""
echo "=== ${HOSTNAME} provisioned successfully ==="
echo "  IP: ${IP} | Raw IP: ${RAW_IP}"
echo "  SSH: ssh root@${IP}"
