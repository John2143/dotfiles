{
  description = "Jim's first NixOS system — 2G ESP + LVM root";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lidarr = {
      url = "github:John2143/Lidarr/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, lidarr, ... }: {
    nixosConfigurations.jim = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
      ];
      specialArgs = { inherit lidarr; };
    };
  };
}
