# k3s node networking in one place: node-ip derivation (including MAC-derived
# EUI-64), the dual-stack cluster CIDRs, tls-sans, crash-recovery tuning and the
# sysctls every node needs. Hosts declare `custom.k3sNet` and nothing else.
{
  config,
  lib,
  ...
}: let
  cfg = config.custom.k3sNet;

  # lib.toHexString is uppercase and does not zero-pad, so normalise first.
  hex = n: let
    s = lib.toLower (lib.toHexString n);
  in
    if lib.stringLength s == 1 then "0" + s else s;

  # EUI-64 interface identifier: flip the U/L bit, insert ff:fe.
  # "98:b7:85:23:48:90" -> "9ab7:85ff:fe23:4890"
  eui64 = prefix: mac: let
    o = map (h: lib.fromHexString h) (lib.splitString ":" (lib.toLower mac));
    iid = [
      (lib.bitXor (lib.elemAt o 0) 2)
      (lib.elemAt o 1)
      (lib.elemAt o 2)
      255
      254
      (lib.elemAt o 3)
      (lib.elemAt o 4)
      (lib.elemAt o 5)
    ];
    word = i: hex (lib.elemAt iid (i * 2)) + hex (lib.elemAt iid (i * 2 + 1));
  in
    prefix + lib.concatMapStringsSep ":" word [ 0 1 2 3 ];

  ipv6 =
    if cfg.ipv6Mac != null
    then eui64 cfg.ipv6Prefix cfg.ipv6Mac
    else cfg.ipv6;

  common =
    ["--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.ip_forward,net.ipv6.conf.all.forwarding"]
    ++ lib.optional (cfg.systemReserved != null) "--kubelet-arg=system-reserved=${cfg.systemReserved}"
    ++ map (l: "--node-label=${l}") cfg.nodeLabels
    ++ lib.optional (cfg.ipv4 != null) "--node-ip=${cfg.ipv4},${ipv6}";

  server =
    [
      "--disable=servicelb"
      "--cluster-cidr=${cfg.clusterCidr}"
      "--service-cidr=${cfg.serviceCidr}"
      "--flannel-ipv6-masq"
      "--etcd-expose-metrics"
      "--kube-apiserver-arg=default-not-ready-toleration-seconds=40"
      "--kube-apiserver-arg=default-unreachable-toleration-seconds=40"
      "--kube-controller-manager-arg=node-monitor-grace-period=20s"
      "--kube-controller-manager-arg=node-monitor-period=2s"
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
    ]
    ++ map (n: "--tls-san=${n}") (lib.unique (
      ["${config.networking.hostName}.local" cfg.apiVip]
      ++ lib.optional (cfg.ipv4 != null) cfg.ipv4
      ++ map (n: "${n}.local") cfg.serverNames
      ++ cfg.extraTlsSans
    ));
in {
  options.custom.k3sNet = {
    ipv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LAN IPv4 of this node, or null to leave --node-ip unset (k3s autodetects; agents only).";
    };
    ipv6 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Explicit IPv6 node address. Alternative to ipv6Mac.";
    };
    ipv6Mac = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "NIC MAC whose EUI-64 form under ipv6Prefix becomes the IPv6 node address.";
    };
    ipv6Prefix = lib.mkOption {
      type = lib.types.str;
      default = "fd00:1::";
      description = "Prefix the router advertises; the EUI-64 IID is appended to it.";
    };
    apiVip = lib.mkOption {
      type = lib.types.str;
      default = "192.168.5.10";
      description = "MetalLB VIP the API server is reached on.";
    };
    serverNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["closet" "arch" "nas"];
      description = "Control-plane hostnames; each becomes a tls-san.";
    };
    clusterCidr = lib.mkOption {
      type = lib.types.str;
      default = "10.42.0.0/16,fd42:42:42::/56";
    };
    serviceCidr = lib.mkOption {
      type = lib.types.str;
      default = "10.43.0.0/16,fd42:42:43::/112";
    };
    systemReserved = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "kubelet system-reserved, e.g. \"cpu=2,memory=3Gi\".";
    };
    nodeLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Registration-time node labels.";
    };
    extraTlsSans = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.ipv4 == null || ipv6 != null;
        message = "custom.k3sNet: ipv4 is set without ipv6 or ipv6Mac — a dual-stack node needs both";
      }
    ];
    services.k3s.serverAddr = lib.mkDefault "https://${cfg.apiVip}:6443";
    services.k3s.extraFlags =
      common ++ lib.optionals (config.services.k3s.role == "server") server;
  };
}
