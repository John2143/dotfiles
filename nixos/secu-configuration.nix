# secu — 24/7 camera monitoring station.
# Boots directly into Hyprland and opens Firefox fullscreen on the
# GL-KVM web UI (https://glkvm.ts.2143.me), showing the NVR screen.
# GL-KVM login is manual (password typed once, saved by Firefox).
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
    ./modules/secu-startup.nix
    #./modules/ollama.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;
  services.getty.autologinUser = "john";

  # age identity must be reachable in the initrd: NixOS 26.x runs agenix
  # activation inside initrd-nixos-activation-start, before @home (and thus
  # /home/john/.ssh/age) is mounted. Mirror the cluster-host pattern
  # (cluster/hosts/ssh.nix): keyfile at /etc/ssh/age-identity on the root fs.
  age.identityPaths = ["/etc/ssh/age-identity"];

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
      default_session = {
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
