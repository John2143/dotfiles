# Disko configuration for the NAS machine.
#
# Partition layout (2TB WD SSD, GPT):
#   part1: ESP        (1GB,    vfat, label=BOOT,    mount=/boot)
#   part2: Swap       (8GB,    random-key encrypted, label=SWAP)
#   part3: Root       (~1TB,   ext4, label=NIXROOT,  mount=/)
#   part4: ZFS-special (~500GB, raw, no filesystem)
#         └── Used as one leg of the mirrored ZFS special vdev on `tank`.
#             Paired with the 500GB SSD via: zpool add tank special mirror ...
#
# The ZFS data pool (`tank`) is NOT managed by disko. It is created manually
# after the first boot and auto-imported by NixOS via boot.zfs.extraPools.
# See nas-configuration.nix header comments for the full ZFS setup procedure.
#
# === INSTALL STEPS ===
#
# 1. Boot the NixOS installer USB.
# 2. Identify the 2TB boot SSD:
#      ls -l /dev/disk/by-id/ | grep WDC
#    Update the `device` path below.
# 3. Run disko:
#      sudo nix --experimental-features "nix-command flakes" \
#        run github:nix-community/disko -- --mode disko ./nixos/modules/disko_nas.nix
# 4. Install NixOS:
#      sudo nixos-install --flake .#nas
# 5. Reboot, then create ZFS pools (see nas-configuration.nix).
#
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/disk/by-id/ata-WDC_CHANGEME";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "1G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
                extraArgs = [ "-n" "BOOT" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
                extraArgs = [ "-L" "SWAP" ];
              };
            };
            root = {
              size = "1T";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [ "-L" "NIXROOT" ];
              };
            };
            zfs_special = {
              size = "100%";
            };
          };
        };
      };
    };
  };
}
