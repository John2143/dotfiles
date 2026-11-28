# Disko configuration for arch (UEFI / systemd-boot).
#
# Stable by-id paths (the kernel's nvme0n1/nvme1n1 names swap between boots):
#   nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B → main (ESP + PV, 1T)
#   nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B → data (PV only, 1T)
# The WD 2TB SATA disk (NTFS, label xd, /mnt/d) is not managed here.
#
# Layout (GPT + one VG over both NVMe):
#   main part1 ESP (3G, EF00, vfat, label BOOT)            → /boot
#   main part2 PV  (rest)                                  ┐
#   data part1 PV  (whole disk)                            ┴→ VG `arch` (~1904G)
#     arch-swap     (32G,  swap)
#     arch-longhorn (500G, ext4, label longhorn, noatime)  → /mnt/longhorn
#     arch-monero   (400G, ext4, label monero, noatime)    → /mnt/monero
#     arch-root     (900G, ext4, label root, noatime)      → /  (home lives here)
#   unallocated ~72G — growth headroom, `sudo lvextend -r -L +<size> arch/<lv>`
#
# No RAID: root spans both NVMe, so either disk failing loses /. restic covers
# /home/john. longhorn is split out so Longhorn can never fill /; after its 30%
# storage-reserved-percentage it offers ~350G. monero is split out for the
# same reason (the chain grows ~1G/day).
#
# Install (wipes both NVMe), from the NixOS installer with the repo at /tmp/dotfiles:
#   sudo nix --experimental-features "nix-command flakes" run --inputs-from /tmp/dotfiles \
#     disko -- --mode destroy,format,mount /tmp/dotfiles/nixos/modules/disko_arch.nix
#   sudo nixos-install --system <prebuilt toplevel> --no-root-passwd --no-channel-copy
{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "3G";
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
              vg = "arch";
            };
          };
        };
      };
    };
    disk.data = {
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B";
      type = "disk";
      content = {
        type = "gpt";
        partitions.lvm = {
          size = "100%";
          content = {
            type = "lvm_pv";
            vg = "arch";
          };
        };
      };
    };
    lvm_vg.arch = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "32G";
          content = {
            type = "swap";
          };
        };
        longhorn = {
          size = "500G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/longhorn";
            mountOptions = ["noatime"];
            extraArgs = ["-L" "longhorn"];
          };
        };
        monero = {
          size = "400G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/monero";
            mountOptions = ["noatime"];
            extraArgs = ["-L" "monero"];
          };
        };
        root = {
          size = "900G";
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
