#!/usr/bin/env bash
# desec-dns.sh — Manage deSEC DNS records for 9s.pics
#
# Usage:
#   desec-dns.sh bootstrap-dns <region> <floating-ip>  # Set NS + glue A records
#   desec-dns.sh set-a <name> <ip>                     # Set A record
#   desec-dns.sh set-ns <subdomain> <ns>               # Set NS record
#   desec-dns.sh list                                  # List all records
#   desec-dns.sh update-headscale                      # Update headscale.9s.pics to current public IP
#   desec-dns.sh update-all-nodes [<ashburn-floating> <hillsboro-floating> <nuremberg-floating>]
#
# Requires: DESEC_TOKEN env var or agenix secret at ../secrets/hetzner/desec-token.age

set -euo pipefail

DOMAIN="9s.pics"
API="https://desec.io/api/v1/domains/${DOMAIN}/rrsets"

# Region → NS hostname mapping
declare -A REGION_TO_NS=(
  [ashburn]=ns1
  [hillsboro]=ns2
  [nuremberg]=ns3
)

# NS hostnames (in order)
NS_HOSTNAMES=(ns1 ns2 ns3)

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
  # Try PATCH (update existing), fall back to POST (create new)
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H "$AUTH" -H "$CT" "$API/${subname}/A/" -d "{\"records\":[\"${ip}\"]}")
  if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
    curl -sf -X PATCH -H "$AUTH" -H "$CT" "$API/${subname}/A/" -d "{\"records\":[\"${ip}\"]}" | python3 -m json.tool
  else
    curl -sf -X POST -H "$AUTH" -H "$CT" "$API/" -d "{\"subname\":\"${subname}\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"${ip}\"]}" | python3 -m json.tool
  fi
}

cmd_set_ns() {
  local subname="$1" nameserver="$2"
  echo "Setting NS record: ${subname}.${DOMAIN} → ${nameserver}"
  curl -sf -X PUT -H "$AUTH" -H "$CT" \
    "$API/${subname}/NS/" \
    -d "{\"records\":[\"${nameserver}.\"]}" | python3 -m json.tool
}

cmd_update_headscale() {
  local ip
  ip=$(curl -4sf --connect-timeout 10 ifconfig.me 2>/dev/null || curl -4sf --connect-timeout 10 icanhazip.com 2>/dev/null)
  if [ -z "$ip" ]; then
    echo "ERROR: Could not determine public IP"
    exit 1
  fi
  cmd_set_a "headscale" "$ip"
}

cmd_bootstrap_dns() {
  # Set glue A record for this node.
  #
  # Called once per node during provisioning.
  #   desec-dns.sh bootstrap-dns <region> <floating-ip>
  local region="$1" floating_ip="$2"
  local ns_hostname="${REGION_TO_NS[$region]:-}"
  if [ -z "$ns_hostname" ]; then
    echo "ERROR: Unknown region '$region'. Valid: ashburn, hillsboro, nuremberg"
    exit 1
  fi

  echo "=== deSEC DNS bootstrap: region=$region ns=$ns_hostname floating=$floating_ip ==="

  # ── Glue A record: nsN.9s.pics → floating IP ──
  cmd_set_a "$ns_hostname" "$floating_ip"

}

cmd_update_all_nodes() {
  # Update A records for k3s nodes and headscale.
  # Accepts 3 optional floating IPs; falls back to hcloud API query.
  local ashburn_ip="${1:-}"
  local hillsboro_ip="${2:-}"
  local nuremberg_ip="${3:-}"

  # If no IPs provided on command line, query Hetzner API
  if [ -z "$ashburn_ip" ] || [ -z "$hillsboro_ip" ] || [ -z "$nuremberg_ip" ]; then
    if command -v hcloud &>/dev/null && [ -n "${HCLOUD_TOKEN:-}" ]; then
      echo "Querying Hetzner API for floating IPs..."
      while IFS== read -r desc ip; do
        case "$desc" in
          k3s-ashburn-raw)   ashburn_ip="${ashburn_ip:-$ip}" ;;
          k3s-hillsboro-raw) hillsboro_ip="${hillsboro_ip:-$ip}" ;;
          k3s-nuremberg-raw) nuremberg_ip="${nuremberg_ip:-$ip}" ;;
        esac
      done < <(hcloud floating-ip list -o json 2>/dev/null | \
        python3 -c "import sys,json; [print(f'{f[\"description\"]}={f[\"ip\"]}') for f in json.load(sys.stdin) if 'k3s-' in f.get('description','')]")
    fi
  fi

  if [ -n "$ashburn_ip" ]; then
    cmd_set_a "k3s-ashburn" "$ashburn_ip"
  else
    echo "SKIP: k3s-ashburn (no floating IP provided)"
  fi
  if [ -n "$hillsboro_ip" ]; then
    cmd_set_a "k3s-hillsboro" "$hillsboro_ip"
  else
    echo "SKIP: k3s-hillsboro (no floating IP provided)"
  fi
  if [ -n "$nuremberg_ip" ]; then
    cmd_set_a "k3s-nuremberg" "$nuremberg_ip"
  else
    echo "SKIP: k3s-nuremberg (no floating IP provided)"
  fi

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
  bootstrap-dns)
    [ $# -eq 3 ] || { echo "Usage: $0 bootstrap-dns <ashburn|hillsboro|nuremberg> <floating-ip>"; exit 1; }
    cmd_bootstrap_dns "$2" "$3"
    ;;
  update-headscale)
    cmd_update_headscale
    ;;
  update-all-nodes)
    shift
    cmd_update_all_nodes "$@"
    ;;
  *)
    echo "Usage: $0 {list|set-a|set-ns|bootstrap-dns|update-headscale|update-all-nodes}"
    echo ""
    echo "  list               List all DNS records for ${DOMAIN}"
    echo "  set-a NAME IP      Set A record (e.g. headscale → 108.56.153.222)"
    echo "  set-ns NAME NS     Set NS record"
    echo "  bootstrap-dns REGION FLOATING-IP  Set NS + glue A for deSEC delegation"
    echo "  update-headscale   Auto-detect public IP and update headscale.${DOMAIN}"
    echo "  update-all-nodes [FLOATING_ASBURN FLOATING_HILLSBORO FLOATING_NUREMBERG]"
    echo "                     Update all node A records + headscale"
    exit 1
    ;;
esac
