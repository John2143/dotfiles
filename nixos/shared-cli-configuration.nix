# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  ...
}: {
  # flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    persistent = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;

  # setup my two input channels
  nixpkgs.config = {
    allowUnfree = true;
  };
  nixpkgs.overlays = [
    (import ./overlays/claw-overlay.nix)
    (final: prev: {
      btop =
        if compName == "office"
        then prev.btop.override {rocmSupport = true;}
        else if compName == "arch"
        then prev.btop.override {cudaSupport = true;}
        else prev.btop;
    })
  ];

  _module.args.pkgs-stable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit (config.nixpkgs) config;
  };

  environment.systemPackages = with pkgs;
    [
      git
      fish
      wget
      curl
      tmux
      vim
      btop
      aha
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals (builtins.elem config.networking.hostName ["office" "arch"]) [
      # uv on PATH so my_claw (in fish-functions.nix) can `uvx litellm`
      # without needing a writeShellScriptBin nix-store substitution.
      pkgs.uv
      pkgs.attic-client
      # omp wrapper: consumes the fork's own flake (John2143/oh-my-pi#omp).
      # Bump via `nix flake update oh-my-pi`. All build hashes (cargoHash,
      # bun.nix) live in the fork.
      (
        let
          omp-unwrapped = inputs.oh-my-pi.packages.${pkgs.stdenv.hostPlatform.system}.omp;
        in
          pkgs.writeShellScriptBin "omp" ''
            if [ -f /run/agenix/llm-runtime-keys ]; then
              set -a
              . /run/agenix/llm-runtime-keys
              set +a
            fi
            if [ -f /run/agenix/ntfy-topic-url ]; then
              set -a
              . /run/agenix/ntfy-topic-url
              set +a
            fi
            ${omp-unwrapped}/bin/omp --system-prompt "$HOME/.omp/agent/system-prompt.md" "$@"
            ## exec ${pkgs.bubblewrap}/bin/bwrap \
            ##   --ro-bind /nix/store /nix/store \
            ##   --ro-bind /etc/resolv.conf /etc/resolv.conf \
            ##   --ro-bind /etc/ssl /etc/ssl \
            ##   --ro-bind /etc/static /etc/static \
            ##   --ro-bind /etc/passwd /etc/passwd \
            ##   --ro-bind /etc/group /etc/group \
            ##   --tmpfs /tmp --proc /proc --dev /dev \
            ##   --setenv ANTHROPIC_API_KEY "''${ANTHROPIC_API_KEY:-}" \
            ##   --setenv OPENAI_API_KEY "''${OPENAI_API_KEY:-}" \
            ##   --setenv HOME "$HOME" \
            ##   --setenv PATH "$PATH" \
            ##   --setenv TERM "''${TERM:-xterm}" \
            ##   --unshare-all --share-net --die-with-parent \
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

      # Bash wrappers for fish helpers — so they work from bash/omp harness too.
      (pkgs.writeShellScriptBin "mikrotik-connect" ''
        exec fish -c 'mikrotik-connect $argv' -- "$@"
      '')
      (pkgs.writeShellScriptBin "juush" ''
        exec fish -c 'juush $argv' -- "$@"
      '')
      (pkgs.writeShellScriptBin "bigjuush" ''
        exec fish -c 'bigjuush $argv' -- "$@"
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
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/llm-runtime-keys.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # ntfy.sh topic URL for agent notifications. Sourced by omp wrapper
  # so the agent can ping the user when blocked.
  age.secrets.ntfy-topic-url =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/ntfy-topic-url.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # Home Assistant long-lived access token. Used by omp system prompt for
  # critical iOS notifications (bypasses Do Not Disturb / mute).
  age.secrets.hass-credentials =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/hass-credentials.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

  # Admin key (ANTHROPIC_ADMIN_KEY) — sourced by `llm-unsafe-load-admin-keys` for interactive
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

  # MikroTik router + switches (upstairs/downstairs) SSH key.
  # Decrypted by the mikrotik-connect fish helper on first use.
  # Format: MIKROTIK_SSH_PRIVATE_KEY_B64=<base64 ed25519 private key>
  # Generate: ssh-keygen -t ed25519 -f /tmp/mikrotik-key -N ""
  age.secrets.mikrotik-credentials =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/mikrotik-credentials.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };
  # UniFi controller credentials — username + password for API access.
  # Format: UNIFI_USERNAME=... UNIFI_PASSWORD=... UNIFI_CONTROLLER=https://192.168.5.10:30443
  # Used by fish functions unifi-status, unifi-clients, unifi-ap.
  age.secrets.unifi-credentials =
    lib.mkIf
    (builtins.elem config.networking.hostName ["office" "arch"])
    {
      file = ../secrets/unifi-credentials.age;
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

  # Firewall enabled — NixOS opens SSH, Tailscale, Avahi automatically.
  # Tailscale interface trusted so tailnet traffic bypasses the firewall.
  # Per-host ports (k3s, ollama-cpu, gRPC, etc.) configured in host files.
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["tailscale0"];
  };

  # Balanced shutdown — systemd waits up to 30s for services before SIGKILL
  # (10s was too tight for iscsid to cleanly logout iSCSI sessions on reboot)
  systemd.settings.Manager.DefaultTimeoutStopSec = "30s";
  # ── Node Exporter (Prometheus metrics) ──
  # Scraped by pite Prometheus for home cluster monitoring.
  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true; # port 9100
  };
}
