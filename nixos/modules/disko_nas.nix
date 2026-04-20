# Disko configuration for the NAS machine.
#
# Partition layout declared in this file (2TB WD SSD, GPT):
#   part1: ESP         (4GB,   vfat, label=BOOT, mount=/boot)
#   part2: swap        (16GB,  random-key encrypted, label=SWAP)
#   part3: zfs_special (100GB, raw, no filesystem)
#   part4: root        (remainder, ext4, label=NIXROOT, mount=/)
#
# Current NAS host differs from this declared layout:
#   - / is currently on sda2
#   - swap is currently on sda3
#   - tank special mirror currently uses sda4 + sdf1
# Keep this file and the live layout in sync before relying on this as an
# authoritative rebuild/reinstall recipe.
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
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "4G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
                extraArgs = [ "-n" "BOOT" ];
              };
            };
            swap = {
              size = "16G";
              content = {
                type = "swap";
                randomEncryption = true;
                extraArgs = [ "-L" "SWAP" ];
              };
            };
            zfs_special = {
              size = "100G";
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [ "-L" "NIXROOT" ];
              };
            };
          };
        };
      };
    };
  };
}
