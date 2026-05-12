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
  nixpkgs.overlays = [
    (import ./overlays/claw-overlay.nix)
  ];

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
      # uv on PATH so my_claw (in fish-functions.nix) can `uvx litellm`
      # without needing a writeShellScriptBin nix-store substitution.
      pkgs.uv
      # omp wrapper: sandboxed via bubblewrap so a compromised binary can't
      # read /run/agenix/*, ~/.ssh, or the dotfiles secrets directory.
      # omp is a status display tool that doesn't need broad filesystem access.
      (let
        omp-src = pkgs.fetchFromGitHub {
          owner = "John2143";
          repo = "oh-my-pi";
          rev = "7f8fabf9e1eb5ac77b2021c03ff6ab776dd04a80";
          hash = "sha256-lLz19UZ99bEC3ZcMpPwmcDfrW2psnDRQRCFi2Sh68ok=";
        };
        omp-unwrapped = (inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp.overrideAttrs (old: {
          version = "14.9.3";
          src = omp-src;
          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            name = "omp-14.9.3-cargo-vendor";
            src = omp-src;
            hash = "sha256-lSWYXvk4w3QFt4FdlvAqdEJF8rV8CIfG35Mu3Iq7QFM=";
          };
          bunDeps = let
            bun2nix' = (pkgs.extend inputs.llm-agents.inputs.bun2nix.overlays.default).bun2nix;
          in bun2nix'.fetchBunDeps {
            bunNix = ./omp-bun.nix;
          };
        }));
      in
      pkgs.writeShellScriptBin "omp" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          ${omp-unwrapped}/bin/omp --system-prompt "$HOME/.omp/agent/system-prompt.md" "$@"
          # exec ${pkgs.bubblewrap}/bin/bwrap \
          #   --ro-bind /nix/store /nix/store \
          #   --ro-bind /etc/resolv.conf /etc/resolv.conf \
          #   --ro-bind /etc/ssl /etc/ssl \
          #   --ro-bind /etc/static /etc/static \
          #   --ro-bind /etc/passwd /etc/passwd \
          #   --ro-bind /etc/group /etc/group \
          #   --tmpfs /tmp --proc /proc --dev /dev \
          #   --setenv ANTHROPIC_API_KEY "''${ANTHROPIC_API_KEY:-}" \
          #   --setenv OPENAI_API_KEY "''${OPENAI_API_KEY:-}" \
          #   --setenv HOME "$HOME" \
          #   --setenv PATH "$PATH" \
          #   --setenv TERM "''${TERM:-xterm}" \
          #   --unshare-all --share-net --die-with-parent \
        ''
      )
      # claude wrapper: allowlist-style sandbox — explicitly bind only what
      # claude needs. Default-deny on $HOME, /run, and the rest of the host.
      #
      # Why allowlist (vs. broad bind + tmpfs masks): all of these are
      # john-readable on this host and would otherwise be exfiltratable:
      #   /run/agenix/llm-admin-keys           (admin LLM keys we walled off in Phase A)
      #   /run/agenix/rustfs-credentials       (S3/object-store credentials)
      #   /run/agenix/gocryptfs-passphrase     (NAS encrypted-vault passphrase)
      #   /run/agenix/hass-credentials         (Home Assistant API, on arch)
      #   $HOME/.ssh/age                       (agenix MASTER decryption key)
      #   $HOME/.ssh/id_*                      (SSH private keys)
      #   $HOME/.gnupg/private-keys-v1.d/*     (GPG private keys)
      # The agenix master key alone would let a compromised binary decrypt
      # every .age file on disk, including root-owned secrets (restic,
      # backup-ssh, k3s, smb). Allowlist binding eliminates this entire class.
      (let
        claude-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      in
        pkgs.writeShellScriptBin "claude" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          # Ensure claude's state dir exists so --bind succeeds.
          mkdir -p "$HOME/.claude"
          ${claude-unwrapped}/bin/claude "$@"
          # exec ${pkgs.bubblewrap}/bin/bwrap \
          #   --ro-bind /nix/store /nix/store \
          #   --ro-bind /etc/resolv.conf /etc/resolv.conf \
          #   --ro-bind /etc/ssl /etc/ssl \
          #   --ro-bind /etc/static /etc/static \
          #   --ro-bind /etc/passwd /etc/passwd \
          #   --ro-bind /etc/group /etc/group \
          #   --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
          #   --ro-bind-try /etc/hosts /etc/hosts \
          #   --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig" \
          #   --ro-bind-try "$HOME/.config/git" "$HOME/.config/git" \
          #   --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix" \
          #   --bind "$HOME/.claude" "$HOME/.claude" \
          #   --bind "$PWD" "$PWD" \
          #   --chdir "$PWD" \
          #   --tmpfs /tmp --proc /proc --dev /dev \
          #   --setenv ANTHROPIC_API_KEY "''${ANTHROPIC_API_KEY:-}" \
          #   --setenv HOME "$HOME" \
          #   --setenv PATH "$PATH" \
          #   --setenv TERM "''${TERM:-xterm}" \
          #   --unsetenv ANTHROPIC_ADMIN_KEY \
          #   --unsetenv OPENAI_ADMIN_KEY \
          #   --unshare-all --share-net --die-with-parent \
          #  ${claude-unwrapped}/bin/claude "$@"
        '')
      # claw wrapper: sources runtime API keys from agenix. No sandboxing
      # yet (same pattern as claude/omp — bwrap commented out for now).
      (let
        claw-unwrapped = pkgs.claw;
      in
        pkgs.writeShellScriptBin "claw" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          exec ${claw-unwrapped}/bin/claw "$@"
        '')
      (pkgs.writeShellScriptBin "ollama-sync" ''
        set -euo pipefail
        # --chmod forces 0644/0755 on the destination regardless of source mode.
        # The NAS daemon historically created 0600 manifests/blobs (umask 0077),
        # which break the local daemon's runner subprocess under
        # ProtectSystem=strict + NoNewPrivileges — symptom is `bad manifest …
        # permission denied` and the model vanishing from `ollama list` even
        # though john owns the files.
        exec sudo -E ${pkgs.rsync}/bin/rsync -ahP --delete \
          --chown=john:users \
          --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
          --rsh="sudo -u john ${pkgs.openssh}/bin/ssh" \
          nas:/neo/ollama/models/ /var/lib/ollama/models/
      '')
    ]
    ++ lib.optionals (builtins.elem config.networking.hostName ["office" "arch"]) [
      # Vast.ai CLI wrapper. Loads VAST_API_KEY from /run/agenix/vast-credentials
      # (encrypted file declared above — also carries the SSH private key
      # consumed by the _vast-load fish helper) and runs the upstream PyPI
      # CLI via uvx — cached at ~/.cache/uv after first invocation, ~5s warm-up.
      #
      # Full workflow lives in ../Vast.md. Common tasks have fish helpers
      # in home-cli.nix:
      #   vast-search    — list verified B200 offers
      #   vast-create    — launch with our minimal CUDA image, 300GB disk
      #   vast-show      — list active rentals
      #   vast-destroy   — tear down a rental
      # Anything else (account info, billing, raw filters, etc.):
      #   vastai show user
      #   vastai search offers '<query>' -o '<sort>'
      #   vastai logs <instance_id>
      #   etc. — see `vastai --help` or https://vast.ai/docs/cli/
      (pkgs.writeShellScriptBin "vastai" ''
        if [ -f /run/agenix/vast-credentials ]; then
          set -a
          . /run/agenix/vast-credentials
          set +a
        fi
        exec ${pkgs.uv}/bin/uvx --quiet vastai "$@"
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

  # Admin key (ANTHROPIC_ADMIN_KEY) — sourced by `llm-load-keys` for interactive
  # `llm-costs` and `llm-topup-anthropic` use. Never mounted on pite.
  age.secrets.llm-admin-keys =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/llm-admin-keys.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # Vast.ai credentials (combined API key + SSH private key, see
  # secrets/secrets.nix for format). Sourced by:
  #   - the `vastai` wrapper below (reads VAST_API_KEY)
  #   - the _vast-load fish helper in home-cli.nix (reads
  #     VAST_SSH_PRIVATE_KEY_B64, materializes it to /run/user/$UID/...)
  age.secrets.vast-credentials =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/vast-credentials.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  security.rtkit.enable = true;
  services.udisks2.enable = true;

  # ArgoCD admin password — auto-login for `argocd` CLI.
  age.secrets.argo-admin-password =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch" "closet"])
    {
      file = ../secrets/argo-admin-password.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
