# Split-IP Firewall — per-IP iptables rules for DDoS blast radius containment
#
# Each node has two IPs, both detected at runtime:
#   Primary IP (Hetzner DHCP):  SSH + Tailscale only — locked down
#   Floating IP (Hetzner Cloud): DNS, HTTP/HTTPS, k3s API, CNPG, game servers
#
# Detection: primary = IP with default route; floating = the other IP on enp1s0.
# Falls back gracefully on single-IP nodes (one chain, SSH+Tailscale only).
{
  config,
  lib,
  pkgs,
  rawIP ? null,  # deprecated — detected at runtime; kept for backward compat
  ...
}: {
  systemd.services.split-ip-firewall = {
    description = "Split-IP iptables firewall (Primary vs Floating IP)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.iptables pkgs.iproute2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      # ── IP Detection ──
      # Primary IP: the one with the default route
      PRIMARY_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
      # All IPs on enp1s0 (Hetzner Cloud predictable interface name)
      ALL_IPS=$(ip -4 addr show enp1s0 2>/dev/null | grep -oP 'inet \K[\d.]+' || true)
      # Floating IP: the IP on enp1s0 that is NOT the primary
      FLOATING_IP=$(echo "$ALL_IPS" | grep -v "$PRIMARY_IP" | head -1 || true)

      if [ -z "$PRIMARY_IP" ]; then
        echo "WARNING: Could not detect primary IP, skipping firewall"
        exit 0
      fi

      echo "Primary IP:  $PRIMARY_IP"
      echo "Floating IP: ''${FLOATING_IP:-none (single-IP mode)}"

      # ── Primary IP chain ──
      # Locked down: only SSH + Tailscale + loopback + established
      iptables -N PRIMARY_IN 2>/dev/null || iptables -F PRIMARY_IN

      iptables -A PRIMARY_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A PRIMARY_IN -i lo -j ACCEPT
      iptables -A PRIMARY_IN -i tailscale0 -j ACCEPT
      iptables -A PRIMARY_IN -p tcp --dport 22 -j ACCEPT
      iptables -A PRIMARY_IN -j DROP

      iptables -D INPUT -d "$PRIMARY_IP" -j PRIMARY_IN 2>/dev/null || true
      iptables -I INPUT -d "$PRIMARY_IP" -j PRIMARY_IN

      # ── Floating IP chain (only if dual-IP) ──
      if [ -n "$FLOATING_IP" ]; then
        iptables -N FLOATING_IN 2>/dev/null || iptables -F FLOATING_IN

        iptables -A FLOATING_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A FLOATING_IN -i lo -j ACCEPT
        iptables -A FLOATING_IN -i tailscale0 -j ACCEPT

        # SSH (management)
        iptables -A FLOATING_IN -p tcp --dport 22 -j ACCEPT

        # DNS (PowerDNS authoritative + resolver)
        iptables -A FLOATING_IN -p tcp --dport 53 -j ACCEPT
        iptables -A FLOATING_IN -p udp --dport 53 -j ACCEPT

        # HTTP/HTTPS (k3s ingress via Traefik)
        iptables -A FLOATING_IN -p tcp --dport 80  -j ACCEPT
        iptables -A FLOATING_IN -p tcp --dport 443 -j ACCEPT

        # k3s API server
        iptables -A FLOATING_IN -p tcp --dport 6443 -j ACCEPT

        # CNPG PostgreSQL NodePort
        iptables -A FLOATING_IN -p tcp --dport 30432 -j ACCEPT

        # Game servers / DERP / TeamSpeak
        iptables -A FLOATING_IN -p udp --dport 3478  -j ACCEPT  # STUN/DERP
        iptables -A FLOATING_IN -p udp --dport 9987  -j ACCEPT  # TeamSpeak voice
        iptables -A FLOATING_IN -p tcp --dport 30033 -j ACCEPT  # TeamSpeak file
        iptables -A FLOATING_IN -p tcp --dport 8080  -j ACCEPT  # DERP/other

        # SYN rate limiting for HTTP/HTTPS on floating IP
        iptables -A FLOATING_IN -p tcp --dport 80  --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT
        iptables -A FLOATING_IN -p tcp --dport 443 --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT

        iptables -A FLOATING_IN -j DROP
        iptables -D INPUT -d "$FLOATING_IP" -j FLOATING_IN 2>/dev/null || true
        iptables -I INPUT -d "$FLOATING_IP" -j FLOATING_IN
      fi

      echo "Split-IP firewall applied."
    '';
  };
}
