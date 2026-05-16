#!/usr/bin/env bash
# provision.sh — Create Hetzner VM and deploy NixOS via nixos-anywhere
#
# Usage: ./provision.sh <region> <role>
#   region: ashburn | hillsboro | nuremberg
#   role:   server  | agent
#
# Requires: HCLOUD_TOKEN env var, hcloud CLI, nixos-anywhere
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
echo "  [1/4] Creating VM..."
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
echo "  [2/4] Deploying NixOS..."
nix run github:nix-community/nixos-anywhere -- \
  --flake "${FLAKE}" \
  --target-host "root@${IP}" \
  --build-on-remote

echo "  [3/4] Waiting for SSH..."
sleep 10
ssh "root@${IP}" "echo '  NixOS booted. Hostname: '\$(hostname)"

# ── Step 4: Verify ──
echo "  [4/4] Verification..."

if [[ "$ROLE" == "server" ]]; then
  ssh "root@${IP}" "systemctl is-active k3s pdns mariadb"
  ssh "root@${IP}" "kubectl get nodes"
  echo "  Server ${HOSTNAME}: k3s + PowerDNS + MariaDB — all active"
else
  ssh "root@${IP}" "systemctl is-active k3s-agent"
  echo "  Agent ${HOSTNAME}: k3s agent — joined cluster"
fi

echo ""
echo "=== ${HOSTNAME} provisioned successfully ==="
echo "  IP: ${IP} | Raw IP: ${RAW_IP}"
echo "  SSH: ssh root@${IP}"
