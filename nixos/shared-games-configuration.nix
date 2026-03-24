# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  ...
}:

{
  # VPN
  #services.mullvad-vpn = {
    #enable = true;
  #};

  # games
  programs.steam.enable = true;
  programs.gamescope.enable = true;
  services.flatpak.enable = true;
  services.udev.packages = [ pkgs.via ];
  environment.systemPackages = with pkgs; [
    via
    qmk
  ];

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = [
      pkgs-stable.brlaser
    ];
    listenAddresses = [ "*:631" ];
    allowFrom = [ "all" ];
    browsing = true;
    defaultShared = true;
  };

  services.udev.extraRules = (
      builtins.readFile ./udev_embedded.rules
      + "\n"
      + builtins.readFile ./udev_keyboard_via.rules
  );
}
