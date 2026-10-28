# Disko configuration for the office workstation (UEFI / systemd-boot).
#
# Stable by-id path:
#   nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F → the only disk (1.8T)
#
# Layout (GPT + LVM, as few volumes as possible):
#   part1 ESP   (1G,  EF00, vfat, label BOOT)              → /boot
#   part2 PV    (rest, LVM physical volume)                → VG `office`
#     office-swap     (32G,   swap)
#     office-longhorn (300G,  ext4, label longhorn)        → /mnt/longhorn
#     office-root     (1400G, ext4, label root, noatime)   → /  (home lives here)
#   unallocated ~130G — growth headroom for either LV
#
# Why no /home or games volume: one big root, grown online with
# `sudo lvextend -r -L +<size> office/root`. Only `longhorn` is split out so
# Longhorn can never fill /. office is NOT registered as a Longhorn node
# (it carries taint wifi=no-network-storage); /mnt/longhorn matches the
# cluster's setting default-data-path, so enabling it later needs no change.
#
# Install (wipes the disk):
#   sudo nix --experimental-features "nix-command flakes" \
#     run github:nix-community/disko -- --mode disko ./nixos/modules/disko_office.nix
#   sudo nixos-install --flake .#office --no-root-passwd
{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["fmask=0022" "dmask=0022"];
              extraArgs = ["-n" "BOOT"];
            };
          };
          lvm = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "office";
            };
          };
        };
      };
    };
    lvm_vg.office = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "32G";
          content = {
            type = "swap";
          };
        };
        longhorn = {
          size = "300G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/longhorn";
            mountOptions = ["noatime"];
            extraArgs = ["-L" "longhorn"];
          };
        };
        root = {
          size = "1400G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["noatime"];
            extraArgs = ["-L" "root"];
          };
        };
      };
    };
  };
}
