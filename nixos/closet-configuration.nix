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
    ./modules/nut-ups.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home-cli.nix;

  # Use the systemd-boot EFI boot loader.;
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelModules = [
    "target_core_mod"
    "iscsi_target_mod"
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];
  zramSwap.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # (cam04 restream moved to Frigate's ffmpeg with NVR sub-stream — no separate service needed)

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
      # Join existing cluster via VIP (MetalLB-announced .10)
      "--server=https://192.168.5.10:6443"
      "--disable=servicelb"
      "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
      "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
      # Dual-stack nodes must use explicit IPv4+IPv6 addresses
      "--node-ip=192.168.5.36,fd00:1::36"
      # Required for IPv6 pod egress when using flannel
      "--flannel-ipv6-masq"
      # Fast crash recovery — detect downed nodes in 20s, evict pods in 40s
      "--kube-apiserver-arg=default-not-ready-toleration-seconds=40"
      "--kube-apiserver-arg=default-unreachable-toleration-seconds=40"
      "--kube-controller-manager-arg=node-monitor-grace-period=20s"
      "--kube-controller-manager-arg=node-monitor-period=2s"
      # Keep standard per-node subnet sizing across families
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
      "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
      # Reserve RAM for OS + k3s server (etcd/Longhorn/iscsid are host
      # processes, not pods). 7.7 GiB total - 2.7 GiB reserved = ~5 GiB for
      # kube pods (HA must run here — USB hardware affinity; user priority).
      # WARNING: host procs measured ~4.7 GiB, so this overcommits and the
      # OOM hang may return until the 32 GB upgrade lands.
      "--kubelet-arg=system-reserved=cpu=1,memory=2700Mi"
    ];
    # Raw manifest via `source` (not `content`): pkgs.formats.yaml in current
    # nixpkgs emits a `%YAML 1.1` directive that the k3s helm-controller's
    # yaml parser rejects ("line 1: did not find expected <document start>").
    # `source` symlinks the file verbatim, bypassing the format generator.
    manifests.traefik-config.source = builtins.toFile "traefik-config.yaml" ''
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |
    logs:
      access:
        enabled: true
        format: json
    experimental:
      plugins:
        bouncer:
          moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
          version: v1.7.1
    additionalVolumeMounts:
      - name: crowdsec-bouncer-key
        mountPath: /etc/traefik/secrets
        readOnly: true
    deployment:
      replicas: 3
      additionalVolumes:
        - name: crowdsec-bouncer-key
          secret:
            secretName: crowdsec-bouncer-key
    nodeSelector:
      node-role.kubernetes.io/control-plane: "true"
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: traefik
              topologyKey: kubernetes.io/hostname
    providers:
      kubernetesGateway:
        enabled: true
        experimentalChannel: true
    tracing:
      otlp:
        enabled: true
        grpc:
          enabled: true
          endpoint: "alloy.observability.svc:4317"
          insecure: true
      serviceName: traefik
      sampleRate: 1.0
    service:
      annotations:
        metallb.io/loadBalancerIPs: "192.168.6.11"
      spec:
        externalTrafficPolicy: Local
'';
    # Split-horizon DNS for pods: public hostnames resolve to the internal
    # traefik LB (192.168.6.11) instead of the public IP, so pod traffic never
    # hairpins through the router (see argo/docs/2026-08-10-auto-instrumentation.md).
    # k3s's coredns chart mounts a `coredns-custom` ConfigMap at
    # /etc/coredns/custom (volume custom-config-volume, optional) and the
    # Corefile imports `*.server` at top level + `*.override` in the `.:53`
    # block. The hosts plugin matches literal names — every public hostname is
    # enumerated (not a wildcard). `.server` (not `.override`): a hosts-format
    # blob inside `.:53` would be invalid Corefile and take down cluster DNS.
    manifests.coredns-custom.source = builtins.toFile "coredns-custom.yaml" ''
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  hosts.split-horizon: |
    192.168.6.11 2143.me argocd.ts.2143.me au.2143.me cameras.ts.2143.me cams.ts.2143.me chat.2143.me files-ui.ts.2143.me home.ts.2143.me images.2143.me immich.ts.2143.me llm.2143.me longhorn.ts.2143.me m.2143.me matrix.2143.me net.2143.me pihole.ts.2143.me prod.rots.2143.me rots.2143.me status.2143.me temporal.ts.2143.me unifi.ts.2143.me
    192.168.6.11 john2143.com argo-webhook.john2143.com auth.john2143.com cameras.john2143.com containerstore.john2143.com element.john2143.com files.john2143.com grafana.john2143.com livekit.john2143.com mattermost.john2143.com net.john2143.com pvp.john2143.com seafile.john2143.com temporal.john2143.com
    192.168.6.13 imap.m.2143.me smtp.m.2143.me
    192.168.6.20 temporal-grpc.john2143.com
  split-horizon.server: |
    2143.me:53 john2143.com:53 {
        hosts /etc/coredns/custom/hosts.split-horizon {
            ttl 60
            reload 15s
            fallthrough
        }
        forward . /etc/resolv.conf
    }
'';
  };
  # Tailscale subnet route — advertises LAN + service subnets to the tailnet:
  # 192.168.5.0/24 (MetalLB API VIP .10) and 192.168.6.0/24 (traefik LB .6.11).
  # Approved in headscale per-node.
  services.tailscale.extraUpFlags = [ "--advertise-routes=192.168.6.0/24,192.168.5.0/24" ];
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
    179 # BGP (MetalLB speaker)
  ];
  networking.firewall.allowedUDPPorts = [
    5540 # matter-server (hostNetwork pod)
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # Kubernetes NodePort range
  ];

  # ── NUT UPS monitoring ────────────────────────────────────────────
  # power.ups handles usbhid-ups auto-detect, webhooks, and k3s drain.
  # See modules/nut-ups.nix for the shared config.
  custom.nut-ups = {
    enable = true;
    haWebhooks = true;
    k3sDrain = true;
    poweroffArgs = "-f";
  };
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?
}
