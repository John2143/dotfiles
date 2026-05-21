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
    piSystem = "aarch64-linux";
    my-keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHjc0NNrHCwjrBUvUByFoFPW9vKGVFsWVD6LoKp1FLtNaIjyigMTYXoCKZSNNguKdNwUiyqKIZfCExZmgc3Cccw= phone"
    ];

    # All 3 server nodes are fully identical — drop-in replaceable.
    # Each runs k3s + PowerDNS. PostgreSQL runs inside k3s via CloudNativePG.
    mkServer = { compName }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs compName; sshKeys = my-keys; postgresHost = "127.0.0.1"; };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./modules/hetzner-disko.nix
        ./modules/hetzner-ssh.nix
        ./modules/hetzner-k3s-server.nix
        ./modules/tailscale.nix
      ];
    };

    # Agent nodes join the corresponding server's k3s cluster.
    mkAgent = { compName }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs compName; sshKeys = my-keys; };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./modules/hetzner-disko.nix
        ./modules/hetzner-ssh.nix
        ./modules/hetzner-k3s-agent.nix
        ./modules/tailscale.nix
      ];
    };
  in {
    nixosConfigurations = {
      # ── Server nodes (LA mode, 24/7) ──
      k3s-ashburn   = mkServer { compName = "k3s-ashburn";   };
      k3s-hillsboro = mkServer { compName = "k3s-hillsboro"; };
      k3s-nuremberg = mkServer { compName = "k3s-nuremberg"; };

      # ── Agent nodes (HA toggle, provisioned/destroyed via scripts) ──
      k3s-ashburn-agent   = mkAgent { compName = "k3s-ashburn-agent";   };
      k3s-hillsboro-agent = mkAgent { compName = "k3s-hillsboro-agent"; };
      k3s-nuremberg-agent = mkAgent { compName = "k3s-nuremberg-agent"; };

      # ── Home Pi (Headscale + PowerDNS) ──
      home-pi = nixpkgs.lib.nixosSystem {
        system = piSystem;
        specialArgs = { inherit inputs; compName = "home-pi"; sshKeys = my-keys; postgresHost = "k3s-ashburn.ts.9s.pics"; };
        modules = [
          agenix.nixosModules.default
          ./hosts/home-pi.nix
        ];
      };
    };
  };
}
