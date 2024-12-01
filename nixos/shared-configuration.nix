# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, pkgs-stable, inputs, ... }:

{
  # setup my two input channels
  nixpkgs.config = {
    permittedInsecurePackages = [
      "electron-25.9.0"
    ];
  };

  fonts.packages = with pkgs; [
    scientifica
  ];

  # VPN
  services.mullvad-vpn = {
    enable = true;
  };

  # audio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.extraConfig = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
      };
    };
    #jack.enable = true;
  };

  # graphical
  programs.hyprland = {
    enable = true;
    #enableNvidiaPatches = true;
  };

  #environment.systemPackages = with pkgs; [
  #];
  # games
  programs.steam.enable = true;


  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      brlaser
    ];
    listenAddresses = [ "*:631" ];
    allowFrom = [ "all" ];
    browsing = true;
    defaultShared = true;
  };

  # bluetooth
  services.blueman.enable = true;

  systemd.timers."kdeconnect-refresh" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "kdeconnect-refresh.service";
    };
  };

  services.udev.extraRules = builtins.readFile ./udev_embedded.rules;

  systemd.services."kdeconnect-refresh" = {
    script = ''
      ${pkgs.fish}/bin/fish -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus kdeconnect-cli --refresh"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "john";
    };
  };
}
