{
  config,
  inputs,
  pkgs,
  lib,
  pkgs-stable,
  compName,
  ...
}:

let
  primaryPackages = with pkgs; [
    udiskie # disks
    # neovim

    # fonts
    # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/fonts/nerdfonts/shas.nix
    nerd-fonts.jetbrains-mono # font
    nerd-fonts.roboto-mono # font also, "FiraCode" "DejaVuSansMono" "FiraMono"

    # cli
    amdgpu_top # gpu stats
    chatgpt-cli # yessir
    ffmpeg

    # screenshots
    slurp # use mouse to get a point on screen
    grim # minimal screenshot program
    bind # network utilities
    pkgs-stable.wf-recorder # screen recording
    pkgs-stable.normcap # OCR screen recognition
    hyprpicker # color picker

    #@ embedded programming
    #@ gcc-arm-embedded # arm compiler
    #@ openocd # open debugger
    #@ probe-rs # rust <-> stm32
    #@ stlink # stm32 programmer
    #@ stm32cubemx # stm32 ide
    prusa-slicer # 3d printer slicer

    # desktop tools (bars, clipbaords, notifications, etc)
    pulseaudio # pactl (audio)
    wofi # "start menu" / program browser
    kdePackages.dolphin # file browser
    xfce.thunar # file browser 2
    wl-clipboard # copy-paste via cli
    jetbrains-mono # font
    alacritty # terminal
    pwvucontrol # volume control
    pamixer # volume control
    cliphist # clipboard history
    wl-clipboard-x11 # clipboard compatibility for some apps
    dunst # desktop alert notificaitons
    libnotify # notifications cli
    gammastep # redshift / f.lux / night light
    spotifyd # play to spotify device if needed

    temurin-jre-bin-21 # java
    wine-wayland # wine

    hyprlock # screen locker

    # desktop programs (programs you can open)
    firefox # browser
    # floorp # browser
    #@ ungoogled-chromium # browser backup
    mullvad-vpn # vpn
    gthumb # image viewer
    #@ plex-media-player # plex
    spotify # music
    (prismlauncher.override {
      jdks = [
        temurin-bin-21
        temurin-bin-8
        temurin-bin-17
      ];
    })
    r2modman # game modding
    vesktop # discord
    discord
    discordo
    # discord-canary
    #@ krita
    #@ kdePackages.kdenlive # video editor
    # kdeconnect # phone sync (now in main settings)
    #v4l-utils # video inputs for linux (obs)
    #@ path-of-building # Path of Exile build planner
    bitwarden-desktop # password manager
    vlc # video player
    mpv # video player
    wev # wayland event viewer

    # Other / unsorted
    appimage-run
    #@ betaflight-configurator
    lshw
    #@ darktable
    nixd
    hyprpaper
    kind
    mongodb-compass
    doctl
    # kubernetes-helm

    k3s # kubernetes k8s node

    pavucontrol # audio
    qpwgraph

    plasma5Packages.kdeconnect-kde
    kdePackages.ark
    kdePackages.gwenview

    e1s
    dbeaver-bin # db browser
    warp-terminal # agent terminal
  ];

  # If we are on office computer, then also add the following:
  optionalPackages = with pkgs; [
    kicad # PCB Hardware Layout
    obs-studio # streaming
  ];

  # On my other computer, I want to install these
  optionalPackagesUpstairs = with pkgs; [
  ];
in
{
  # Include everything from home-cli.nix too
  imports = [
    ./home-cli.nix
    ./modules/waybar.nix
  ];

  # Check hostname to determine what to install
  home.packages =
    if compName == "office" then primaryPackages ++ optionalPackages else
    if compName == "arch" then primaryPackages ++ optionalPackagesUpstairs else
    primaryPackages;

  nixpkgs.overlays = [
    #(import ./overlays/r2modman-overlay.nix)
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    xwayland.enable = true;
    systemd.enable = true;
    extraConfig = builtins.readFile ../.config/hypr/hyprland.conf;
  };

  services.gammastep = {
    enable = true;
    # New york
    longitude = -74.0060;
    latitude = 40.7128;
    temperature = {
      day = 6500;
      night = 3500;
    };
  };

  xdg.configFile = {
    "alacritty".source = config.lib.file.mkOutOfStoreSymlink ../.config/alacritty;
    "dunst".source = config.lib.file.mkOutOfStoreSymlink ../.config/dunst;
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink ../.config/hypr/hyprlock.conf;
    "hypr/hyprpaper.conf".text =
      "
      preload = /home/john/backgrounds/luna_1.png
      wallpaper = , /home/john/backgrounds/luna_1.png
    ";
    # "waybar".source = config.lib.file.mkOutOfStoreSymlink ../.config/waybar;

    "get_sunset.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_sunset.fish;
    "get_mullvad.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_mullvad.fish;

    "focussed-vol-adjust.sh".source =
      builtins.fetchGit {
        url = "https://github.com/Orbsa/hyprland-pipewire-focused-volume-adjust";
        ref = "master";
        rev = "c268b0269617c5109585044ef6eac8623090891f";
      }
      + "/hpfva.sh";
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".vimrc".source = ../.vimrc;
    # ".tmux.conf".source = /home/john/dotfiles/.tmux.conf;
    # ".gitconfig".source = ../.gitconfig;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };
}
