# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, pkgs-stable, ... }:

{
  _module.args.john-home-path = ./home.nix;
  imports =
    [
      ./office-hardware-configuration.nix
      ./modules/user-john.nix
      ./modules/ollama.nix
      #./waybar.nix
      # inputs.home-manager.nixosModules.default
    ];

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

  systemd.services.office-bad-cpu = {
    wantedBy = [ "multi-user.target" ];
    description = "CPU perf core 8 is bad on my office comp";
    script = ''${pkgs.fish}/bin/fish /home/john/bin/office.fish'';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."bad-cpu" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5";
      OnUnitActiveSec = "5";
      Unit = "office-bad-cpu.service";
    };
  };

  systemd.services.rebuild-nixos = {
    wantedBy = [ "multi-user.target" ];
    description = "Update NixOS configuration";
    script = ''${pkgs.fish}/bin/fish -c "update || true"'';
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Environment = "HOME=/home/john";
    };
  };

  systemd.timers."rebuild-nixos" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "rebuild-nixos.service";
      # Every 15 mins
      OnCalendar = "*:0/15";
      #Persistent = true;
    };
  };

  systemd.services.rebuild-nixos-boot = {
    wantedBy = [ "multi-user.target" ];
    description = "Update NixOS configuration fr";
    script = ''${pkgs.fish}/bin/fish -c "cd dotfiles; build boot && git add flake.lock && git commit -m 'Update auto: '(date +%Y-%m-%dT%H:%M:%S) && git push"'';
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Environment = "HOME=/home/john";
    };
  };

  systemd.timers."rebuild-nixos-boot" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "rebuild-nixos-boot.service";
      # Every 15 mins at 5 minutes after update
      OnCalendar = "*:5/15";
      #Persistent = true;
    };
  };

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
  networking.firewall.allowPing = true;

  # Allow windows to see the samba share
  #services.samba-wsdd = {
    #enable = true;
    #openFirewall = true;
  #};

  #services.samba = {
    #enable = true;
    #securityType = "user";
    #openFirewall = true;
    #settings = {
      #global = {
        #"workgroup" = "WORKGROUP";
        #"server string" = "smbnix";
        #"netbios name" = "smbnix";
        #"security" = "user";
        ##"use sendfile" = "yes";
        ##"max protocol" = "smb2";
        ## note: localhost is the ipv6 localhost ::1
        #"hosts allow" = "192.168.1. 127.0.0.1 localhost";
        #"hosts deny" = "0.0.0.0/0";
        #"guest account" = "john";
        #"map to guest" = "bad user";
      #};
      #"john_camera_readonly" = {
        #"path" = "/mnt/share/camera/";
        #"browseable" = "yes";
        #"read only" = "yes";
        #"guest ok" = "yes";
        #"create mask" = "0644";
        #"directory mask" = "0755";
        #"force user" = "john";
        #"force group" = "john";
      #};
    #};
  #};

  #programs.ssh.extraConfig = ''
    #Host eu.nixbuild.net
      #PubkeyAcceptedKeyTypes ssh-ed25519
      #ServerAliveInterval 60
      #IPQoS throughput
      #IdentityFile /home/john/.ssh/id_ed25519
  #'';

  #programs.ssh.knownHosts = {
    #nixbuild = {
      #hostNames = [ "eu.nixbuild.net" ];
      #publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    #};
  #};

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?
}
