# Disko configuration for the secu machine.
#
# Partition layout (/dev/sda, ~100GB GPT):
#   sda1: ESP    (4GB,   vfat,  label=BOOT,  mount=/boot)
#   sda2: Swap   (8GB,   random-key encrypted, label=SWAP)
#   sda3: LUKS   (~88GB, "cryptroot")
#     └── btrfs (label=NIX)
#           subvol @root      -> /
#           subvol @home      -> /home/john
#           subvol @snapshots -> /home/john/.snapshots
#
# === POST-INSTALL STEPS ===
#
# 1. Install NixOS with disko -- disko handles partitioning, formatting,
#    and mounting. During install you will be prompted for a LUKS passphrase
#    for the "cryptroot" partition.
#
# 2. Enroll USB keyfile -- plug in the CRYPTKEY USB and run:
#      sudo cryptsetup luksAddKey /dev/sda3 /dev/disk/by-partlabel/CRYPTKEY --new-keyfile-size 4096
#    (you will be prompted for the existing passphrase to authorize)
#
# 3. Enable post-install module -- uncomment the secu-post-install.nix
#    import in flake.nix and rebuild:
#      sudo nixos-rebuild switch --flake .#secu
#
# 4. Verify USB unlock -- reboot with the USB plugged in; the system should
#    unlock automatically. Without the USB, it falls back to passphrase.
#
# 5. Snapshots -- btrbk will begin taking hourly snapshots of /home/john.
#    List them with:
#      sudo btrbk list snapshots
#    Restore with:
#      btrfs subvolume snapshot /home/john/.snapshots/<snapshot-name> /home/john
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
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
                extraArgs = [ "-L" "SWAP" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" "-L" "NIX" ];
                  subvolumes = {
                    "@root" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@home" = {
                      mountpoint = "/home/john";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@snapshots" = {
                      mountpoint = "/home/john/.snapshots";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
