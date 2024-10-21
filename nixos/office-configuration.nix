# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports =
    [
      ./office-hardware-configuration.nix
      #./waybar.nix
      # inputs.home-manager.nixosModules.default
    ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "input" "dialout" "docker" ]; # Enable ‘sudo’ for the user.
    initialPassword = "john";
    shell = pkgs.fish;
    packages = with pkgs; [
      obsidian # note-taking software
      teamspeak_client
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  home-manager = {
    # home-manager uses extraSpecialArgs instead of specialArgs, but it does the same thing
    extraSpecialArgs = {
      pkgs-stable = pkgs-stable;
    };
    #sharedModles = [
      #inputs.sops-nix.homeManagerModles.sops
    #];
    users = {
      "john" = import ./home.nix;
    };
  };

  services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      extraEntries = ''
      '';
      enable = true;
      device = "nodev";
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  networking.hostName = "office"; # Define your hostname.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    wlp0s20f3.ipv4.addresses = [{
      address = "192.168.1.36";
      prefixLength = 24;
    }];
  };
  networking.wireless.secretsFile = "/run/secrets/wireless.env";
  networking.wireless.networks = {
    jimmys_2G.pskRaw = "ext:PSK_HOME";
  };
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.12" "1.1.1.1" ];

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

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  systemd.user.services.office-bad-cpu = {
    wantedBy = [ "multi-user.target" ];
    description = "CPU perf core 8 is bad on my office comp";

    serviceConfig = {
      ExecStart = ''${pkgs.fish}/bin/fish /home/john/bin/office.fish'';
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  services.udev.extraRules = builtins.readFile ./udev_embedded.rules;

  # services.udiskie.enable = true;

  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://192.168.1.35:6443";
    token = "K10c774bc9053c47bd55747f362531fb443f6ca1e4364143dbd74acdd4156eb6878::3vjhdv.f8s0bl2ablc7ctej";
  };

  services.ollama = {
    acceleration = "rocm";
    environmentVariables = {
      HCC_AMDGPU_TARGET = "gfx1100";
    };
    rocmOverrideGfx = "11.0.0";
  };

  # drones
  services.upower.enable = true;

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    #extraConfig = ''
      #workgroup = WORKGROUP
      #server string = smbnix
      #netbios name = smbnix
      #security = user
      ##use sendfile = yes
      ##max protocol = smb2
      ## note: localhost is the ipv6 localhost ::1
      ## hosts allow = 192.168.1. 127.0.0.1 localhost
      #hosts allow = 0.0.0.0/0
      ## hosts deny = 0.0.0.0/0
      #guest account = john
      #map to guest = bad user
    #'';
    shares = {
      public = {
        path = "/home/john/camera/";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      #private = {
        #path = "/mnt/Shares/Private";
        #browseable = "yes";
        #"read only" = "no";
        #"guest ok" = "no";
        #"create mask" = "0644";
        #"directory mask" = "0755";
        #"force user" = "username";
        #"force group" = "groupname";
      #};
    };
  };

  programs.ssh.extraConfig = ''
    Host eu.nixbuild.net
      PubkeyAcceptedKeyTypes ssh-ed25519
      ServerAliveInterval 60
      IPQoS throughput
      IdentityFile /home/john/.ssh/id_ed25519
  '';

  programs.ssh.knownHosts = {
    nixbuild = {
      hostNames = [ "eu.nixbuild.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      #{ hostName = "eu.nixbuild.net";
        #system = "x86_64-linux";
        #maxJobs = 100;
        #supportedFeatures = [ "benchmark" "big-parallel" ];
      #}
      { hostName = "eu.nixbuild.net";
        system = "aarch64-linux";
        maxJobs = 100;
        supportedFeatures = [ "benchmark" "big-parallel" ];
      }
      { hostName = "eu.nixbuild.net";
        system = "armv7l-linux";
        maxJobs = 100;
        supportedFeatures = [ "benchmark" "big-parallel" ];
      }
    ];
  };
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
