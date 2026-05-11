#!/usr/bin/env bash
# toggle-la.sh — Drain and destroy all 3 agent nodes for Low Availability mode
#
# Gracefully drains agent nodes, then destroys the VMs via Hetzner API.
# Server nodes continue running. Stateful workloads stay on servers.
#
# Usage: ./toggle-la.sh
#
# Requires: HCLOUD_TOKEN env var
set -euo pipefail

echo "=== Toggling LA mode: draining and destroying 3 agent nodes ==="

destroy_agent() {
  local region="$1"
  local hostname="k3s-${region}-agent"

  echo ""
  echo "--- ${hostname} ---"

  # Get IP (try cached/saved, or lookup via hcloud)
  local ip
  ip=$(hcloud server list --output-format json | jq -r '.[] | select(.name=="'"${hostname}"'") | .public_net.ipv4.ip' 2>/dev/null || echo "")

  if [[ -z "${ip}" ]]; then
    echo "  ${hostname}: VM not found in Hetzner. Already destroyed?"
    return 0
  fi

  echo "  [1/3] Draining node..."
  ssh "root@${ip}" "kubectl drain ${hostname} --delete-emptydir-data --ignore-daemonsets --timeout=120s" || true

  echo "  [2/3] Destroying VM..."
  local server_id
  server_id=$(hcloud server list --output-format json | jq -r '.[] | select(.name=="'"${hostname}"'") | .id')
  hcloud server delete "${server_id}"

  echo "  [3/3] Releasing floating IPs..."
  hcloud floating-ip list --output-format json | \
    jq -r '.[] | select(.description=="'"${hostname}-raw"'") | .id' | \
    xargs -r hcloud floating-ip delete

  echo "  ${hostname}: drained and destroyed."
}

destroy_agent "ashburn"
destroy_agent "hillsboro"
destroy_agent "nuremberg"

echo ""
echo "=== LA Mode Active ==="
echo "3 server nodes only (~$75/mo). Agent nodes destroyed."
echo ""
echo "To restore HA: ./toggle-ha.sh"
