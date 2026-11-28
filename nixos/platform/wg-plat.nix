# wg-plat: the WireGuard mesh between the three platform voters. etcd, the
# API, the kubelet and flannel's VXLAN (both families) all run on these
# addresses, so no cluster port is ever open on a public interface.
#
# Peers come from nodes.nix. The two cloud voters reach each other on their
# public IPv4; plat-home sits behind the home NAT, so it dials both and keeps
# the mapping open, and the clouds learn its endpoint from that.
{
  config,
  lib,
  compName,
  ...
}: let
  nodes = import ./nodes.nix;
  self = config.custom.platform;
  behindNat = self.publicIPv4 == null;
  others = lib.filterAttrs (name: n: name != compName && n.wgPublicKey != null) nodes;
  mkPeer = name: n:
    {
      inherit name;
      publicKey = n.wgPublicKey;
      allowedIPs = ["${n.wgAddress}/32" "${n.wgAddress6}/128"];
    }
    // lib.optionalAttrs (n.publicIPv4 != null) {endpoint = "${n.publicIPv4}:51820";}
    // lib.optionalAttrs behindNat {persistentKeepalive = 25;};
in {
  # Script backend, not networkd. networkd cannot generate the key, and it
  # loads the key through systemd-networkd's own credentials, so a missing key
  # file would stop networkd and take the SSH interface down with it. Here a
  # WireGuard failure stays inside wireguard-wg-plat.service.
  networking.wireguard.useNetworkd = false;

  networking.wireguard.interfaces.wg-plat = {
    ips = ["${self.wgAddress}/24" "${self.wgAddress6}/64"];
    listenPort = 51820;
    mtu = 1420;
    privateKeyFile = "/var/lib/wireguard/wg-plat.key";
    generatePrivateKeyFile = true;
    # The /24 and /64 on the interface already route every peer.
    allowedIPsAsRoutes = false;
    peers = lib.mapAttrsToList mkPeer others;
  };

  # WireGuard answers only peers it has a key for. plat-home never needs the
  # port open: it dials, and replies return through connection tracking.
  networking.firewall.allowedUDPPorts = lib.optional (!behindNat) 51820;
}
