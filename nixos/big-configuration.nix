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

  # ── Volatile/growing data off the 100G root disk ───────────────────────
  # /tmp is RAM-backed (tmpfs): ephemeral by design, so it can never fill
  # the root disk, and it's faster than any disk. The 2T scsi1 disk is 100%
  # longhorn's (see modules/disko_big.nix), so it's left alone here.
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "16G";

  # Weekly TRIM. Only reclaims space on the Proxmox thin pool if the VM's
  # disks have `discard=on` (otherwise QEMU silently drops guest discards).
  services.fstrim.enable = true;

  # ── Growing /var dirs relocated onto the 2T longhorn zvol ───────────────
  # Bind-mounts the persistent/growing /var dirs onto the 2T scsi1 disk
  # (mounted at /var/lib/longhorn by disko_big.nix). Longhorn only manages
  # its own subdirs (replicas/, engine-binaries/), so a .system/ subtree is
  # safe and keeps free-space accounting accurate (same filesystem).
  # `nofail` + `depends` keep boot safe: nothing mounts before the zvol is
  # up, and a missing disk can never brick boot. Source dirs are created by
  # the tmpfiles rule below and persist on the zvol's ext4.
  #
  # NOTE: on the first `nixos-rebuild switch`, migrate existing data first
  # (with the relevant service stopped), e.g.:
  #   rsync -a /var/lib/rancher/     /var/lib/longhorn/.system/rancher/     # k3s
  #   rsync -a /var/lib/containers/  /var/lib/longhorn/.system/containers/  # podman
  # The originals stay on the root disk until you delete them.
  fileSystems."/var/log" = {
    device = "/var/lib/longhorn/.system/log";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/var/lib/longhorn" ];
  };
  fileSystems."/var/cache" = {
    device = "/var/lib/longhorn/.system/cache";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/var/lib/longhorn" ];
  };
  fileSystems."/var/tmp" = {
    device = "/var/lib/longhorn/.system/tmp";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/var/lib/longhorn" ];
  };
  fileSystems."/var/lib/containers" = {
    device = "/var/lib/longhorn/.system/containers";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/var/lib/longhorn" ];
  };
  fileSystems."/var/lib/rancher" = {
    device = "/var/lib/longhorn/.system/rancher";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/var/lib/longhorn" ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn/.system/log 0755 root root -"
    "d /var/lib/longhorn/.system/cache 0755 root root -"
    "d /var/lib/longhorn/.system/tmp 1777 root root -"
    "d /var/lib/longhorn/.system/containers 0711 root root -"
    "d /var/lib/longhorn/.system/rancher 0755 root root -"
  ];

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
  # Proxmox guest agent — enables qm guest exec / graceful shutdown from hypervisor
  services.qemuGuest.enable = true;

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
    5580 # matter-server (hostNetwork pod)
  ];
  networking.firewall.allowedUDPPorts = [
    5540 # matter-server (hostNetwork pod)
    8472 # flannel VXLAN
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # NodePort range
  ];

  system.stateVersion = "26.05";
}
