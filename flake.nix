{
  inputs = {
    #nixpkgs.url = "github:John2143/nixpkgs/johnpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, disko, ... }@inputs:
    let
      system = "x86_64-linux";
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
        ];
      };

      nixosConfigurations.livecd = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/livecd-configuration.nix
        ];
      };

      nixosConfigurations.closet = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          #./nixos/simple-efi.nix
          #disko.nixosModules.disko
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/closet-configuration.nix
        ];
      };

      nixosConfigurations.rpi4b = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          disko.nixosModules.disko
          ./nixos/simple-efi.nix
          { disko.devices.disk.my-disk.device = "/dev/mmcblk0"; }

          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/rpi4b-configuration.nix
        ];
      };

      #images.rpi1 = nixosConfigurations.rpi1.config.system.build.sdImage;
    };
}
