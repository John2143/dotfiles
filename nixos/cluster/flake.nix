{
  description = "Multi-Cloud k3s Platform — OpenTofu-provisioned clusters + Home Pi";
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFNmxHc5ArL5bnSMgF3tRpXquIRSFQ67TJ1Phvi2xvxG k3s-multi-cloud-provisioning"
    ];

    # k3s server nodes — cloud-agnostic, OpenTofu-provisioned.
    # DNS via deSEC.io (NS delegation + A records). cert-manager uses deSEC webhook for DNS01.
    mkServer = { compName, rawIP ? null, diskDevice ? "/dev/sda", useEFI ? true, extraModules ? [ ] }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs compName rawIP diskDevice useEFI; sshKeys = my-keys; };

      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./modules/disko.nix
        ./modules/ssh.nix
        ./modules/k3s-server.nix
        ./modules/tailscale.nix
      ] ++ extraModules;
    };

    # Agent nodes join the corresponding server's k3s cluster.
    mkAgent = { compName, diskDevice ? "/dev/sda", useEFI ? true, extraModules ? [ ] }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs compName diskDevice useEFI; sshKeys = my-keys; };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./modules/disko.nix
        ./modules/ssh.nix
        ./modules/k3s-agent.nix
        ./modules/tailscale.nix
      ] ++ extraModules;
    };
  in {
    nixosConfigurations = {
      # ── Server nodes (LA mode, 24/7) ──
      hetzner-ashburn-k3s   = mkServer { compName = "hetzner-ashburn-k3s"; };
      hetzner-hillsboro-k3s = mkServer { compName = "hetzner-hillsboro-k3s"; };
      do-nyc-k3s            = mkServer { compName = "do-nyc-k3s"; diskDevice = "/dev/vda"; useEFI = false; extraModules = [ ./modules/digitalocean.nix ]; };


      # ── Agent nodes (HA toggle, OpenTofu-provisioned) ──
      hetzner-ashburn-k3s-agent   = mkAgent { compName = "hetzner-ashburn-k3s-agent"; };
      hetzner-hillsboro-k3s-agent = mkAgent { compName = "hetzner-hillsboro-k3s-agent"; };
      do-nyc-k3s-agent            = mkAgent { compName = "do-nyc-k3s-agent"; diskDevice = "/dev/vda"; useEFI = false; extraModules = [ ./modules/digitalocean.nix ]; };

      # ── Home Pi (Headscale) ──
      home-pi = nixpkgs.lib.nixosSystem {
        system = piSystem;
        specialArgs = { inherit inputs; compName = "home-pi"; sshKeys = my-keys; };
        modules = [
          agenix.nixosModules.default
          ./hosts/home-pi.nix
        ];
      };
    };
  };
}