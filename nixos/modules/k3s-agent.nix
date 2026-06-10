{
  config,
  lib,
  ...
}: {
  imports = [./longhorn-host.nix];

  options.custom.k3sNodeTaints = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Node taints to apply when the k3s agent first registers.";
    example = ["seated=true:NoSchedule"];
  };

  config = {
    age.secrets.k3s-local-token = {
      file = ../../secrets/k3s-local-token.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://192.168.5.10:6443";
      tokenFile = config.age.secrets.k3s-local-token.path;
    };
    # Agent needs avahi to resolve .local server hostnames
    systemd.services.k3s = {
      after = [ "avahi-daemon.service" ];
      wants = [ "avahi-daemon.service" ];
      environment.K3S_RESOLV_CONF = "/etc/rancher/k3s/resolv.conf";
      serviceConfig = {
        TimeoutStopSec = lib.mkForce "10s";
      };
    };
    # Clean resolv.conf for k3s pods — strips the Tailscale MagicDNS search
    # domain (ts.2143.me) to prevent ndots:5 expansion from prepending it
    # to external hostnames. Keeps 100.100.100.100 as the upstream so pods
    # can still resolve tailnet names (nas.ts.2143.me, etc.) via MagicDNS.
    environment.etc."rancher/k3s/resolv.conf".text = ''
      nameserver 100.100.100.100
    '';


    # Prevent systemd-networkd from flushing custom ip rules created by
    # external tools (like our pod-CIDR routing fix below). Without this,
    # systemd-networkd removes rules it doesn't know about on restart.
    systemd.network.config.networkConf."ManageForeignRoutingPolicyRules" = "no";

    # Add an ip rule that directs pod CIDR traffic to the main routing table
    # BEFORE Tailscale's rule 5270 sends everything to table 52.
    #
    # Without this, Tailscale's `default dev tailscale0` in table 52 captures
    # pod-to-pod traffic between k3s nodes (because Tailscale's `throw` entries
    # only cover the local node's /24 on cni0, not remote pod CIDRs reached
    # via flannel.1). The result: cross-node pod networking silently fails.
    #
    # Priority 2500 is safely below Tailscale's range (5200-5500), so this rule
    # fires before Tailscale's table 52 lookup at rule 5270.
    # The `to 10.42.0.0/16` narrows it to k3s pod traffic only — non-pod traffic
    # falls through to Tailscale's rules as normal.
    #
    # See research: ai_research/what-is-the-best-way-to-run-a-kubernetes-node-on-a-computer-that/final_report.md
    networking.iproute2 = {
      enable = true;
      rules = [
        "priority 2500 from all to 10.42.0.0/16 lookup main"
      ];
    };
  };
}
