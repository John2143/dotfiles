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

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    max-jobs = 8;
    cores = 2;
    http-connections = 50;
    auto-optimise-store = true;
    keep-outputs = true;
    keep-derivations = true;
    extra-substituters = [
      "https://cache.numtide.com"
      "https://claude-code.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  nix.gc = {
    automatic = true;
    interval = {Weekday = 0; Hour = 3; Minute = 0;};
    options = "--delete-older-than 14d";
  };

  nix.registry.nixpkgs.flake = inputs.nixpkgs;

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
      inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

  programs.fish.enable = true;
  environment.shells = [pkgs.fish];

  security.pam.services.sudo_local.touchIdAuth = true;

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
      # "bruno"
      "krita"
      "obs"
      "vlc"
      # "warp"
      # "lens"
      # "insomnia"
      # "pgadmin4"
      # "plex"
      "mongodb-compass"
      # "keycastr"
      # "sage"
    ];
    brews = [
      # "probe-rs"
    ];
    taps = [
      # "probe-rs/probe-rs"
    ];
  };

  # macOS system preferences
  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      launchanim = false;
      orientation = "bottom";
      show-recents = false;
      static-only = true;
      tilesize = 36;
      mru-spaces = false;
      minimize-to-application = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXDefaultSearchScope = "SCcf";
      FXPreferredViewStyle = "Nlsv";
      _FXShowPosixPathInTitle = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;
      ApplePressAndHoldEnabled = false;
      NSWindowShouldDragOnGesture = true;
    };

    screencapture = {
      location = "~/Screenshots";
      type = "png";
      disable-shadow = true;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    menuExtraClock.Show24Hour = true;
    loginwindow.GuestEnabled = false;
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  system.activationScripts.postActivation.text = ''
    mkdir -p /Users/jschmidt/Screenshots
  '';

  users.users.jschmidt = {
    name = "jschmidt";
    home = "/Users/jschmidt";
    shell = pkgs.fish;
  };

  # Home Manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {inherit inputs;};
    users.jschmidt = import ./home-cli.nix;
  };

  ids.gids.nixbld = 30000;

  system.primaryUser = "jschmidt";
  system.stateVersion = 6;
}
