{
  config,
  lib,
  pkgs,
  inputs,
  compName,
  sshKeys,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

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

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (import ./overlays/claw-overlay.nix)
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
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ [
      (let
        claude-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      in
        pkgs.writeShellScriptBin "claude" ''
          if [ -f /run/agenix/llm-runtime-keys ]; then
            set -a
            . /run/agenix/llm-runtime-keys
            set +a
          fi
          mkdir -p "$HOME/.claude"
          ${claude-unwrapped}/bin/claude "$@"
        '')
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
    ];

  programs.fish.enable = true;
  environment.shells = [pkgs.fish];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # agenix secrets
  age.identityPaths = ["/Users/jschmidt/.ssh/age"];
  age.secrets.llm-runtime-keys = {
    file = ../secrets/llm-runtime-keys.age;
    mode = "0400";
    owner = "jschmidt";
    group = "staff";
  };
  age.secrets.llm-admin-keys = {
    file = ../secrets/llm-admin-keys.age;
    mode = "0400";
    owner = "jschmidt";
    group = "staff";
  };

  # Declarative homebrew for GUI apps without nix equivalents
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "zap";
    };
    casks = [
      "bruno"
      "krita"
      "obs"
      "vlc"
      "warp"
      "lens"
      "insomnia"
      "pgadmin4"
      "plex"
      "mongodb-compass"
      "keycastr"
      "sage"
    ];
    brews = [
      "probe-rs"
    ];
    taps = [
      "probe-rs/probe-rs"
    ];
  };

  # macOS system preferences
  system.defaults = {
    dock.autohide = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  users.users.jschmidt = {
    name = "jschmidt";
    home = "/Users/jschmidt";
    shell = pkgs.fish;
  };

  # Home Manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs;};
    users.jschmidt = import ./home-cli.nix;
  };

  networking.hostName = compName;

  system.primaryUser = "jschmidt";
  system.stateVersion = 6;
}
