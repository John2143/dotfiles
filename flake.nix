{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.office = nixpkgs.lib.nixosSystem {
        system = "${system}";
        # extraSpecialArgs = {inherit inputs;};
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-configuration.nix
          ./nixos/office-configuration.nix
        ];
      };

      nixosConfigurations.arch = nixpkgs.lib.nixosSystem {
        system = "${system}";
        # extraSpecialArgs = {inherit inputs;};
        modules = [
          inputs.home-manager.nixosModules.default
          ./nixos/shared-configuration.nix
          ./nixos/arch-configuration.nix
        ];
      };
    };
}
