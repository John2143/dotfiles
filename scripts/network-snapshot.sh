#!/usr/bin/env bash
# Print live network state as markdown, for diffing against the network-engineer skill docs.
# Read-only. If mikrotik-connect is missing, each section fails independently.
set -uo pipefail

r() { mikrotik-connect r "$1" 2>/dev/null || echo "(router unreachable)"; }

echo "# Live network snapshot"
echo
echo "Generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') — compare against"
echo "\`.claude/skills/network-engineer/*.md\` and update what moved."
echo
echo "## DHCP leases (5.0/24 and 1.0/24)"
echo '```'
r '/ip dhcp-server lease print terse where status=bound' | awk '{a="";h="";for(i=1;i<=NF;i++){if($i~/^address=/){a=substr($i,9)}else if($i~/^host-name=/){h=substr($i,11)}} if(a!="") printf "%s %s\n",a,h}'
echo '```'
echo
echo "## ARP (reachable)"
echo '```'
r '/ip arp print terse where status=reachable' | sed -n 's/.*address=\([0-9.]*\).*mac-address=\([0-9A-F:]*\).*/\1 \2/p'
echo '```'
echo
echo "## dst-nat rules"
echo '```'
r '/ip firewall nat print terse where chain=dstnat'
echo '```'
echo
echo "## IPv6 addresses"
echo '```'
r '/ipv6 address print terse'
echo '```'
echo
echo "## BGP sessions"
echo '```'
r '/routing bgp session print'
echo '```'
echo
echo "## Interface state"
echo '```'
r '/interface print terse where running'
echo '```'
