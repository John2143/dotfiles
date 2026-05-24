# secu — 24/7 security camera monitoring station.
# Boots directly into Hyprland and displays a live RTSP grid
# of all 6 Reolink camera channels from the NVR (192.168.1.67).
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

  # Greetd auto-logs into Hyprland directly at boot (lemurs lacks auto_login in 0.4.0).
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "${pkgs.hyprland}/bin/Hyprland";
        user = "john";
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

  # Camera monitoring (mpv is already in home.nix).
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
