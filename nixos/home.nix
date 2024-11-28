{ config, inputs, pkgs, lib, pkgs-stable, ... }:
{
  # Include everything from home-cli.nix too
  imports = [
    ./home-cli.nix
    ./modules/waybar.nix
  ];

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
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
    normcap # OCR screen recognition
    hyprpicker # color picker

    # embedded programming
    # gcc-arm-embedded # arm compiler
    # openocd # open debugger
    # probe-rs # rust <-> stm32
    # stlink # stm32 programmer
    # stm32cubemx # stm32 ide
    kicad # PCB Hardware Layout

    # desktop tools (bars, clipbaords, notifications, etc)
    pulseaudio # pactl (audio)
    wofi # "start menu" / program browser
    dolphin # file browser
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
    mullvad-vpn # vpn
    gthumb # image viewer
    plex-media-player # plex
    spotify # music
    prismlauncher # minecraft
    vesktop # discord
    krita
    kdenlive # video editor
    # kdeconnect # phone sync (now in main settings)
    v4l-utils # video inputs for linux (obs)
    obs-studio # streaming
    path-of-building # Path of Exile build planner
    bitwarden-desktop # password manager
    vlc # video player
    mpv # video player
    wev # wayland event viewer

    # Other / unsorted
    appimage-run
    betaflight-configurator
    lshw
    darktable
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
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    xwayland.enable = true;
    systemd.enable = true;
    extraConfig = builtins.readFile ../.config/hypr/hyprland.conf;
  };

  xdg.configFile = {
    "alacritty".source = config.lib.file.mkOutOfStoreSymlink ../.config/alacritty;
    "dunst".source = config.lib.file.mkOutOfStoreSymlink ../.config/dunst;
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink ../.config/hypr/hyprlock.conf;
    "hypr/hyprpaper.conf".text = "
      preload = /home/john/backgrounds/luna_1.png
      wallpaper = , /home/john/backgrounds/luna_1.png
    ";
    # "waybar".source = config.lib.file.mkOutOfStoreSymlink ../.config/waybar;

    "get_sunset.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_sunset.fish;
    "get_mullvad.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_mullvad.fish;

    "focussed-vol-adjust.sh".source = builtins.fetchGit {
      url = "https://github.com/Orbsa/hyprland-pipewire-focused-volume-adjust";
      ref = "master";
      rev = "c268b0269617c5109585044ef6eac8623090891f";
    } + "/hpfva.sh";
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
