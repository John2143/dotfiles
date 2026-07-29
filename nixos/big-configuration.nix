{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  sshKeys,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix") # Proxmox VM virtio drivers
    ./big-hardware-configuration.nix
    ./modules/user-john.nix
  ];
  home-manager.users."john" = import ./home-cli.nix;

  boot.loader.grub.enable = true;

  # 192 GB RAM — no zram or swap needed
  # zswap would add CPU overhead for no benefit

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  networking.hostName = compName;
  networking.networkmanager.enable = true;

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
    htop
    iotop
    lm_sensors
    pciutils
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;
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

  # === k3s worker labels ===
  services.k3s.extraFlags = [
    "--node-label=kubernetes.io/role=worker"
    "--node-label=workload-type=general"
  ];

  # Firewall — k3s ports
  networking.firewall.allowedTCPPorts = [
    10250 # kubelet
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel VXLAN
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # NodePort range
  ];

  system.stateVersion = "26.05";
}
