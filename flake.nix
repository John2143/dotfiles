{
  inputs = {
    #nixpkgs.url = "github:John2143/nixpkgs/johnpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nix-cachyos-kernel.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #disko = {
      #url = "github:nix-community/disko";
      #inputs.nixpkgs.follows = "nixpkgs";
    #};
  };

  outputs =
    { nixpkgs, nix-cachyos-kernel, ... }@inputs:
    let
      system = "x86_64-linux";
      catchy-os = [
        ({ pkgs, ... }:
        {
          nixpkgs.overlays = [
             nix-cachyos-kernel.overlays.default
             #nix-cachyos-kernel.overlays.pinned
          ];
        })
        ({ pkgs, ... }:
        {
          boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
          #hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
        })
      ];
    in
    rec {
      formatter.x86_64-linux = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      nixosConfigurations.office = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "office";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/office-configuration.nix
        ];
      };

      nixosConfigurations.arch = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "arch";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/arch-configuration.nix
          ({ config, ... }:
          {
            hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
          })
        ];
      };

      nixosConfigurations.closet = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "closet";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/closet-configuration.nix
        ];
      };

      #nixosConfigurations.rpi4b = nixpkgs.lib.nixosSystem {
        #system = "aarch64-linux";
        #modules = [
          #disko.nixosModules.disko
          #./nixos/simple-efi.nix
          #{ disko.devices.disk.my-disk.device = "/dev/mmcblk0"; }

          #inputs.home-manager.nixosModules.default
          #./nixos/shared-cli-configuration.nix
          #./nixos/rpi4b-configuration.nix
        #];
      #};

      #images.rpi1 = nixosConfigurations.rpi1.config.system.build.sdImage;
    };
}
