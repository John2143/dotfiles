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
}: {
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

  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # ── cam04 restream proxy (rotate Reolink Duo 270°) ───────────────
  # Software HEVC decode → transpose → H264 encode → RTSP.
  # GTX 1080 Ti NVENC has 4096px width limit; go2rtc filter ordering
  # puts scale before rotate, breaking GPU rotation on arch.
  # See local://cam04-rotation-cuda-arch.md
  age.secrets.reolink-nvr = {
    file = ../secrets/reolink-nvr.age;
    owner = "root";
  };
  systemd.services.cam04-restream = {
    description = "cam04 restream proxy — rotate Reolink Duo 270°";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.ffmpeg pkgs.bash];
    script = ''
      set -a
      source ${config.age.secrets.reolink-nvr.path}
      set +a
      exec ffmpeg -hide_banner \
        -rtsp_transport tcp \
        -i "rtsp://$NVR_USER:$NVR_PASS@$NVR_HOST/h264Preview_04_main" \
        -vf transpose=2 \
        -c:v libx264 -preset ultrafast -crf 23 -tune zerolatency \
        -an \
        -f rtsp -listen 1 rtsp://0.0.0.0:8554/cam04
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
    };
  };
  # (old teamspeak container removed; cam04 restream runs via systemd above)

  networking.hostName = compName; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  # No hardware-specific network config in NixOS — NM profiles managed via nmcli
  # DHCPv4 (.36) and DHCPv6 (fd00:1::36) are assigned by MikroTik router

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
    kubectl
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  custom.backup = {
    enable = true;
    prepareCommand = ''
      mkdir -p /mnt/backup
      ${pkgs.util-linux}/bin/ionice -c3 ${pkgs.coreutils}/bin/nice -n19 \
        ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_17}/bin/pg_dumpall \
        | ${pkgs.gzip}/bin/gzip > /mnt/backup/postgres.sql.gz
    '';
    extraPaths = ["/mnt/backup/postgres.sql.gz"];
  };

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
      # mDNS hostnames for k3s TLS cert — needed for server-to-server join
      "--tls-san=closet.local"
      "--tls-san=arch.local"
      "--tls-san=nas.local"
      # Primary via 10G NIC (enp8s0f1)
      "--tls-san=192.168.5.36"
      # Backup via old 1GbE NIC (enp6s0)
      "--tls-san=192.168.5.35"
      "--tls-san=192.168.5.10"
      # Dual-stack pod and service networks (IPv4 + IPv6)
      # Join existing cluster via VIP (kube-vip LB on .10)
      "--server=https://192.168.5.10:6443"
      "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
      "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
      # Dual-stack nodes must use explicit IPv4+IPv6 addresses
      "--node-ip=192.168.5.36,fd00:1::36"
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
  # Tailscale subnet route — advertises LAN to tailnet so tailscale
  # clients can reach the kube-vip VIP (192.168.5.10) for k8s services.
  # Approved in headscale admin UI.
  services.tailscale.extraUpFlags = [ "--advertise-routes=192.168.5.0/24" ];
  # Keep Longhorn data mount active during k3s shutdown so iSCSI can
  # logout cleanly before the filesystem unmounts.
  custom.k3sStorageAfter = ["mnt-longhorn.mount"];

  services.postgresql = {
    enable = true;
    ensureDatabases = ["openfrontpro"];
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

  # Firewall enabled via shared-cli-configuration.nix.
  networking.firewall.allowedTCPPorts = [
    6443 # k3s API server
    10250 # kubelet
    2379 # etcd client (k3s join)
    2380 # etcd peer (k3s join)
    5432 # Postgres
    5580 # matter-server (hostNetwork pod)
    179 # BGP for kube-vip
    8554 # cam04 restream proxy (rotated RTSP)
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # Kubernetes NodePort range
  ];

  # ── APC UPS monitoring ────────────────────────────────────────────
  # Gracefully shuts down at low battery. Fires HA webhooks on power events.
  age.secrets.hass-webhooks = {
    file = ../secrets/hass-webhooks.age;
    owner = "root";
  };
  services.apcupsd = {
    enable = true;
    configText = ''
      UPSCABLE usb
      UPSTYPE usb
      DEVICE
      ONBATTERYDELAY 6
      BATTERYLEVEL 50
      MINUTES 5
    '';
    hooks = {
      onbattery = ''
        set -a; source /run/agenix/hass-webhooks; set +a
        ${pkgs.curl}/bin/curl -s -X POST "$CLOSET_ONBATTERY_URL"
        ${pkgs.util-linux}/bin/wall 'UPS on battery — shutting down when critical'
      '';
      offbattery = ''
        set -a; source /run/agenix/hass-webhooks; set +a
        ${pkgs.curl}/bin/curl -s -X POST "$CLOSET_OFFBATTERY_URL"
        ${pkgs.util-linux}/bin/wall 'UPS power restored'
      '';
      doshutdown = ''
        ${pkgs.util-linux}/bin/wall 'UPS battery critical — draining k3s node and shutting down NOW'
        # Drain this k3s node before poweroff — gives Longhorn time to
        # promote replicas and avoids the 5-minute iSCSI timeout delay.
        ${pkgs.k3s}/bin/k3s kubectl drain ${compName} --ignore-daemonsets --delete-emptydir-data --grace-period=90 --timeout=150s 2>/dev/null || true
        ${pkgs.systemd}/bin/systemctl poweroff -f
      '';
    };
  };
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?
}
