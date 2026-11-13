{
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

  home.packages =
    (with pkgs; [
      alacritty
      firefox
      discord
      imagemagick
      kind
      doctl
      hcloud
      rclone
      velero
      e1s
      openrct2
      gdtoolkit_4
      temurin-jre-bin-21
      (prismlauncher.override {jdks = [temurin-bin-17];})
      python3
      uv
      desec-dns
      pkgs-stable.yt-dlp
    ])
    ++ [omp claude];

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
}
