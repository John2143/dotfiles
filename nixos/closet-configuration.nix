# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports =
    [
      ./closet-hardware-configuration.nix
      # inputs.home-manager.nixosModules.default
    ];


  home-manager.users.john = import ./home-cli.nix;

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  networking.hostName = "closet"; # Define your hostname.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    enp6s0.ipv4.addresses = [{
      address = "192.168.1.35";
      prefixLength = 24;
    }];
  };

  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.12" "1.1.1.1" ];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    fish
    curl
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # ================
  # === Services ===
  # ================

  # Enable the OpenSSH daemon.
  users.users."john".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEQTnsGZnbDgz6aY4O15lVybDwkaGJlIUmYO75gyLVds john@office"
  ];
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  security.rtkit.enable = true;
  services.printing.enable = true;

  services.k3s = {
    enable = true;
    role = "server";
  };

  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  networking.firewall.enable = false;

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?
}
