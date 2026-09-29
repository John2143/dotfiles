#!/usr/bin/env bash
# desec-dns.sh — Manage deSEC DNS records for 9s.pics
#
# Usage:
#   desec-dns.sh set-a <name> <ip>                     # Set A record
#   desec-dns.sh set-ns <subdomain> <ns>               # Set NS record
#   desec-dns.sh list                                  # List all records
#   desec-dns.sh update-headscale                      # Update headscale.9s.pics to current public IP
#   desec-dns.sh update-all-nodes                      # Update headscale.9s.pics to current public IP
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



cmd_update_all_nodes() {
  cmd_update_headscale
}

# ── NS Delegation Setup (k8gb GSLB) ──
# One-time migration: deSEC wildcard A → NS delegation to self-hosted coredns.
# Must be run AFTER k8gb coredns is verified working on all 3 FIPs.
cmd_setup_ns_delegation() {
  echo "=== Setting up NS delegation for *.9s.pics → k8gb self-hosted DNS ==="
  echo ""
  echo "This creates 5 DNS records with 5-minute pauses between each."
  echo "WARNING: One-time migration. Verify coredns on all 3 FIPs first:"
  echo "  dig @5.161.19.201 test.9s.pics"
  echo "  dig @5.78.29.145 test.9s.pics"
  echo "  dig @5.161.19.197 test.9s.pics"
  echo ""
  read -rp "Proceed with NS delegation? (y/N) " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborting."
    exit 0
  fi

  # Step 1-3: Create ns1, ns2, ns3 A records
  local ips=("5.161.19.201" "5.78.29.145" "5.161.19.197")
  local names=("ns1" "ns2" "ns3")
  for i in 1 2 3; do
    echo "[$i/5] Creating ${names[$((i-1))]}.9s.pics A ${ips[$((i-1))]}..."
    cmd_set_a "${names[$((i-1))]}" "${ips[$((i-1))]}"
    echo "Sleeping 300s for deSEC rate limit..."
    sleep 300
  done

  # Step 4: Delete old wildcard A record
  echo "[4/5] Deleting *.9s.pics A record..."
  curl -sf -X DELETE -H "$AUTH" "$API/*/A/" 2>&1 || echo "    (record may already be absent)"
  echo "Sleeping 300s for deSEC rate limit..."
  sleep 300

  # Step 5: Create wildcard NS delegation
  echo "[5/5] Creating *.9s.pics NS ns1.9s.pics ns2.9s.pics ns3.9s.pics..."
  curl -sf -X PUT -H "$AUTH" -H "$CT" \
    "$API/*/NS/" \
    -d '{"records":["ns1.9s.pics.","ns2.9s.pics.","ns3.9s.pics."]}' 2>&1 | python3 -m json.tool

  echo ""
  echo "=== NS delegation complete ==="
  echo "Verify: dig @8.8.8.8 openfront.9s.pics"
  echo ""
  echo "Rollback if broken: $0 set-a '*' 5.161.19.201"
}

cmd_deploy_wildcard_cname() {
  echo "=== Deploying wildcard CNAME: *.9s.pics → gslb.9s.pics ==="
  echo ""
  echo "This sets up the zero-touch DNS architecture:"
  echo "  1. ns1/ns2/ns3 A records (glue for delegation)"
  echo "  2. gslb.9s.pics NS → ns1/ns2/ns3 (delegation to self-hosted coredns)"
  echo "  3. *.9s.pics CNAME → gslb.9s.pics (wildcard catch-all)"
  echo ""
  echo "After this, new app domains only need to be added to coredns zone.db."
  echo "No further deSEC API calls required for new subdomains."
  echo ""
  read -rp "Proceed? (y/N) " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborting."
    exit 0
  fi

  local ips=("5.161.19.201" "5.78.29.145" "5.161.19.197")
  local names=("ns1" "ns2" "ns3")

  # Step 1-3: Create ns1, ns2, ns3 A records
  for i in 1 2 3; do
    echo "[$i/6] Creating ${names[$((i-1))]}.9s.pics A ${ips[$((i-1))]}..."
    cmd_set_a "${names[$((i-1))]}" "${ips[$((i-1))]}"
    echo "Sleeping 300s for deSEC rate limit..."
    sleep 300
  done

  # Step 4: Delete old wildcard A record (if it exists)
  echo "[4/6] Deleting *.9s.pics A record (if present)..."
  curl -sf -X DELETE -H "$AUTH" "$API/*/A/" 2>&1 || echo "    (record may already be absent)"
  echo "Sleeping 300s for deSEC rate limit..."
  sleep 300

  # Step 5: Create gslb.9s.pics NS delegation
  echo "[5/6] Creating gslb.9s.pics NS → ns1 ns2 ns3..."
  curl -sf -X PUT -H "$AUTH" -H "$CT" \
    "$API/gslb/NS/" \
    -d '{"records":["ns1.9s.pics.","ns2.9s.pics.","ns3.9s.pics."]}' 2>&1 | python3 -m json.tool
  echo "Sleeping 300s for deSEC rate limit..."
  sleep 300

  # Step 6: Create wildcard CNAME
  echo "[6/6] Creating *.9s.pics CNAME gslb.9s.pics..."
  curl -sf -X PUT -H "$AUTH" -H "$CT" \
    "$API/*/CNAME/" \
    -d '{"records":["gslb.9s.pics."]}' 2>&1 | python3 -m json.tool

  echo ""
  echo "=== Wildcard CNAME deployed ==="
  echo "Verify: dig @8.8.8.8 some-random-name.9s.pics"
  echo ""
  echo "Rollback if broken: $0 set-a '*' 5.161.19.201"
}

cmd_verify_ns_delegation() {
  echo "=== Verifying *.9s.pics NS delegation ==="
  echo ""
  echo "--- NS records via 8.8.8.8 ---"
  dig +short NS 9s.pics @8.8.8.8 2>/dev/null || echo "(none)"
  echo ""
  echo "--- Nameserver A records ---"
  for ns in ns1 ns2 ns3; do
    echo -n "  ${ns}.9s.pics: "
    dig +short "${ns}.9s.pics" @8.8.8.8 2>/dev/null || echo "unresolved"
  done
  echo ""
  echo "--- *.9s.pics NS delegation chain ---"
  dig +short openfront.9s.pics @8.8.8.8 2>/dev/null || echo "(no records yet — k8gb Gslb not deployed)"
  echo ""
  echo "--- Direct to each coredns ---"
  for ip in 5.161.19.201 5.78.29.145 5.161.19.197; do
    echo -n "  $ip: "
    dig +short openfront.9s.pics @"$ip" 2>/dev/null || echo "unreachable"
  done
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
  setup-ns-delegation)
    cmd_setup_ns_delegation
    ;;
  verify-ns-delegation)
    cmd_verify_ns_delegation
    ;;
  deploy-wildcard-cname)
    cmd_deploy_wildcard_cname
    ;;

  update-headscale)
    cmd_update_headscale
    ;;
  update-all-nodes)
    cmd_update_all_nodes
    ;;
  *)
    echo "Usage: $0 {list|set-a|set-ns|setup-ns-delegation|deploy-wildcard-cname|verify-ns-delegation|update-headscale|update-all-nodes}"
    echo ""
    echo "  list                  List all DNS records for ${DOMAIN}"
    echo "  set-a NAME IP         Set A record (e.g. headscale → 108.56.153.222)"
    echo "  set-ns NAME NS        Set NS record"
    echo "  setup-ns-delegation   ONE-TIME: migrate wildcard A → NS delegation (k8gb)"
    echo "  deploy-wildcard-cname ONE-TIME: wildcard CNAME *.9s.pics → gslb.9s.pics"
    echo "  verify-ns-delegation  Check NS delegation and coredns health"
    echo "  update-headscale      Auto-detect public IP and update headscale.${DOMAIN}"
    echo "  update-all-nodes      Update headscale.${DOMAIN} to current public IP"

    exit 1
    ;;
esac
