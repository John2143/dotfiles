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
}: let
  # Store path of the CrowdSec bouncer plugin source, defined once in
  # modules/k3s-server.nix (imported by every Traefik node, so the directory
  # exists on all three). Used directly as the hostPath: the mount source is a
  # real /nix/store directory, with no /etc symlink to resolve, and the store
  # is read-only, which is all localPlugins needs. The rev is part of the path,
  # so bumping the plugin changes this manifest and Helm rolls Traefik —
  # required, because Traefik reads plugin source only at startup.
  # unsafeDiscardStringContext: builtins.toFile rejects derivation references.
  traefikPluginSource = builtins.unsafeDiscardStringContext (toString
    config.environment.etc."traefik-plugins/crowdsec-bouncer-traefik-plugin".source);
in {
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
  # zramSwap disabled (was: enable = true; memoryPercent = 75). The compressed
  # swap interacted badly with the 8 GiB box under pressure (kernel panics in
  # BPF LRU / memory paths — see pstore dmesg captures); the 8 GiB /swapfile
  # above remains the only swap device.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Reboot 10s after a kernel panic instead of hanging; panic console text is
  # captured to efi pstore and survives the reboot in /var/lib/systemd/pstore.
  boot.kernel.sysctl."kernel.panic" = 10;
  boot.kernelParams = [ "panic=10" ];

  # (cam04 restream moved to Frigate's ffmpeg with NVR sub-stream — no separate service needed)

  networking.hostName = compName; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  # No hardware-specific network config in NixOS — NM profiles are managed via nmcli.
  # DHCPv4 (.36) and DHCPv6 (fd00:1::36, static router binding) come from the MikroTik.
  # Profile "enp8s0f1" must keep ipv6.method=auto: the RA supplies the fd00:1::/64 on-link and default routes; with method=dhcp closet cannot reach any other node over IPv6 (2026-10-16).

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

  # Node identity and cluster networking come from modules/k3s-net.nix.
  custom.k3sNet = {
    # Primary via 10G NIC (enp8s0f1); fd00:1::36 is the router's DHCPv6 binding.
    ipv4 = "192.168.5.36";
    ipv6 = "fd00:1::36";
    # Reserve RAM for OS + k3s server (etcd/Longhorn/iscsid are host
    # processes, not pods). 7.7 GiB total - 4 GiB reserved ≈ 3.4 GiB for
    # kube pods (HA must run here — USB hardware affinity; user priority).
    # Host procs measure ~4.7 GiB — 4096Mi matches measured usage so the
    # kubelet evicts pods before the host OOMs (2700Mi overcommitted and
    # the OOM hang returned; 5120Mi would leave only ~2.4 GiB for pods on
    # a control-plane hosting argocd/cert-manager/keda).
    systemReserved = "cpu=1,memory=4096Mi";
    # Backup via the old 1GbE NIC (enp6s0), still a valid API endpoint.
    extraTlsSans = ["192.168.5.35"];
  };
  services.k3s = {
    enable = true;
    role = "server";
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
      # Fail closed: if the plugin cannot load, Traefik exits (CrashLoopBackOff)
      # instead of serving with every bouncer-gated router dropped (2026-10-16).
      abortOnPluginFailure: true
      # Source comes from disk (dotfiles nixos/modules/k3s-server.nix), not
      # plugins.traefik.io, so a Traefik start needs no DNS and no network.
      localPlugins:
        bouncer:
          type: localPath
          moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
          mountPath: /plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
          volumeName: crowdsec-bouncer-plugin
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
        - name: crowdsec-bouncer-plugin
          hostPath:
            path: ${traefikPluginSource}
            type: Directory
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
    # The VIP pair comes from MetalLB pool `ingress` (argo
    # workloads/metallb/ipaddresspool.yaml). Never pin metallb.io/loadBalancerIPs
    # here: a pin naming one family of this PreferDualStack Service makes MetalLB
    # refuse allocation ("does not match the ipFamily"; outages 2026-10-15 and
    # 10-16). The pool holds exactly one address per family: .6.6 + fd00:6::6.
    service:
      annotations:
        metallb.io/address-pool: ingress
      spec:
        externalTrafficPolicy: Local
'';
    # Split-horizon DNS for pods: public hostnames resolve to the internal
    # traefik LB (192.168.6.6) instead of the public IP, so pod traffic never
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
    192.168.6.6 2143.me argocd.ts.2143.me au.2143.me cameras.ts.2143.me cams.ts.2143.me chat.2143.me files-ui.ts.2143.me home.ts.2143.me images.2143.me immich.ts.2143.me llm.2143.me longhorn.ts.2143.me m.2143.me matrix.2143.me net.2143.me pihole.ts.2143.me prod.rots.2143.me rots.2143.me status.2143.me temporal.ts.2143.me unifi.ts.2143.me anni.2143.me listen.2143.me mail.ts.2143.me mm.timestone.2143.me openbao.ts.2143.me stalwart.ts.2143.me tasks.2143.me
    192.168.6.6 john2143.com argo-webhook.john2143.com auth.john2143.com cameras.john2143.com containerstore.john2143.com element.john2143.com files.john2143.com grafana.john2143.com livekit.john2143.com mattermost.john2143.com net.john2143.com pvp.john2143.com seafile.john2143.com temporal.john2143.com applicationset-webhook.john2143.com factorio.john2143.com mm.timestone.john2143.com openbao.john2143.com pelican.john2143.com terminals.john2143.com i.john2143.com
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
  # 192.168.5.0/24 (MetalLB API VIP .10) and 192.168.6.0/24 (traefik LB .6.6).
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

      # password login: the WireGuard tunnel (10.99.0.0/24), the LAN, and loopback
      # only. The public WAN forward for 5432 is gone from the router, so nothing
      # routes here from the internet any more.
      # Deliberately absent: the cluster pod CIDR 10.42.0.0/16. Nothing in the
      # cluster connects to this database (the DO side comes in over the tunnel and
      # is masqueraded to 10.99.0.2; home pods are masqueraded to their node IPs,
      # which the LAN line already covers). Add it back if a pod ever connects
      # directly.
      host all all 10.99.0.0/24 scram-sha-256
      host all all 192.168.5.0/24 scram-sha-256
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
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
