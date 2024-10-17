# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, pkgs-stable, inputs, ... }:

{
  # flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # setup my two input channels
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "electron-25.9.0"
    ];
  };

  _module.args.pkgs-stable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit (config.nixpkgs) config;
  };

  # shutdown faster
  systemd.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';

  fonts.packages = with pkgs; [
    scientifica
  ];

  environment.systemPackages = with pkgs; [
    git
    fish
    wget
    curl
    tmux
    vim
    btop
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
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
  services.udisks2.enable = true;

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


  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;


  virtualisation.docker.enable = true;

  systemd.timers."kdeconnect-refresh" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "kdeconnect-refresh.service";
    };
  };

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
