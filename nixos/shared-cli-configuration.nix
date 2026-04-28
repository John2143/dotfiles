# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  ...
}: {
  # flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.extra-substituters = ["https://cache.numtide.com"];
  nix.settings.extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  #nix.gc.automatic = true;

  # setup my two input channels
  nixpkgs.config = {
    allowUnfree = true;
  };

  _module.args.pkgs-stable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit (config.nixpkgs) config;
  };

  # shutdown faster
  #systemd.extraConfig = ''
  #DefaultTimeoutStopSec=10s
  #'';

  environment.systemPackages = with pkgs;
    [
      git
      fish
      wget
      curl
      tmux
      vim
      btop
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals (builtins.elem config.networking.hostName ["office" "arch"]) [
      (let
        omp-unwrapped = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
      in
        pkgs.writeShellScriptBin "omp" ''
          if [ -f /run/agenix/llm-api-keys ]; then
            set -a
            . /run/agenix/llm-api-keys
            set +a
          fi
          exec ${omp-unwrapped}/bin/omp "$@"
        '')
      (pkgs.writeShellScriptBin "ollama-sync" ''
        set -euo pipefail
        exec sudo -E ${pkgs.rsync}/bin/rsync -ahP --delete \
          --chown=john:users \
          --rsh="sudo -u john ${pkgs.openssh}/bin/ssh" \
          nas:/tank/share/ollama/models/ /var/lib/ollama/models/
      '')
    ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    package = pkgs-stable.openssh;
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  # RustFS credentials for juush/bigjuush file sharing
  age.identityPaths = ["/home/john/.ssh/age"];
  age.secrets.rustfs-credentials =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch" "nas" "closet"])
    {
      file = ../secrets/rustfs-credentials.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  age.secrets.llm-api-keys =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/llm-api-keys.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  security.rtkit.enable = true;
  services.udisks2.enable = true;

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
