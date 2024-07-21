# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # === BEGIN NONFREE ===
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "electron-25.9.0"
    ];
  };
  # === END NONFREE ===

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

    k3s # kubernetes k8s node

    pavucontrol # audio
    qpwgraph
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "input" "dialout" ]; # Enable ‘sudo’ for the user.
    initialPassword = "john";
    shell = pkgs.fish;
    packages = with pkgs; [
      # === BEGIN NONFREE ===
      obsidian # note-taking software
      teamspeak_client
      discord
      # ======== X =========
      # bspwm
      # xorg.xinit
      # polybarFull
      # ======== X =========
      # nvidia_x11
      # nvidia_settings
      # nvidia_persistenced
      # === END NONFREE ===
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  home-manager = {
    users = {
      "john" = import ./home.nix;
    };
  };

  # ======== X =========

  # services.xserver = {
  #   enable = true;
  #   layout = "us";
  #   xkbOptions = "ctrl:nocaps";
  #   windowManager = {
  #     bspwm.enable = true;
  #     # default = "bspwm";
  #     bspwm = {
  #       configFile = ../.config/bspwm/bspwmrc;
  #       sxhkd.configFile = ../.config/sxhkd/sxhkdrc;
  #     };
  #   };
  # };

  # ======== X =========

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.hyprland = {
    enable = true;
  };

  programs.fish.enable = true;

  programs.steam.enable = true;

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

  services.mullvad-vpn = {
    enable = true;
  };

  security.rtkit.enable = true;
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
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };

  services.udisks2.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # TODO udiskie
  # services.udiskie.enable = true;

  # services.k3s = {
  #   enable = true;
  #   role = "agent";
  #   serverAddr = "https://192.168.1.2:6443";
  #   token = "K109bf3d3db3a886f74e3b580da672b54e15f0197c0d922c5f3186a8abd2ba36b00::server:cc13ddec0fa20ac3f2c1b3912dab21fb";
  # };

  services.blueman.enable = true;


  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
