# CoreDNS Zone Generator — dynamic zone.db from multi-cloud FIP registry
#
# Runs every 60s. Reads FIP registry from Kubernetes ConfigMap (populated
# by deploy_all.py at provisioning time), renders a BIND zone file, and
# applies it as a Kubernetes ConfigMap. coredns picks it up with the reload
# plugin.
#
# Cloud-agnostic: no cloud API calls needed. Adding a new cloud region
# just means the FIP registry ConfigMap gets updated.
#
# No hardcoded IPs — reprovision a node, new FIP appears within 60s.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Generator script — reads FIP registry from Kubernetes ConfigMap (no cloud API)
  systemd.services.coredns-zone-generator = {
    description = "Generate coredns zone.db from multi-cloud FIP registry";
    after = ["k3s.service"];
    wants = ["k3s.service"];
    path = [pkgs.k3s pkgs.python3 pkgs.bind];
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        "FIP_CONFIGMAP=fip-registry"
        "FIP_NAMESPACE=k8gb"
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
