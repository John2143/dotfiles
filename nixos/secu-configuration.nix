# secu — 24/7 security camera monitoring station.
# This machine boots directly into Hyprland, opens the JetKVM web UI,
# and displays a live grid of all Reolink RTSP camera feeds.
#
# Secrets needed (create with: agenix -e <file>.age -i ~/.ssh/age):
#   secrets/camera-credentials.age  →  CAMERA_USER=admin\nCAMERA_PASSWORD=<pw>
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  sshKeys,
  ...
}: {
  imports = [
    ./secu-hardware-configuration.nix
    ./modules/user-john.nix
    #./modules/ollama.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;
  services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.;
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  services.displayManager.lemurs = {
    enable = true;
    # Auto-login directly to Hyprland (first available Wayland session).
    settings = {
      auto_login = {
        enabled = true;
        username = "john";
        default_desktop = 0;
      };
    };
  };
  services.seatd.enable = true;

  networking.hostName = compName; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Camera monitoring packages (mpv is already in home.nix; these are system-level).
  environment.systemPackages = with pkgs; [
    git
    fish
    curl
    socat          # for RTSP stream debugging
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  custom.backup.enable = true;

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;

  # Enable the OpenSSH daemon.
  users.users."john".openssh.authorizedKeys.keys = sshKeys;
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

  # Camera RTSP credentials (sourced by startup-secu.fish).
  # Create with: cd ~/dotfiles/secrets && agenix -e camera-credentials.age -i ~/.ssh/age
  # Format: CAMERA_USER=admin\nCAMERA_PASSWORD=<reolink-password>
  age.secrets.camera-credentials = {
    file = ../secrets/camera-credentials.age;
    owner = "john";
  };

  # Disable console blanking for 24/7 monitoring.
  boot.kernelParams = [ "consoleblank=0" ];

  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  #networking.firewall.enable = true;

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?
}
