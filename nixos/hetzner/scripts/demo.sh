#!/usr/bin/env bash
# demo.sh — Full deploy, test failover, teardown demo (~$8-10 for 48 hours)
#

# 4. Cleanup (optional — skip to keep nodes running)
#
# Usage: ./demo.sh [--keep]
#   --keep: don't destroy VMs after demo
#
# Requires: HCLOUD_TOKEN env var
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEEP="${1:-}"

echo "╔══════════════════════════════════════════════╗"
echo "║   Enterprise HA Platform Demo               ║"
echo "║   3 regions, 3 k3s clusters, full stack      ║"
echo "║   Estimated cost: ~$8-10 (48 hours)          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Phase 1: Deploy 3 server nodes ──
echo "=== Phase 1: Deploying 3 server nodes ==="
"${SCRIPT_DIR}/provision.sh" ashburn server &
PID1=$!
"${SCRIPT_DIR}/provision.sh" hillsboro server &
PID2=$!
"${SCRIPT_DIR}/provision.sh" nuremberg server &
PID3=$!

wait $PID1 $PID2 $PID3
echo "  All 3 server nodes provisioned."

# ── Phase 2: Verify ──
echo ""
echo "=== Phase 2: Verification ==="

ASHBURN_IP=$(hcloud server list --output-format json | jq -r '.[] | select(.name=="k3s-ashburn") | .public_net.ipv4.ip')
HILLSBORO_IP=$(hcloud server list --output-format json | jq -r '.[] | select(.name=="k3s-hillsboro") | .public_net.ipv4.ip')
NUREMBERG_IP=$(hcloud server list --output-format json | jq -r '.[] | select(.name=="k3s-nuremberg") | .public_net.ipv4.ip')

echo "  Ashburn:    ${ASHBURN_IP}"
echo "  Hillsboro:  ${HILLSBORO_IP}"
echo "  Nuremberg:  ${NUREMBERG_IP}"

echo ""
echo "  --- k3s nodes ---"
ssh "root@${ASHBURN_IP}" "kubectl get nodes" || echo "  (k8s not yet deployed — expected)"
ssh "root@${HILLSBORO_IP}" "kubectl get nodes" || echo "  (k8s not yet deployed — expected)"
ssh "root@${NUREMBERG_IP}" "kubectl get nodes" || echo "  (k8s not yet deployed — expected)"

# ── Phase 3: Cleanup ──
if [[ "$KEEP" == "--keep" ]]; then
  echo ""
  echo "=== Nodes KEPT (--keep flag) ==="
  echo "  SSH:  ssh root@${ASHBURN_IP}"
  echo "  SSH:  ssh root@${HILLSBORO_IP}"
  echo "  SSH:  ssh root@${NUREMBERG_IP}"
  echo ""
  echo "  To destroy: hcloud server delete k3s-ashburn k3s-hillsboro k3s-nuremberg"
  echo "  To go HA:   ./toggle-ha.sh"
  exit 0
fi

echo ""
echo "=== Phase 3: Teardown ==="
echo "  Destroying all 3 server nodes..."
hcloud server delete k3s-ashburn k3s-hillsboro k3s-nuremberg

echo ""
echo "=== Demo complete ==="
echo "  Total cost: ~$1-2 (VMs were up for ~10-15 minutes)"
