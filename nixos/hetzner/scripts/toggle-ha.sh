#!/usr/bin/env bash
# toggle-ha.sh — Provision all 3 agent nodes for High Availability mode
#
# Deploys the agent nodes that were previously destroyed (or never provisioned).
# Agents join the existing k3s clusters. ArgoCD deploys workloads automatically.
#
# Usage: ./toggle-ha.sh
#
# Requires: HCLOUD_TOKEN env var
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Toggling HA mode: provisioning 3 agent nodes ==="

echo ""
echo "--- Ashburn agent ---"
"${SCRIPT_DIR}/provision.sh" ashburn agent

echo ""
echo "--- Hillsboro agent ---"
"${SCRIPT_DIR}/provision.sh" hillsboro agent

echo ""
echo "--- Nuremberg agent ---"
"${SCRIPT_DIR}/provision.sh" nuremberg agent

echo ""
echo "=== HA Mode Active ==="
echo "3 server nodes + 3 agent nodes = 6 nodes total (~$140/mo)"
echo ""
echo "Verification:"
echo "  kubectl get nodes    # should show 2 nodes per region"
echo "  kubectl get pods -A  # ArgoCD should be deploying workloads"
