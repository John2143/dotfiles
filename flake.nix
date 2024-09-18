{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.office = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-configuration.nix
          ./nixos/office-configuration.nix
        ];
      };

      nixosConfigurations.arch = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-configuration.nix
          ./nixos/arch-configuration.nix
        ];
      };

      nixosConfigurations.closet = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-configuration.nix
          ./nixos/closet-configuration.nix
        ];
      };
    };
}
