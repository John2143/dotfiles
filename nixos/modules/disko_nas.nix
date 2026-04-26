# Disko configuration for the NAS machine.
#
# Target disk: 2TB WD SSD (wwn-0x5001b448be24504b, currently sdb).
#
# Partition layout declared in this file (GPT):
#   part1: ESP         (4GB,   vfat, label=BOOT, mount=/boot)
#   part2: swap        (16GB,  random-key encrypted, label=SWAP)
#   part3: zfs_special (100GB, raw — tank special mirror leg)
#   part4: l2arc       (200GB, raw — tank L2ARC read cache)
#   part5: neo         (500GB, raw — neo ZFS pool)
#   part6: root        (remainder ~1.1TB, ext4, label=NIXROOT, mount=/)
#
# Current NAS host differs from this declared layout:
#   - Actual on-disk order is ESP(sdb1) / root(sdb2) / swap(sdb3) /
#     zfs_special+l2arc+neo(sdb4-6). This file defines the desired layout
#     for a fresh disko install; partition numbering may differ on the
#     live system.
#   - tank special mirror: wwn-0x5001b448be24504b-part4 (sdb4) +
#                           wwn-0x5e83a97923abf0ec-part1 (sdd1)
#
# The ZFS pools (`tank`, `neo`) are NOT managed by disko. They are created
# manually after the first boot and auto-imported by NixOS via
# boot.zfs.extraPools. See nas-configuration.nix header comments for the
# full ZFS setup procedure.
#
# === INSTALL STEPS ===
#
# 1. Boot the NixOS installer USB.
# 2. Identify the 2TB boot SSD:
#      ls -l /dev/disk/by-id/ | grep WDC
#    Verify it matches wwn-0x5001b448be24504b.
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
        device = "/dev/disk/by-id/wwn-0x5001b448be24504b";
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
            l2arc = {
              size = "200G";
            };
            neo = {
              size = "500G";
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
