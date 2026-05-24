# Split-IP Firewall — per-interface iptables rules for DDoS blast radius containment
#
# Each node has two IPs:
#   Protected IP (primary): Web apps, DNS, k3s API, CNPG NodePort — strict whitelist + SYN rate limiting
#   Raw IP (floating):      Game servers, DERP, TeamSpeak — per-service port whitelist
#
# The raw IP is resolved from deSEC DNS at runtime: <region>-raw.9s.pics
# Region is derived from compName: k3s-ashburn → ash-raw.9s.pics
#
# An attack on one IP cannot affect services on the other.
# Floating IP can be rotated without touching the Protected IP — just update DNS.
{
  config,
  lib,
  pkgs,
  compName ? "unknown",
  ...
}: let
  # Derive raw DNS name from compName
  # k3s-ashburn → ash, k3s-hillsboro → hil, k3s-nuremberg → nur
  region = if builtins.stringLength compName > 4
    then builtins.substring (builtins.stringLength compName - 3) 3 compName  # last 3 chars
    else "---";
  rawDNS = "${region}-raw.9s.pics";
in {
  systemd.services.split-ip-firewall = {
    description = "Split-IP iptables firewall (Protected vs Raw IP)";
    after = ["network.target"];
    wants = ["network.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.iptables pkgs.bind];  # bind for 'host' command
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      PROTECTED_IP=$(hostname -I | awk '{print $1}')
      RAW_IP=$(host ${rawDNS} 2>/dev/null | awk '/has address/ {print $NF; exit}')

      if [ -z "$RAW_IP" ]; then
        echo "WARNING: Could not resolve ${rawDNS}, skipping raw IP firewall"
        exit 0
      fi

      echo "Protected IP: $PROTECTED_IP"
      echo "Raw IP: $RAW_IP (${rawDNS})"

      # === Protected IP (per-destination) ===
      iptables -N PROTECTED_IN 2>/dev/null || iptables -F PROTECTED_IN

      iptables -A PROTECTED_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A PROTECTED_IN -i lo -j ACCEPT
      iptables -A PROTECTED_IN -i tailscale0 -j ACCEPT

      iptables -A PROTECTED_IN -p tcp --dport 22   -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 53   -j ACCEPT
      iptables -A PROTECTED_IN -p udp --dport 53   -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 80   -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 443  -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 6443 -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 30432 -j ACCEPT

      # SYN rate limiting
      iptables -A PROTECTED_IN -p tcp --dport 80  --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT
      iptables -A PROTECTED_IN -p tcp --dport 443 --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT

      iptables -A PROTECTED_IN -j DROP
      iptables -D INPUT -d "$PROTECTED_IP" -j PROTECTED_IN 2>/dev/null || true
      iptables -I INPUT -d "$PROTECTED_IP" -j PROTECTED_IN

      # === Raw IP (per-destination) ===
      iptables -N RAW_IN 2>/dev/null || iptables -F RAW_IN

      iptables -A RAW_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A RAW_IN -i lo -j ACCEPT
      iptables -A RAW_IN -i tailscale0 -j ACCEPT

      iptables -A RAW_IN -p tcp --dport 22 -j ACCEPT
      iptables -A RAW_IN -p udp --dport 3478 -j ACCEPT
      iptables -A RAW_IN -p udp --dport 9987 -j ACCEPT
      iptables -A RAW_IN -p tcp --dport 30033 -j ACCEPT
      iptables -A RAW_IN -p tcp --dport 8080 -j ACCEPT

      iptables -A RAW_IN -j DROP
      iptables -D INPUT -d "$RAW_IP" -j RAW_IN 2>/dev/null || true
      iptables -I INPUT -d "$RAW_IP" -j RAW_IN

      echo "Split-IP firewall applied."
    '';
  };
}
