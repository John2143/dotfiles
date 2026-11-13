{
  pkgs,
  pkgs-stable,
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

  networking.hostName = compName;
  networking.computerName = "John’s MacBook Pro";
  networking.localHostName = "Johns-MacBook-Pro";

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (final: prev: {
      desec-dns = final.callPackage ./packages/desec-dns.nix {};
    })
  ];

  _module.args.pkgs-stable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {allowUnfree = true;};
  };

  environment.systemPackages = with pkgs; [
    git
    fish
    wget
    curl
    tmux
    vim
    btop
    tesseract
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.fish.enable = true;
  environment.shells = [pkgs.fish];

  services.openssh.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  age.identityPaths = ["/Users/john/.ssh/age"];
  age.secrets.llm-runtime-keys = {
    file = ../secrets/llm-runtime-keys.age;
    mode = "0400";
    owner = "john";
    group = "staff";
  };
  age.secrets.llm-admin-keys = {
    file = ../secrets/llm-admin-keys.age;
    mode = "0400";
    owner = "john";
    group = "staff";
  };

  # cleanup = "none" and no --cleanup/--zap: the Tailscale.app bundle and any
  # other manually installed app must survive activation.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
    };
    taps = ["peteonrails/voxtype"];
    casks = [
      "krita"
      "obs"
      "vlc"
      "dbeaver-community"
      "mongodb-compass"
      "maccy"
      "voxtype"
      "firefox"
      "discord"
      "prismlauncher"
    ];
    brews = [];
  };

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
      AppleShowAllExtensions = false;
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
      AppleShowAllExtensions = false;
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

  # Personal Mac maps Caps Lock to Control. Do not set remapCapsLockToEscape
  # (the work Mac's setting) — the two conflict.
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    nerd-fonts.roboto-mono
  ];

  system.activationScripts.postActivation.text = ''
    mkdir -p /Users/john/Screenshots
    chown john:staff /Users/john/Screenshots
  '';

  users.users.john = {
    name = "john";
    home = "/Users/john";
    uid = 501;
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = sshKeys;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {inherit inputs pkgs-stable compName;};
    users.john = import ./home-macbook.nix;
  };

  system.primaryUser = "john";
  system.stateVersion = 7;
}
