# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  pkgs,
  pkgs-stable,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./arch-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/vllm.nix
    # ./modules/frigate.nix  # migrated to k8s on big (2026-08-01); file kept for rollback
    ./modules/teamspeak.nix
    ./modules/nut-ups.nix

    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;



  #nix.settings.trusted-users = [ "@wheel" ];
  #nix.settings.trusted-public-keys = [
  #"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
  #];

  #services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.supportedFilesystems = ["ntfs"];
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.kernelModules = [
    "target_core_mod"
    "iscsi_target_mod"
  ];

  services.displayManager.lemurs = {
    enable = true;
  };
  services.seatd.enable = true;

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSOverTLS = "true";
        DNSSEC = "true";
        Domains = [
          "~."
        ];
        FallbackDNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
    };
  };

  networking.hostName = "arch"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.nameservers = [
    "1.1.1.1"
    "192.168.1.12"
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Second keyboard (winkeyless ps2avrGB) remapped to F13-F24.
  # F23 and F24 are the last standard Linux function keycodes (KEY_F23, KEY_F24).
  # Any additional keys beyond F24 should use XF86Launch* (Launch8, Launch9, etc.)
  # to continue the pattern from the existing XF86Launch5/6/7 mappings.
  # Hyprland binds in hyprland.conf map these to actual commands.

  environment.systemPackages = [
    #inputs.hyprcap.packages.x86_64-linux.default
    pkgs.voxtype
    #inputs.self.packages.x86_64-linux.waytop
  ];

  # openrgb flakes occasionally — keep the unit out of "failed" state so it
  # doesn't trip exit-code-4 in switch-to-configuration's post-activation scan.
  systemd.services.openrgb.enable = lib.mkForce false;


  custom.k3sStorageAfter = ["mnt-longhorn.mount"];

  # k3s server — join existing cluster via mDNS (bootstrap without tailscale dependency).
  # Dual-stack cluster CIDRs mirror closet's init node config.
  services.k3s.extraFlags = lib.concatStringsSep " " [
    "--server=https://192.168.5.10:6443"
    "--disable=servicelb"
    "--tls-san=arch.local"
    "--tls-san=closet.local"
    "--tls-san=192.168.5.76"
    "--tls-san=192.168.5.10"
    "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
    "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
    "--flannel-ipv6-masq"
    "--node-ip=192.168.5.76,fd00:1::7ce1:b412:3068:c799"
    # Fast crash recovery — detect downed nodes in 20s, evict pods in 40s
    "--kube-apiserver-arg=default-not-ready-toleration-seconds=40"
    "--kube-apiserver-arg=default-unreachable-toleration-seconds=40"
    "--kube-controller-manager-arg=node-monitor-grace-period=20s"
    "--kube-controller-manager-arg=node-monitor-period=2s"
    # Reserve 12 CPU + 23 GiB RAM for the system (Hyprland desktop). k8s gets 4 CPU, ~8 GiB.
    "--kubelet-arg=system-reserved=cpu=12,memory=23Gi"
  ];
  custom.backup.enable = true;

  # Building screen-control directly instead of nix run (which was slow and
  # didn't reliably pass the systemd `path` environment through to the binary).
  nixpkgs.overlays = [
    (final: prev: {
      screen-control = inputs.screen-control.defaultPackage.${prev.stdenv.hostPlatform.system};
    })
  ];

  systemd.services.screen-control = {
    description = "REST screen control server";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.screen-control}/bin/screen-control";
      Restart = "always";
      RestartSec = 5;
      User = "john";
      Group = "users";
    };
    path = [pkgs.hyprland];
  };


  networking.firewall.allowedTCPPorts = [
    50051 # screen-control REST API (arch-configuration.nix:290, screen-control/src/main.rs:129)
    10250 # kubelet (k3s agent)
    18080 # monero p2p (monerod)
    5580 # matter-server (hostNetwork pod)
    179 # BGP (MetalLB speaker)
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # Kubernetes NodePort range
  ];

  # NAS CIFS mounts live in ./modules/nas-mounts.nix (shared across workstations).


  # ollama disabled: CUDA build broken upstream (GCC ICE in ggml-cuda),
  # and arch GPU has <8GB VRAM — only gemma4 fits, never used in practice.
  # services.ollama = {
  #   package = pkgs.ollama-cuda;
  #   # Disk-constrained host: only gemma4 is auto-pulled. Don't run ollama-sync
  #   # here — it would mirror every model from the NAS and fill the SSD.
  #   modelNames = ["gemma4"];
  # };
  # vLLM disabled: GPU VRAM too small for the models we'd want to serve here.

  # Firewall enabled via shared-cli-configuration.nix.

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # ── NUT UPS monitoring ────────────────────────────────────────────
  # Desktop k3s node — notify-send, wall, k3s drain, then poweroff.
  # See modules/nut-ups.nix for the shared config.
  custom.nut-ups = {
    enable = false;  # TODO: true once Goldenmate UPS arrives
    k3sDrain = true;
    desktopNotifications = true;
  };
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11";
}
