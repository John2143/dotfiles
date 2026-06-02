# Hetzner CoreDNS Zone Generator — dynamic zone.db from Hetzner FIP API
#
# Runs every 60s. Queries hcloud for floating IPs by region label,
# renders a BIND zone file with all 3 FIPs per domain, and applies
# it as a Kubernetes ConfigMap. coredns picks it up with the reload plugin.
#
# No hardcoded IPs — reprovision a node, new FIP appears within 60s.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Generator script — Python, no external deps beyond hcloud and kubectl
  systemd.services.coredns-zone-generator = {
    description = "Generate coredns zone.db from Hetzner floating IPs";
    after = ["k3s.service" "floating-ip-health.service"];
    wants = ["k3s.service"];
    path = [pkgs.k3s pkgs.hcloud pkgs.python3];
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        # Domain → region mapping. Each domain resolves to all 3 FIPs.
        # headscale uses Tailscale MagicDNS IP (stable, not a FIP).
        'ZONE_CONFIG={"openfront":{"regions":["ashburn","hillsboro","nuremberg"]},"simulation-api":{"regions":["ashburn","hillsboro","nuremberg"]},"john2143":{"regions":["ashburn","hillsboro","nuremberg"]},"headscale":{"ip":"100.64.0.14","ttl":3600}}'
      ];
    };
    script = "${pkgs.python3}/bin/python3 ${../scripts/coredns-zone-generator.py}";
  };

  # Timer: every 60 seconds, staggered to not collide with floating-ip-health
  systemd.timers.coredns-zone-generator = {
    description = "Regenerate coredns zone.db every 60s";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/1";
      OnUnitInactiveSec = "60";
      Persistent = true;
    };
  };
}
