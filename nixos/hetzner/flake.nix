{
  description = "Hetzner Enterprise HA Platform — 6 k3s nodes + Home Pi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    agenix,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    my-keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHjc0NNrHCwjrBUvUByFoFPW9vKGVFsWVD6LoKp1FLtNaIjyigMTYXoCKZSNNguKdNwUiyqKIZfCExZmgc3Cccw= phone"
    ];
  in {
    nixosConfigurations.k3s-ashburn = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-ashburn";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/ashburn-server.nix
        ./modules/tailscale.nix
      ];
    };

    nixosConfigurations.k3s-ashburn-agent = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-ashburn-agent";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/ashburn-agent.nix
        ./modules/tailscale.nix
      ];
    };

    nixosConfigurations.k3s-hillsboro = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-hillsboro";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/hillsboro-server.nix
        ./modules/tailscale.nix
      ];
    };

    nixosConfigurations.k3s-hillsboro-agent = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-hillsboro-agent";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/hillsboro-agent.nix
        ./modules/tailscale.nix
      ];
    };

    nixosConfigurations.k3s-nuremberg = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-nuremberg";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/nuremberg-server.nix
        ./modules/tailscale.nix
      ];
    };

    nixosConfigurations.k3s-nuremberg-agent = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        compName = "k3s-nuremberg-agent";
        sshKeys = my-keys;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./hosts/nuremberg-agent.nix
        ./modules/tailscale.nix
      ];
    };
  };
}
