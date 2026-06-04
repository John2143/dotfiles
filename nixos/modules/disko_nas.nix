# Disko configuration for the NAS boot SSD.
#
# Target disk: 2TB WD SSD (wwn-0x5001b448be24504b, currently sda).
#
# Partition layout (GPT):
#   part1: ESP         (4GB,    vfat,  mount=/boot)
#   part2: root        (1024GB, ext4,  mount=/)
#   part3: swap        (16GB,   plain dm-crypt random-key)
#   part4: zfs_special (100GB,  raw — tank special mirror leg, attached post-boot)
#   part5: l2arc       (200GB,  raw — tank L2ARC cache, added post-boot)
#   part6: longhorn    (remainder ~519GB, ext4, mount=/var/lib/longhorn)
#
# The ZFS pool `tank` is NOT managed by disko. After first boot:
#   1. Import:  sudo zpool import tank
#   2. Re-attach special mirror leg:
#      sudo zpool replace tank /dev/disk/by-partlabel/disk-main-zfs_special
#   3. Re-add L2ARC:
#      sudo zpool add tank cache /dev/disk/by-partlabel/disk-main-l2arc
#   4. Rebuild: sudo nixos-rebuild switch --flake /home/john/dotfiles#nas
#
# === INSTALL STEPS (fresh install or boot SSD replacement) ===
#
# 1. Boot the NixOS installer USB.
# 2. Identify the 2TB boot SSD:
#      ls -l /dev/disk/by-id/ | grep -i wdc
#    Verify it matches wwn-0x5001b448be24504b.
# 3. Run disko:
#      sudo nix --experimental-features "nix-command flakes" \
#        run github:nix-community/disko -- --mode disko ./nixos/modules/disko_nas.nix
# 4. Install NixOS:
#      sudo mount /dev/disk/by-label/NIXROOT /mnt
#      sudo mount /dev/disk/by-label/BOOT /mnt/boot
#      sudo mount /dev/disk/by-label/longhorn /mnt/var/lib/longhorn
#      sudo nixos-install --flake /home/john/dotfiles#nas
# 5. Reboot, then re-attach ZFS tank members (see above).
#
# === DISASTER RECOVERY (boot SSD failure) ===
#
# RTO target: ~25-40 minutes (bounded by nixos-install build time).
# ZFS data arrays (sdb-sde, RAIDZ2) are unaffected — no data loss.
#
# 1. PHYSICALLY REPLACE: Swap dead SSD, insert replacement.
# 2. IDENTIFY: ls -l /dev/disk/by-id/ | grep -i wdc
#    If the WWN changed (different model), update the `device` line below.
# 3. PARTITION:
#      nix run github:nix-community/disko -- --mode disko ./nixos/modules/disko_nas.nix
# 4. MOUNT & INSTALL:
#      mount /dev/disk/by-label/NIXROOT /mnt
#      mount /dev/disk/by-label/BOOT /mnt/boot
#      mount /dev/disk/by-label/longhorn /mnt/var/lib/longhorn
#      nixos-install --flake github:John2143/dotfiles#nas
#    (If GitHub is unreachable, use a local clone of the dotfiles repo.)
# 5. REBOOT:
#      reboot
# 6. RE-ATTACH ZFS TANK MEMBERS:
#      zpool import tank
#      zpool replace tank /dev/disk/by-partlabel/disk-main-zfs_special
#      zpool add tank cache /dev/disk/by-partlabel/disk-main-l2arc
#      nixos-rebuild switch --flake ~/dotfiles#nas
#
# The dotfiles repo must be reachable at install time. If the NAS itself
# was the only clone of the repo and GitHub is down, clone to the installer
# from another machine on the LAN or use a USB stick with a tarball.
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
              name = "disk-main-ESP";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
                extraArgs = ["-n" "BOOT"];
              };
            };
            root = {
              type = "8300";
              size = "1024G";
              name = "disk-main-root";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = ["x-initrd.mount" "defaults"];
                extraArgs = ["-L" "NIXROOT"];
              };
            };
            swap = {
              type = "8200";
              size = "16G";
              name = "disk-main-swap";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            zfs_special = {
              type = "8300";
              size = "100G";
              name = "disk-main-zfs_special";
              # Raw — ZFS special mirror leg, attached post-boot
            };
            l2arc = {
              type = "8300";
              size = "200G";
              name = "disk-main-l2arc";
              # Raw — ZFS L2ARC cache, added post-boot
            };
            longhorn = {
              type = "8300";
              size = "100%";
              name = "disk-main-longhorn";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/var/lib/longhorn";
                mountOptions = ["defaults"];
                extraArgs = ["-L" "longhorn"];
              };
            };
          };
        };
      };
    };
  };
}
