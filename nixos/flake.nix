{
  outputs = { self, nixpkgs }: {
    nixosConfigurations.office = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
