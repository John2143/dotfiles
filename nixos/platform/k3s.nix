# k3s on the three platform voters: embedded etcd, dual-stack, every cluster
# port on wg-plat. The dual-stack values mirror the home cluster's
# nixos/modules/k3s-net.nix; k3s can only be dual-stack from its first start.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}: let
  nodes = import ./nodes.nix;
  self = config.custom.platform;
  init = "plat-bos";
  isHome = self.site == "bigp";
  s3 = {
    endpoint = "s3.us-east-005.backblazeb2.com";
    region = "us-east-005";
    bucket = "2143-labs-public-argo";
  };
  # Every address a client may use for the API. 10.98.0.11/.12 are the cloud
  # voters' wg-home addresses, which phase 3 adds; they are listed now because
  # changing this list later regenerates the API certificates.
  sans =
    lib.concatMap (n: [n.wgAddress n.wgAddress6]) (lib.attrValues nodes)
    ++ ["10.98.0.11" "10.98.0.12" "192.168.5.50" "fd00:1::50"];
in {
  # These hosts have no /etc/ssh/age-identity (ssh.nix lists it for the
  # Hetzner hosts); their agenix identity is the SSH host key alone.
  age.identityPaths = lib.mkForce ["/etc/ssh/ssh_host_ed25519_key"];
  age.secrets.platform-k3s-token = {
    file = ../../secrets/platform-k3s-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };
  age.secrets.platform-etcd-s3-env = {
    file = ../../secrets/platform-etcd-s3.env.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  services.k3s = {
    enable = true;
    # Pinned to a minor: a nixpkgs bump must not move three etcd voters to a
    # new Kubernetes minor by accident.
    package = pkgs.k3s_1_36;
    role = "server";
    clusterInit = compName == init;
    serverAddr =
      if compName == init
      then ""
      else "https://${nodes.${init}.wgAddress}:6443";
    tokenFile = config.age.secrets.platform-k3s-token.path;
    # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for --etcd-s3.
    environmentFile = config.age.secrets.platform-etcd-s3-env.path;
    disable = ["traefik" "servicelb"];
    nodeLabel =
      [
        "2143.me/provider=${lib.head (lib.splitString "-" self.site)}"
        "2143.me/site=${
          if isHome
          then "home"
          else "cloud"
        }"
      ]
      ++ lib.optional self.edge "2143.me/edge=true";
    nodeTaint = lib.optional isHome "2143.me/home=true:NoSchedule";
    # The module joins these with spaces and no quoting: no value may contain
    # a space. The snapshot schedule is k3s's default (00:00 and 12:00), which
    # is why no cron flag appears here.
    extraFlags =
      [
        "--node-ip=${self.wgAddress},${self.wgAddress6}"
        "--advertise-address=${self.wgAddress}"
        "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
        "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
        "--flannel-backend=vxlan"
        "--flannel-iface=wg-plat"
        "--flannel-ipv6-masq"
        "--secrets-encryption"
        "--etcd-s3"
        "--etcd-s3-endpoint=${s3.endpoint}"
        "--etcd-s3-region=${s3.region}"
        "--etcd-s3-bucket=${s3.bucket}"
        "--etcd-s3-folder=etcd"
        # Twice a day for two weeks, locally and in the bucket.
        "--etcd-s3-retention=28"
        "--etcd-snapshot-retention=28"
      ]
      ++ map (s: "--tls-san=${s}") sans;
  };

  # --node-ip lives on wg-plat, so k3s must not start before the interface.
  systemd.services.k3s = {
    after = ["wireguard-wg-plat.service"];
    wants = ["wireguard-wg-plat.service"];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  networking.firewall.interfaces.wg-plat = {
    allowedTCPPorts = [2379 2380 6443 10250];
    allowedUDPPorts = [8472];
  };
  # A pod calling the API service or its own node's kubelet is DNATed to the
  # node address and arrives on cni0, not on wg-plat.
  networking.firewall.interfaces.cni0.allowedTCPPorts = [6443 10250];
  # The owner's kubectl reaches plat-home over the LAN. Matched by source, not
  # by interface name, which is not stable.
  networking.firewall.extraCommands = lib.mkIf isHome ''
    iptables -A nixos-fw -p tcp -s 192.168.5.0/24 --dport 6443 -j nixos-fw-accept
  '';
}
