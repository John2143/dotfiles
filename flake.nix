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
          ./nixos/shared-games-configuration.nix
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
          ./nixos/shared-games-configuration.nix
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

      nixosConfigurations.strradmsad = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "strradmsad";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/strradmsad-configuration.nix
        ];
      };

      nixosConfigurations.security = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "security";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/security-configuration.nix
        ];
      };

      nixosConfigurations.pite = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "pite";
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/security-configuration.nix
        ];
      };

      #nixosConfigurations.security = nixpkgs.lib.nixosSystem {
        #system = "aarch64-linux";
        #modules = [
          #({ config, pkgs, lib, ...}:
          #{
              #imports =
                #[
                  #<nixos-hardware/raspberry-pi/4>
                  #./hardware-configuration.nix
                #];
              #hardware = {
                #raspberry-pi."4".apply-overlays-dtmerge.enable = true;
                #deviceTree = {
                  #enable = true;
                  #filter = "*rpi-4-*.dtb";
                #};
              #};
              #console.enable = false;
              #environment.systemPackages = with pkgs; [
                #libraspberrypi
                #raspberrypi-eeprom
              #];
              #system.stateVersion = "25.11";
          #})
          #({ pkgs, ... }:
            #{
              #imports = [
                #.../nixos-hardware/raspberry-pi/4
              #];

              #hardware.raspberry-pi."4".fkms-3d.enable = true;

              #services.xserver = {
                #enable = true;
                #displayManager.lightdm.enable = true;
                #desktopManager.gnome.enable = true;
              #};
          #})

        #];
      #};

      #images.security = nixosConfigurations.security.config.system.build.sdImage;
    };
}
