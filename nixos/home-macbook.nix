{
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  ...
}: let
  # omp wrapper: sources runtime keys from agenix and forces the local OAuth
  # subscription path, mirroring nixos/shared-cli-configuration.nix.
  omp = let
    omp-unwrapped = inputs.oh-my-pi.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  in
    pkgs.writeShellScriptBin "omp" ''
      if [ -f /run/agenix/llm-runtime-keys ]; then
        set -a
        . /run/agenix/llm-runtime-keys
        set +a
      fi
      if [ -z "$LITELLM_EDITOR_KEY" ]; then
        echo "omp: LITELLM_EDITOR_KEY missing from /run/agenix/llm-runtime-keys" >&2
        exit 1
      fi
      # Force Anthropic through the locally stored OAuth subscription;
      # an inherited platform key would otherwise enable billed fallback.
      unset ANTHROPIC_API_KEY
      if [ -f /run/agenix/ntfy-topic-url ]; then
        set -a
        . /run/agenix/ntfy-topic-url
        set +a
      fi
      ${omp-unwrapped}/bin/omp "$@"
    '';

  # claude wrapper: routes Claude Code through the LiteLLM proxy with the
  # subscription OAuth token in Authorization and the proxy key in
  # x-litellm-api-key, mirroring nixos/shared-cli-configuration.nix.
  claude = let
    claude-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in
    pkgs.writeShellScriptBin "claude" ''
      if [ -f /run/agenix/llm-runtime-keys ]; then
        set -a
        . /run/agenix/llm-runtime-keys
        set +a
      fi
      if [ -z "$LITELLM_EDITOR_KEY" ]; then
        echo "claude: LITELLM_EDITOR_KEY missing from /run/agenix/llm-runtime-keys" >&2
        exit 1
      fi
      export ANTHROPIC_BASE_URL="https://llm.2143.me"
      export ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $LITELLM_EDITOR_KEY"
      # An inherited platform key would win over the subscription login.
      unset ANTHROPIC_API_KEY
      # Ensure claude's state dir exists so --bind succeeds.
      mkdir -p "$HOME/.claude"
      ${claude-unwrapped}/bin/claude "$@"
    '';
in {
  imports = [./home-cli.nix];

  # Home Manager links apps as one directory symlink into the store, which
  # Spotlight and Launchpad do not index. GUI apps come from Homebrew casks
  # instead, so they land as real bundles in /Applications.
  targets.darwin.linkApps.enable = false;

  home.packages =
    (with pkgs; [
      alacritty
      openrct2
      imagemagick
      kind
      doctl
      hcloud
      rclone
      velero
      e1s
      gdtoolkit_4
      temurin-jre-bin-21
      python3
      uv
      desec-dns
      pkgs-stable.yt-dlp
    ])
    ++ [omp claude];

  # Ollama runs as a per-user launchd agent on 127.0.0.1:11434; models live in
  # ~/.ollama, so they are outside the nix store and survive garbage collection.
  services.ollama = {
    enable = true;
    # 16 GiB unified memory: keep a single model resident, quantize the KV cache
    # and use flash attention (the same tuning Homebrew's service unit applies).
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };

  # Home Manager's ollama module sets ProcessType = "Background", so launchd
  # throttles CPU and I/O: measured 18 tok/s that way versus 43 at Standard on
  # this machine. Standard is the launchd default and applies no such limits.
  launchd.agents.ollama.config.ProcessType = lib.mkForce "Standard";

  xdg.configFile = {
    # Read at the top of .config/fish/config.fish before any platform block.
    "fish/host-profile.fish".text = ''
      set -gx DOTFILES_PROFILE personal
      set -gx DOTFILES_DARWIN_FLAKE "$HOME/dotfiles#${compName}"
    '';

    # Standalone config: the repo config imports the Linux theme-switch palette,
    # which this host does not run.
    "alacritty/alacritty.toml".text = ''
      [general]
      live_config_reload = true

      [font]
      size = 14

        [font.normal]
        family = "JetBrainsMono Nerd Font"

        [font.offset]
        x = 0
        y = -3

      [window.padding]
      x = 5
      y = 5
    '';
  };

  # Homebrew's alacritty/openrct2 casks are disabled (Gatekeeper) and a store
  # symlink is invisible to Spotlight/Launchpad. Copy the bundles so they are
  # real apps in ~/Applications.
  home.activation.installAppBundles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run mkdir -p "$HOME/Applications"
    # Earlier copies inherit read-only store permissions; make them writable
    # before replacing them.
    run chmod -R u+w "$HOME/Applications" || true
    run rm -rf "$HOME/Applications/Alacritty.app" "$HOME/Applications/OpenRCT2.app"
    run /usr/bin/ditto --noqtn ${pkgs.alacritty}/Applications/Alacritty.app "$HOME/Applications/Alacritty.app"
    # The store bundle points Contents/MacOS at a relative ../../../bin, which
    # dangles once copied; put a real executable in its place.
    run chmod -R u+w "$HOME/Applications/Alacritty.app"
    run rm -f "$HOME/Applications/Alacritty.app/Contents/MacOS"
    run mkdir -p "$HOME/Applications/Alacritty.app/Contents/MacOS"
    run cp ${pkgs.alacritty}/bin/alacritty "$HOME/Applications/Alacritty.app/Contents/MacOS/alacritty"
    run chmod u+w "$HOME/Applications/Alacritty.app/Contents/MacOS/alacritty"
    run /usr/bin/ditto --noqtn ${pkgs.openrct2}/Applications/OpenRCT2.app "$HOME/Applications/OpenRCT2.app"
  '';
}
