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

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #disko = {
      #url = "github:nix-community/disko";
      #inputs.nixpkgs.follows = "nixpkgs";
    #};
  };

  outputs =
    { nixpkgs, nix-cachyos-kernel, agenix, ... }@inputs:
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
      my-keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHjc0NNrHCwjrBUvUByFoFPW9vKGVFsWVD6LoKp1FLtNaIjyigMTYXoCKZSNNguKdNwUiyqKIZfCExZmgc3Cccw= phone"
      ];
    in
    rec {
      formatter.x86_64-linux = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      nixosConfigurations.office = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "office";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          agenix.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/shared-games-configuration.nix
          ./nixos/office-configuration.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix
        ];
      };

      nixosConfigurations.arch = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "arch";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          agenix.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/shared-games-configuration.nix
          ./nixos/arch-configuration.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix
        ];
      };

      nixosConfigurations.closet = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "closet";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/closet-configuration.nix
          ./nixos/tailscale.nix
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
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/security-configuration.nix
          ./nixos/tailscale.nix
        ];
      };

      nixosConfigurations.pite = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "pite";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          agenix.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/remote-cli-config.nix
          #./nixos/shared-configuration.nix
          #./nixos/security-configuration.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix
        ];
      };

      nixosConfigurations.aman = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "aman";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/remote-cli-config.nix
          #./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix
        ];
      };

      nixosConfigurations.term = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = "term";
          sshKeys = my-keys;
        };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/security-configuration.nix
          #./nixos/remote-cli-config.nix
          #./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix
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
