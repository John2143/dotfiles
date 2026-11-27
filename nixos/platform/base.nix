# Base configuration shared by every US platform host. The three differ only
# in the addresses and the disk they install onto, which come from nodes.nix
# through custom.platform, so this file has no per-host conditionals.
#
# k3s, the WireGuard mesh and the edge role arrive in phase 2; this module
# only has to produce a host that boots unattended, answers SSH on its key
# and can be reinstalled by nixos-anywhere.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}: let
  cfg = config.custom.platform;
in {
  options.custom.platform = {
    site = lib.mkOption {
      type = lib.types.str;
      description = "Where the node actually runs (provider and region, or bigp).";
    };
    publicIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public address the edge answers on; null for a node behind NAT.";
    };
    wgAddress = lib.mkOption {
      type = lib.types.str;
      description = "wg-plat mesh address (10.98.1.0/24) — the node's identity in the cluster.";
    };
    voter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Runs a k3s control-plane member (all three do, or quorum is not 3).";
    };
    edge = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Terminates public 80/443 for the home sites.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      description = "Static address in CIDR form, e.g. 192.168.5.50/24.";
    };
    gateway = lib.mkOption {
      type = lib.types.str;
      description = "Default gateway on the same link as address.";
    };
    address6 = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F:]+/[0-9]{1,3}");
      default = null;
      description = "Static IPv6 address in CIDR form; null when the node has no IPv6.";
    };
    gateway6 = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F:]+");
      default = null;
      description = "IPv6 default gateway; null leaves the node with no IPv6 default route (a ULA-only host).";
    };
    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
    };
    mac = lib.mkOption {
      type = lib.types.str;
      description = "NIC MAC, lower case. bigp-tofu and the provider both pin it.";
    };
    diskDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda";
    };
    useEFI = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "false = BIOS/GRUB via a 1M EF02 partition, which is what all three providers need.";
    };
  };

  config = {
    # A gateway6 with no address6 would render a route out of an address the
    # host does not have, so networkd would never bring the link online.
    assertions = [
      {
        assertion = cfg.gateway6 == null || cfg.address6 != null;
        message = "custom.platform.gateway6 requires address6";
      }
    ];

    # Module arguments for nixos/cluster/modules/disko.nix, which the host
    # entries pass without those arguments (mkHost supplies only compName).
    _module.args = {
      diskDevice = cfg.diskDevice;
      useEFI = cfg.useEFI;
    };

    system.stateVersion = "26.05";
    time.timeZone = "America/New_York";

    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root"];
      # Nothing but root ever invokes nix here, so nothing else needs the
      # daemon; the default is every local user.
      allowed-users = ["root"];
    };
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    networking.hostName = compName;
    networking.domain = "local";
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.nameservers = cfg.nameservers;
    networking.firewall.enable = true;

    # Static on one MAC. RequiredForOnline = routable keeps a boot from being
    # reported online before the default route exists.
    systemd.network.networks."10-lan" = {
      matchConfig.MACAddress = lib.toLower cfg.mac;
      address = [cfg.address] ++ lib.optional (cfg.address6 != null) cfg.address6;
      routes =
        [
          {
            Destination = "0.0.0.0/0";
            Gateway = cfg.gateway;
          }
        ]
        # plat-home stops here: its ULA is link-local to the home LAN and the
        # LAN has no public prefix, so there is no IPv6 default route to add.
        ++ lib.optional (cfg.gateway6 != null) {
          Destination = "::/0";
          Gateway = cfg.gateway6;
        };
      # AcceptRA stays off because every address is static. LinkLocalAddressing
      # keeps its `ipv6` default, so plat-nyc's fe80::1 gateway is on-link and
      # needs no GatewayOnLink.
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "routable";
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      # PAM's auth stack for sshd is deny-only, but the method is still
      # advertised, so clients that prefer it get an auth failure path for
      # free. Stop offering it at all.
      settings.KbdInteractiveAuthentication = false;
      # nixos-anywhere, the phase-2 k3s bootstrap and every later block ssh as
      # root with a key.
      settings.PermitRootLogin = "prohibit-password";
      # This daemon exists to run root commands. No tunnels, no agent
      # forwarding, no ~/.ssh/authorized_keys: keys come from ssh.nix only.
      settings.AllowTcpForwarding = "no";
      settings.AllowAgentForwarding = false;
      settings.AllowStreamLocalForwarding = false;
      settings.LoginGraceTime = 20;
      settings.MaxAuthTries = 3;
      settings.MaxStartups = "10:30:60";
      authorizedKeysInHomedir = false;
    };
    # Only plat-home is a guest of bigp, where H6 verifies the agent from
    # outside; on the cloud voters it is just another root-level socket.
    services.qemuGuest.enable = cfg.site == "bigp";

    # No link-local name resolution on a public host: nothing on the platform
    # uses LLMNR or mDNS, and both listeners otherwise answer on 5355/5353.
    services.resolved.settings.Resolve = {
      LLMNR = false;
      MulticastDNS = false;
    };

    # A voter whose kernel panics reboots after 10 s instead of sitting dead
    # until an operator notices. (Only panics: a hung k3s does not trigger it.)
    # The rest shuts the autoconf and redirect paths nothing on these hosts
    # uses. rp_filter stays at systemd's loose 2: strict filtering breaks the
    # phase-2 WireGuard return path.
    boot.kernel.sysctl = {
      "kernel.panic" = 10;
      "net.ipv6.conf.all.accept_ra" = 0;
      "net.ipv6.conf.default.accept_ra" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
    };

    # Keep the journal bounded: 1G used at most, and always leave 2G of the
    # 100G root free for etcd's own writes.
    services.journald.settings.Journal = {
      SystemMaxUse = "1G";
      SystemKeepFree = "2G";
    };

    environment.systemPackages = with pkgs; [curl git jq];
  };
}
