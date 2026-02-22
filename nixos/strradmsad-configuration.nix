# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  ...
}:

{
  imports = [
    ./strradmsad-hardware-configuration.nix
    ./modules/user-john.nix
    #./modules/ollama.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home-cli.nix;

  # Use the systemd-boot EFI boot loader.;
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };


  networking.hostName = "strradmsad"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  #networking.interfaces = {
    #enp6s0.ipv4.addresses = [
      #{
        #address = "192.168.1.35";
        #prefixLength = 24;
      #}
    #];
  #};

  #networking.defaultGateway = "192.168.1.1";
  #networking.nameservers = [
    #"192.168.1.12"
    #"1.1.1.1"
  #];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    fish
    curl
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # ================
  # === Services ===
  # ================

  # Enable the OpenSSH daemon.
  users.users."john".openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgDycvDPQ3SkY3I1sec2ysE3shh5PNvKjjb5fihV7SOcgkeSxAQhZoQotVJ97AsztC4u93rGWvA/QImry+dREfPUWa9bZI5MhOX2vI4s6oQxWjmLl6e38UkfdkLVm93EiYcfQBuaaUA1Qzx4ZahSGdL7QFxeydzQKDIVh2JqvB1XbgqnHs3/N/cnR5WvbGt5kangWSitfAfB8A7L8Zb3G0RSeXR+b71sCeVKCXFIaj+w+ca+e3EmwM9Mrw/eewagOLFndYovAwEfdIwR975U0b5/o7cXoxJLovPzad09Zk6lz6JmGHsq4jliiC3jv0j3MGR8FZKymcAzOUa+7/eWA4EcdmM+1E9s0OF88s37ODzFTVPQqEtwNkQ57piWtyPAjoD8abgJaLO6y6lh2FS25hktSC4nVsZqWACrcTcKBng/4VIi09F1PPodJruBe1wMJvrVvpDc+If7da3XDzFUItxFQroyydEZGIlt1r8dAEuQU533epkPP09RkexY9neerpXMaQhzo1t9isUHLAMbM64eFkBxsKbGSKWv+zJh0ou/hLFtxEWZC5BDEWHcxilRg8gkV8sY/Ns7bYp3NzRlGKk6NQZrt+hH6rJzIeP0wH72QXOA00JIXJKROWK5V4snq8G2GEDOY9Zve6riY/XCgxYphBhtZFYoFHG0V8Hnwouw== jschmidt@DCIL-L562P1Q5NQ"
  ];
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

  #services.k3s = {
    #enable = true;
    #role = "server";
  #};

  #services.postgresql = {
    #enable = true;
    #ensureDatabases = [ "openfrontpro" ];
    #package = pkgs.postgresql_17;
    #enableTCPIP = true;
    #settings = {
      #ssl = true;
    #};
    #authentication = pkgs.lib.mkOverride 10 ''
      ##type databse DBuser auth-method
      #local all all trust

      ## local trust
      ##host all all 127.0.0.1/32 trust
      ##host all all 192.168.1.1/24 trust

      ## password login
      #host all all 0.0.0.0/0 scram-sha-256
    #'';
  #};

  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  networking.firewall.enable = false;

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?
}
