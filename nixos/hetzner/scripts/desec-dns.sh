#!/usr/bin/env bash
# desec-dns.sh — Manage deSEC DNS records for 9s.pics
#
# Usage:
#   desec-dns.sh set-a <name> <ip>        # Set A record (e.g. headscale → 108.56.153.222)
#   desec-dns.sh set-ns <subdomain> <ns>  # Set NS record
#   desec-dns.sh list                     # List all records
#   desec-dns.sh update-headscale         # Update headscale.9s.pics to current public IP
#
# Requires: DESEC_TOKEN env var or agenix secret at ../secrets/hetzner/desec-token.age

set -euo pipefail

DOMAIN="9s.pics"
API="https://desec.io/api/v1/domains/${DOMAIN}/rrsets"

# Get token from env or agenix
if [ -z "${DESEC_TOKEN:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "${SCRIPT_DIR}/../secrets/hetzner/desec-token.age" ]; then
    DESEC_TOKEN=$(cd "${SCRIPT_DIR}/../secrets" && agenix -d "hetzner/desec-token.age" -i ~/.ssh/age 2>/dev/null | tr -d '\n')
  fi
fi

if [ -z "${DESEC_TOKEN:-}" ]; then
  echo "ERROR: DESEC_TOKEN not set and cannot decrypt from agenix."
  echo "Set it via: export DESEC_TOKEN=your-token"
  echo "Or encrypt via: echo -n 'token' | agenix -e ../secrets/hetzner/desec-token.age -i ~/.ssh/age"
  exit 1
fi

AUTH="Authorization: Token ${DESEC_TOKEN}"
CT="Content-Type: application/json"

cmd_list() {
  curl -sf -H "$AUTH" "$API/" | python3 -m json.tool
}

cmd_set_a() {
  local subname="$1" ip="$2"
  local full="${subname}.${DOMAIN}"
  echo "Setting A record: ${full} → ${ip}"
  curl -sf -X PATCH -H "$AUTH" -H "$CT" \
    "$API/${subname}/A/" \
    -d "{\"records\":[\"${ip}\"]}" | python3 -m json.tool
}

cmd_set_ns() {
  local subname="$1" nameserver="$2"
  local full="${subname}.${DOMAIN}"
  echo "Setting NS record: ${subname}.${DOMAIN} → ${nameserver}"
  curl -sf -X PATCH -H "$AUTH" -H "$CT" \
    "$API/${subname}/NS/" \
    -d "{\"records\":[\"${nameserver}.\"]}" | python3 -m json.tool
}

cmd_update_headscale() {
  local ip
  ip=$(curl -sf ifconfig.me 2>/dev/null || curl -sf icanhazip.com 2>/dev/null)
  if [ -z "$ip" ]; then
    echo "ERROR: Could not determine public IP"
    exit 1
  fi
  cmd_set_a "headscale" "$ip"
}

cmd_update_all_nodes() {
  # Update A records for all 3 k3s nodes and headscale
  # Node IPs are hardcoded — update if VMs are reprovisioned
  cmd_set_a "k3s-ashburn"   "5.161.100.206"
  cmd_set_a "k3s-hillsboro" "5.78.186.134"
  cmd_set_a "k3s-nuremberg" "178.156.133.181"
  cmd_update_headscale
}

case "${1:-}" in
  list)
    cmd_list
    ;;
  set-a)
    [ $# -eq 3 ] || { echo "Usage: $0 set-a <subdomain> <ip>"; exit 1; }
    cmd_set_a "$2" "$3"
    ;;
  set-ns)
    [ $# -eq 3 ] || { echo "Usage: $0 set-ns <subdomain> <nameserver>"; exit 1; }
    cmd_set_ns "$2" "$3"
    ;;
  update-headscale)
    cmd_update_headscale
    ;;
  update-all-nodes)
    cmd_update_all_nodes
    ;;
  *)
    echo "Usage: $0 {list|set-a|set-ns|update-headscale|update-all-nodes}"
    echo ""
    echo "  list               List all DNS records for ${DOMAIN}"
    echo "  set-a NAME IP      Set A record (e.g. headscale → 108.56.153.222)"
    echo "  set-ns NAME NS     Set NS record"
    echo "  update-headscale   Auto-detect public IP and update headscale.${DOMAIN}"
    echo "  update-all-nodes   Update all node A records + headscale"
    exit 1
    ;;
esac
