# Post-install module for big.
# Uncomment in flake.nix AFTER generating the age key and re-encrypting secrets:
#   1. ssh-keygen -f ~/.ssh/age -N "" -C "john@big"
#   2. cat ~/.ssh/age.pub  → paste into secrets/secrets.nix as "big = ..."
#   3. On office: cd ~/dotfiles/secrets && agenix -r -i ~/.ssh/age
#   4. Rebuild: sudo nixos-rebuild switch --flake .#big
{
  config,
  ...
}: {
  imports = [
    ./k3s-agent.nix
    ./restic-backup.nix
    ./attic.nix
    ./remote-builders.nix
  ];

  custom.backup.enable = true;

  # ── NVIDIA Tesla P4 (Proxmox passthrough) — kube GPU foundation ──
  # Pascal card: MUST use the legacy_580 driver branch — nvidiaPackages.stable
  # (595+) dropped Maxwell/Pascal/Volta support and won't load on the P4.
  # The container toolkit writes a CDI spec to /run/cdi; symlinking it into
  # /etc/cdi makes it visible to k3s' containerd (reads /etc/cdi and
  # /var/run/cdi by default; CDI is on by default in containerd 2.x).
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    modesetting.enable = true;
    open = false;
  };
  hardware.nvidia-container-toolkit.enable = true;
  environment.etc."cdi/nvidia-container-toolkit.json".source = "/run/cdi/nvidia-container-toolkit.json";
  # ── kube GPU device plugin driver root ────────────────────────────
  # The NVIDIA device plugin (k8s) mounts /driver-root into its pod and
  # generates CDI specs referencing /usr/lib64 paths (nvcdi resolves to
  # absolute FHS paths when the driver root is "/"). The bind SOURCES in
  # those specs resolve on the host, so /usr/lib64 must exist there too.
  # Driver libs must be REAL copies, not store symlinks — nvcdi resolves
  # symlinks to /nix/store and emits unusable spec paths.
  systemd.tmpfiles.rules = [
    "d /usr 0755 root root -"
    "L /usr/lib64 - - - - /driver-root"
  ];
  systemd.services.populate-driver-root = {
    description = "Populate /driver-root with real copies of the NVIDIA driver libs";
    wantedBy = ["multi-user.target"];
    before = ["k3s.service"];
    after = ["nvidia-container-toolkit-cdi-generator.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /driver-root
      cp -aL /run/opengl-driver/lib/. /driver-root/
    '';
  };
}
