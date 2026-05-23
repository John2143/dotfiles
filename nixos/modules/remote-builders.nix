{
  config,
  lib,
  pkgs,
  ...
}: let
  # All x86_64-linux builders in the cluster.
  # Capabilities: kvm = can run VMs, nixos-test = can run NixOS tests,
  # cuda = has CUDA toolkit, big-parallel = can handle large builds.
  builderDefs = {
    office = {
      maxJobs = 6;
      system = "x86_64-linux";
      supportedFeatures = ["kvm" "nixos-test" "big-parallel"];
    };
    arch = {
      maxJobs = 2;
      system = "x86_64-linux";
      supportedFeatures = ["cuda" "big-parallel"];
    };
    nas = {
      maxJobs = 2;
      system = "x86_64-linux";
      supportedFeatures = [];
    };
  };

  isBuilder = builtins.elem config.networking.hostName
    (builtins.attrNames builderDefs);

  mkMachine = name: def: {
    hostName = "${name}.local";
    sshUser = "nixbuild";
    sshKey = config.age.secrets.build-cluster-key.path;
    inherit (def) maxJobs system supportedFeatures;
  };

  # Every builder EXCEPT self — don't SSH into yourself.
  isNotSelf = m: m.hostName != "${config.networking.hostName}.local";

  buildMachines = builtins.filter isNotSelf
    (lib.mapAttrsToList mkMachine builderDefs);
in {
  nix.distributedBuilds = true;
  nix.buildMachines = buildMachines;
  nix.settings.builders-use-substitutes = true;

  # Lower CPU scheduling priority on builders so remote builds
  # don't disrupt interactive use (gaming, desktop apps).
  nix.daemonCPUSchedPolicy = lib.mkIf isBuilder "idle";

  # ── Shared cluster SSH key ───────────────────────────────────────
  # One keypair for all cluster SSH. Private key deployed via agenix
  # to every x86_64 machine; public key in nixbuild's authorized_keys.
  age.secrets.build-cluster-key = {
    file = ../../secrets/build-cluster-key.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # ── Builder-only: nixbuild user to accept connections ────────────
  users.users.nixbuild = lib.mkIf isBuilder {
    isSystemUser = true;
    group = "nixbuild";
    shell = pkgs.bash;
    createHome = false;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+dLtM35wMPfnsd7krzS8lXcKzi7b1A2OEtJi8viHMz build-cluster"
    ];
  };
  users.groups.nixbuild = lib.mkIf isBuilder {};

  # nixbuild needs store write access to accept remote build results.
  nix.settings.trusted-users = lib.mkIf isBuilder ["nixbuild"];
}