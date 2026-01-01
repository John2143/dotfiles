# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  pkgs,
  pkgs-stable,
  lib,
  ...
}:

{
  imports = [
    ./arch-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/ollama.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;

  #nix.settings.trusted-users = [ "@wheel" ];
  #nix.settings.trusted-public-keys = [
    #"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
  #];

  services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.supportedFilesystems = [ "ntfs" ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    dnsovertls = "true";
  };

  networking.hostName = "arch"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.interfaces = {
    enp6s0.ipv4.addresses = [
      {
        address = "192.168.1.3";
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = "192.168.1.1";
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

  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://192.168.1.35:6443";
    token = "K10c774bc9053c47bd55747f362531fb443f6ca1e4364143dbd74acdd4156eb6878::gw42uk.w06j3n5hkp5o30h8";
  };

  # services.ollama.acceleration = "cuda";

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
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
