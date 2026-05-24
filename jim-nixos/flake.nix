{
  description = "Jim's first NixOS system — 2G ESP + LVM root";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.jim = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.default
        {
          disko.devices = {
            disk.main = {
              type = "disk";
              device = "/dev/sda";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    type = "EF00";
                    size = "2G";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                      mountOptions = ["umask=0077"];
                    };
                  };
                  root = {
                    size = "100%";
                    content = {
                      type = "lvm_pv";
                      vg = "pool";
                    };
                  };
                };
              };
            };
            lvm_vg.pool = {
              type = "lvm_vg";
              lvs.root = {
                size = "100%FREE";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = ["defaults" "noatime"];
                };
              };
            };
          };
        }
        ./configuration.nix
      ];
    };
  };
}
