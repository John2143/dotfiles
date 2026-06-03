# k3s Server Module — shared config for all 3 control-plane nodes (closet, arch, nas).
#
# This module assumes:
#   - closet runs --cluster-init (embedded etcd bootstrap)
#   - arch + nas join via --server https://closet.local:6443
#   - All three advertise 192.168.5.0/24 as a tailscale subnet route for kube-vip VIP.
#
# Every server node imports this identically. Node-specific flags
# (--node-ip, --cluster-init, --server, dual-stack CIDRs) go in the
# host configuration.nix as `services.k3s.extraFlags`.
{
  config,
  lib,
  ...
}: {
  imports = [
    ./longhorn-host.nix
  ];

  options.custom.k3sStorageAfter = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Systemd units that must remain active during k3s shutdown (e.g. storage mounts backing Longhorn).";
  };

  options.custom.k3sNodeTaints = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Node taints for the k3s server node.";
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
      role = "server";
      tokenFile = config.age.secrets.k3s-local-token.path;
    };

    # Tailscale subnet route — advertises LAN to tailnet so tailscale
    # clients can reach the kube-vip VIP (192.168.5.10) for k8s services.
    # Approved in headscale admin UI per-node.
    services.tailscale.extraUpFlags = [ "--advertise-routes=192.168.5.0/24" ];

    # k3s needs avahi for mDNS server discovery (closet.local, arch.local, nas.local)
    systemd.services.k3s = {
      after = [ "avahi-daemon.service" "tailscaled.service" ] ++ config.custom.k3sStorageAfter;
      wants = [ "avahi-daemon.service" ];
    };

    networking.firewall.allowedTCPPorts = [
      6443   # k3s API server
      10250  # kubelet
      2379   # etcd client (k3s server-to-server)
      2380   # etcd peer (k3s server-to-server)
    ];
    networking.firewall.allowedUDPPorts = [
      8472   # k3s flannel VXLAN
    ];
    networking.firewall.allowedTCPPortRanges = [
      { from = 30000; to = 32767; }  # NodePort range
    ];
  };
}
