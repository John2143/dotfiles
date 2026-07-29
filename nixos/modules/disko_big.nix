# Disko configuration for the big machine.
#
# Partition layout (/dev/sda, GPT):
#   sda1: ESP    (1G,  vfat,  label=BOOT, mount=/boot)
#   sda2: root   (rest, ext4,  label=NIXROOT, mount=/)
#
# Install:
#   sudo nix --experimental-features "nix-command flakes" \
#     run github:nix-community/disko -- --mode disko ./nixos/modules/disko_big.nix
#   sudo mount /dev/disk/by-label/NIXROOT /mnt
#   sudo mkdir -p /mnt/boot
#   sudo mount /dev/disk/by-label/BOOT /mnt/boot
#   sudo nixos-install --flake .#big
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
              size = "1G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
                extraArgs = ["-n" "BOOT"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = ["-L" "NIXROOT"];
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
