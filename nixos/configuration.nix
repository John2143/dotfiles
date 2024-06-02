# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # <home-manager/nixos>
    ];

  # === BEGIN NONFREE ===
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "electron-25.9.0"
    ];
  };
  # === END NONFREE ===

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      useOSProber = true;
      extraEntries = ''
      '';
      enable = true;
      device = "nodev";
    };
  };

  networking.hostName = "office"; # Define your hostname.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    wlp0s20f3.ipv4.addresses = [{
      address = "192.168.1.4";
      prefixLength = 24;
    }];
  };
  networking.wireless.environmentFile = "/run/secrets/wireless.env";
  networking.wireless.networks = {
    jimmys_2G.psk = "@PSK_HOME@";
  }; 
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.1" ];

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    # useXkbConfig = true; # use xkb.options in tty.
  };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
    initialPassword = "john";
    shell = pkgs.fish;
    packages = with pkgs; [
      firefox # browser
      jetbrains-mono # font
  
      udiskie # disks
      neovim
  
      # cli
      fish # shell
      git 
      starship #prompt
      bat # cat replacement
      eza # ls replacement
      ripgrep # grep replacement
      btop # btop++ > bpytop > htop > top
      choose # awk replacement
      wl-clipboard # copy-paste via cli
      du-dust # df/du replacement
  
      # graphical
      waybar # status bar
      wofi # "start menu" / program browser
      dolphin # file browser
      alacritty # terminal
  
      nerdfonts # fonts, idk how many this is
  
      fnm # node version manager # TODO switch to nixos
      clang # compiler
      rustup # rust compiler
  
      # === BEGIN NONFREE ===
  
      obsidian # note-taking software
      teamspeak_client
  
  
      # === END NONFREE ===
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    curl
    tmux
    hyprland
    # home-manager
    os-prober
    vim

    pavucontrol # audio
    qpwgraph

    mullvad-vpn
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.hyprland = {
    enable = true;
  };

  programs.fish.enable = true;

  programs.steam.enable = true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
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

  services.mullvad-vpn = {
    enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
#     wireplumber.extraConfig = {
#       "monitor.bluez.properties" = {
#         "bluez5.enable-sbc-xq" = true;
#         "bluez5.enable-msbc" = true;
#         "bluez5.enable-hw-volume" = true;
#         "bluez5.roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
#       };
#     };
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };

  systemd.user.services.office-bad-cpu = {
    description = "CPU perf core 8 is bad on my office comp";
    script = ''
      echo 0 > /sys/devices/system/cpu/cpu8/online
    '';
    wantedBy = [ "multi-user.target" ];
  };

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

