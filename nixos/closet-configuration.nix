# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  sshKeys,
  compName,
  ...
}:

{
  imports = [
    ./closet-hardware-configuration.nix
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

  #virtualisation.oci-containers = {
    #backend = "podman";
    #containers.teamspeak = {
      #image = "docker.io/teamspeak:latest";
      #ports = [
        #"9987:9987/udp"
        #"30033:30033"
      #];
      #environment = {
        #TS3SERVER_LICENSE = "accept";
      #};
      #volumes = [
        #"/home/john/teamspeak/teamspeak3-server_linux_amd64_old:/var/ts3server"
      #];
    #};
  #};

  networking.hostName = compName; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

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
  users.users."john".openssh.authorizedKeys.keys = sshKeys;
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

  security.rtkit.enable = true;
  services.printing.enable = true;

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = lib.concatStringsSep " " [
      # Dual-stack pod and service networks (IPv4 + IPv6)
      "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
      "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
      # Dual-stack nodes must use explicit IPv4+IPv6 addresses
      "--node-ip=192.168.5.35,2600:4040:2602:f801:c037:db04:d14a:5052"
      # Required for IPv6 pod egress when using flannel
      "--flannel-ipv6-masq"
      # Keep standard per-node subnet sizing across families
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
    ];
    manifests.traefik-config.content = {
      apiVersion = "helm.cattle.io/v1";
      kind = "HelmChartConfig";
      metadata = {
        name = "traefik";
        namespace = "kube-system";
      };
      spec.valuesContent = ''
        providers:
          kubernetesGateway:
            enabled: true
            experimentalChannel: true
      '';
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "openfrontpro" ];
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    settings = {
      ssl = true;
    };
    authentication = pkgs.lib.mkOverride 10 ''
      #type databse DBuser auth-method
      local all all trust

      # local trust
      #host all all 127.0.0.1/32 trust
      #host all all 192.168.1.1/24 trust

      # password login
      host all all 0.0.0.0/0 scram-sha-256
    '';
  };

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
  system.stateVersion = "24.11"; # Did you read the comment?
}
