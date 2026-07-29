# Big Machine — Proxmox VM (32 cores, 128 GB RAM, virtio, SeaBIOS)
#
# === INSTALL FROM LIVE CD ===
#   sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko ./nixos/modules/disko_big.nix
#   sudo mount /dev/disk/by-label/NIXROOT /mnt
#   sudo nixos-install --flake .#big
#
# === POST-INSTALL (age key + secrets) ===
#   1. On big:  ssh-keygen -f ~/.ssh/age -N "" -C "john@big" && cat ~/.ssh/age.pub
#   2. On office: paste into secrets/secrets.nix as big = "...", add big to:
#      - k3s-local-token, attic-admin-token, build-cluster-key publicKeys
#      - agenix -r -i ~/.ssh/age && git commit -am "add big" && git push
#   3. On big:  git pull && uncomment big-post-install.nix in flake.nix
#      sudo nixos-rebuild switch --flake .#big
#
# === GOTCHAS ===
#   - Do NOT set boot.loader.grub.device; disko already provides boot.loader.grub.devices.
#     Setting both causes "duplicate devices in mirroredBoots" assertion failure.
#   - k3s 1.35+ rejects custom labels in the kubernetes.io namespace. Use node-role. prefix.
#   - Secrets must be re-encrypted with the new host's age key before post-install rebuild.

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
    "--node-label=workload-type=general"
    "--node-label=node.longhorn.io/create-default-disk=true"
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
