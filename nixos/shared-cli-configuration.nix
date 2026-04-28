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

  nix.settings.extra-substituters = [
    "https://cache.numtide.com"
    "https://claude-code.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
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
    ++ lib.optionals (builtins.elem config.networking.hostName ["office" "arch" "pite"]) [
      # omp wrapper: sandboxed via bubblewrap so a compromised binary can't
      # read /run/agenix/*, ~/.ssh, or the dotfiles secrets directory.
      # omp is a status display tool that doesn't need broad filesystem access.
      (let
        omp-unwrapped = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
      in
        pkgs.writeShellScriptBin "omp" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          exec ${pkgs.bubblewrap}/bin/bwrap \
            --ro-bind /nix/store /nix/store \
            --ro-bind /etc/resolv.conf /etc/resolv.conf \
            --ro-bind /etc/ssl /etc/ssl \
            --ro-bind /etc/static /etc/static \
            --ro-bind /etc/passwd /etc/passwd \
            --ro-bind /etc/group /etc/group \
            --tmpfs /tmp --proc /proc --dev /dev \
            --setenv ANTHROPIC_API_KEY "''${ANTHROPIC_API_KEY:-}" \
            --setenv OPENAI_API_KEY "''${OPENAI_API_KEY:-}" \
            --setenv HOME "$HOME" \
            --setenv PATH "$PATH" \
            --setenv TERM "''${TERM:-xterm}" \
            --unshare-all --share-net --die-with-parent \
            ${omp-unwrapped}/bin/omp "$@"
        '')
      # claude wrapper: lighter sandbox — claude needs to edit project files
      # and run dev tools, so we use "bind / and mask" rather than build-up.
      # Critical secrets directories are masked with tmpfs.
      (let
        claude-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      in
        pkgs.writeShellScriptBin "claude" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          # Mask the highest-value secret paths. The .age files in dotfiles/secrets
          # are encrypted blobs and the host SSH key (used to decrypt them) is
          # root-readable only, so we don't bother masking the dotfiles repo.
          exec ${pkgs.bubblewrap}/bin/bwrap \
            --bind / / \
            --dev-bind /dev /dev \
            --tmpfs /run/agenix \
            --tmpfs "$HOME/.ssh" \
            --tmpfs "$HOME/.gnupg" \
            --setenv ANTHROPIC_API_KEY "''${ANTHROPIC_API_KEY:-}" \
            --unsetenv ANTHROPIC_ADMIN_KEY \
            --unsetenv OPENAI_ADMIN_KEY \
            --die-with-parent \
            ${claude-unwrapped}/bin/claude "$@"
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

  # Legacy combined keys file. Kept mounted on office/arch during transition.
  # Remove after both hosts have rebuilt against llm-runtime-keys/llm-admin-keys
  # and the wrappers stop referencing /run/agenix/llm-api-keys.
  age.secrets.llm-api-keys =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/llm-api-keys.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # Runtime keys (ANTHROPIC_API_KEY, OPENAI_API_KEY) — sourced by omp/claude
  # wrappers. On pite this declaration is overridden in nixos/pite-canary.nix
  # to point at the bait .age file at the same /run/agenix/llm-runtime-keys path.
  age.secrets.llm-runtime-keys =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch" "pite"])
    {
      file = ../secrets/llm-runtime-keys.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # Admin keys (ANTHROPIC_ADMIN_KEY, OPENAI_ADMIN_KEY) — only sourced by
  # `llm-load-keys` for interactive `llm-costs` use. Never mounted on pite.
  age.secrets.llm-admin-keys =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/llm-admin-keys.age;
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
