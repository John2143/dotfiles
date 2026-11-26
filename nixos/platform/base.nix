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
      address = [cfg.address];
      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = cfg.gateway;
        }
      ];
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "routable";
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      # nixos-anywhere, the phase-2 k3s bootstrap and every later block ssh as
      # root with a key.
      settings.PermitRootLogin = "prohibit-password";
    };
    services.qemuGuest.enable = true;

    environment.systemPackages = with pkgs; [curl git jq];
  };
}
