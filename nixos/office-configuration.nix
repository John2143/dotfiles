# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./office-hardware-configuration.nix
      # inputs.home-manager.nixosModules.default
    ];

  services.getty.autologinUser = "john";

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
      address = "192.168.1.36";
      prefixLength = 24;
    }];
  };
  networking.wireless.environmentFile = "/run/secrets/wireless.env";
  networking.wireless.networks = {
    jimmys_2G.psk = "@PSK_HOME@";
  }; 
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.35" "192.168.1.3"  ];

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
  sound.enable = true;
  # hardware.pulseaudio.enable = true;

  systemd.user.services.office-bad-cpu = {
    wantedBy = [ "multi-user.target" ];
    description = "CPU perf core 8 is bad on my office comp";

    serviceConfig = {
      ExecStart = ''
        #!/run/current-system/sw/bin/bash
        echo 0 | tee /sys/devices/system/cpu/cpu8/online
        echo 0 | tee /sys/devices/system/cpu/cpu9/online
        date > /home/john/test.txt
        echo "yeehaw"
      '';
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
    token = "K10c19a7646d1e7136cc58d26d01b44ca809b0c2efed76bed7b1612f7c01e41f616::xv480x.847d9pubg1qnqif5";
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
