# GitHub runner VM — Proxmox VM (2 cores, 4 GB RAM, SeaBIOS, virtio)
#
# === INSTALL FROM LIVE CD ===
#   On bigp: qm create 101 --name github-nixos --machine q35 --cpu host \
#     --sockets 1 --cores 2 --memory 4096 --net0 virtio,firewall=1,bridge=vmbr0 \
#     --scsihw virtio-scsi-single --scsi0 local-lvm:25,iothread=1 \
#     --ide2 local:iso/nixos-minimal-26.05.5845.b3fe9581c906-x86_64-linux.iso,media=cdrom \
#     --serial0 socket --agent 1 --ostype l26 --boot order=ide2\;scsi0
#   On installer: clone https://github.com/John2143/dotfiles.git, then
#     sudo nix --experimental-features "nix-command flakes" \
#       run github:nix-community/disko -- --mode disko ./nixos/modules/disko_github.nix
#   Pre-seed the agenix identity so first-boot activation can decrypt secrets:
#     sudo mkdir -p /mnt/home/john/.ssh
#     sudo ssh-keygen -f /mnt/home/john/.ssh/age -N "" -C "john@github"
#   Re-encrypt secrets on office (secrets/secrets.nix + agenix -r), then:
#     sudo nixos-install --no-root-passwd --flake /tmp/dotfiles#github
#
# === GOTCHAS ===
#   - SeaBIOS + GRUB, like big — disko's EF02 partition provides grub.devices.
#     Do NOT set boot.loader.grub.device (duplicate-device assertion).
#   - Podman dockerCompat asserts it conflicts with virtualisation.docker.
#   - The podman socket group is hard-coded to "podman"; the runner user must be in it.
{
  config,
  lib,
  pkgs,
  sshKeys,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix") # Proxmox VM virtio drivers
    ./github-hardware-configuration.nix # fileSystems owned by disko (see modules/disko_github.nix)
    ./modules/user-john.nix
  ];

  boot.loader.grub.enable = true;
  # disko provides boot.loader.grub.devices from the EF02 partition — do NOT set
  # boot.loader.grub.device (big-configuration.nix gotcha: duplicate-device assertion).

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "sd_mod"
    "ext4"
  ];

  networking.hostName = "github";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  environment.systemPackages = with pkgs; [
    git
    fish
    curl
    htop
    k3s # provides kubectl via `k3s kubectl`
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;
  users.users."john".openssh.authorizedKeys.keys = sshKeys;
  # Proxmox guest agent — graceful shutdown from hypervisor
  services.qemuGuest.enable = true;

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

  # Tailscale for tailnet connectivity — no subnet route advertisement.
  services.tailscale.enable = true;

  # ============================================================
  # === k3s — standalone single-node CI cluster              ===
  # ============================================================

  age.secrets.k3s-ci-token = {
    file = ../secrets/k3s-ci-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.age.secrets.k3s-ci-token.path;
    extraFlags = toString [
      "--cluster-init" # standalone single-node cluster
      "--disable=traefik" # not used — Gateway API on home cluster
      "--disable=servicelb" # no external load balancer needed
      "--flannel-backend=host-gw" # direct routing, lower overhead
    ];
    gracefulNodeShutdown = {
      enable = true;
      shutdownGracePeriod = "20s";
      shutdownGracePeriodCriticalPods = "10s";
    };
  };

  # k3s needs avahi for mDNS — systemd ordering and clean resolv.conf.
  systemd.services.k3s = {
    after = ["avahi-daemon.service"];
    wants = ["avahi-daemon.service"];
    environment.K3S_RESOLV_CONF = "/etc/rancher/k3s/resolv.conf";
    serviceConfig = {
      TimeoutStopSec = lib.mkForce "30s";
    };
  };

  # Clean resolv.conf for k3s pods — strips the Tailscale MagicDNS search
  # domain (ts.2143.me) to prevent ndots:5 expansion from prepending it
  # to external hostnames. Keeps 100.100.100.100 as the upstream so pods
  # can still resolve tailnet names via MagicDNS.
  environment.etc."rancher/k3s/resolv.conf".text = ''
    nameserver 100.100.100.100
  '';

  # Prevent systemd-networkd from flushing custom ip rules created by
  # external tools (like our pod-CIDR routing fix below). Without this,
  # systemd-networkd removes rules it doesn't know about on restart.
  systemd.network.config.networkConf."ManageForeignRoutingPolicyRules" = "no";

  # Add an ip rule that directs pod CIDR traffic to the main routing table
  # BEFORE Tailscale's rule 5270 sends everything to table 52.
  #
  # Without this, Tailscale's `default dev tailscale0` in table 52 captures
  # pod-to-pod traffic between k3s nodes (because Tailscale's `throw` entries
  # only cover the local node's /24 on cni0, not remote pod CIDRs reached
  # via flannel.1). The result: cross-node pod networking silently fails.
  #
  # Priority 2500 is safely below Tailscale's range (5200-5500), so this rule
  # fires before Tailscale's table 52 lookup at rule 5270.
  # The `to 10.42.0.0/16` narrows it to k3s pod traffic only — non-pod traffic
  # falls through to Tailscale's rules as normal.
  systemd.services.pod-cidr-route = {
    description = "Add ip rule for pod CIDR traffic before Tailscale";
    after = ["tailscaled.service" "network.target"];
    wants = ["tailscaled.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iproute2}/bin/ip rule add priority 2500 from all to 10.42.0.0/16 lookup main 2>/dev/null || true
    '';
  };

  # Firewall — k3s ports
  networking.firewall.allowedTCPPorts = [
    6443 # k3s API server
    10250 # kubelet
    2379 # etcd client
    2380 # etcd peer
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # k3s flannel
  ];
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 30000;
      to = 32767;
    } # NodePort range
  ];

  # ── GitHub Actions org runner (2143-Labs) ─────────────────────────
  age.secrets.github-token = {
    file = ../secrets/github-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # Podman with docker-compat — container builds in CI jobs.
  # dockerCompat asserts it conflicts with virtualisation.docker; do NOT enable both.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true; # /run/docker.sock → podman socket (socket group is "podman")
    autoPrune.enable = true; # weekly; keeps the 25G disk from filling with CI images
  };

  # podman 5 reads `unqualified-search-registries`; the nixpkgs module only emits legacy
  # [[registry]] aliases, so `docker build` of short names (e.g. FROM rust:1.97-alpine)
  # fails with "no unqualified-search registries are defined". Override the generated file.
  environment.etc."containers/registries.conf" = lib.mkForce {
    text = ''
      unqualified-search-registries = ["docker.io"]
      [[registry]]
      location = "docker.io"
      [[registry]]
      location = "quay.io"
    '';
  };

  users.groups.github-runner = {};
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    extraGroups = ["podman"]; # the podman module hard-codes SocketGroup = "podman"; no docker group exists
    # Rootless podman (docker build/pull runs client-side as this user) needs uid/gid
    # mapping ranges to unpack image layers — without them: "insufficient UIDs or GIDs
    # available in user namespace ... Check /etc/subuid and /etc/subgid"
    subUidRanges = [{startUid = 1000000; count = 65536;}];
    subGidRanges = [{startGid = 1000000; count = 65536;}];
  };

  # Runner workspace on disk, not the /run tmpfs default (RAM pressure on a 4G box).
  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner-work 0755 github-runner github-runner -"
  ];

  services.github-runners."2143-labs" = {
    enable = true;
    url = "https://github.com/2143-Labs"; # org URL — a repo URL breaks org-wide tokens with 404
    tokenFile = config.age.secrets.github-token.path;
    name = "github"; # org-unique runner name; service unit: github-runner-2143-labs
    replace = true; # re-registration succeeds if a stale "github" runner lingers
    extraLabels = ["nixos"];
    user = "github-runner";
    group = "github-runner";
    workDir = "/var/lib/github-runner-work";
    extraPackages = [
      pkgs.podman
      # GitHub-hosted parity: plain `run:` steps call these bare. bash/coreutils/git/
      # tar/gzip are already on the module's default PATH — do not duplicate them.
      pkgs.curl
      pkgs.wget
      pkgs.jq
      pkgs.unzip
      pkgs.xz
      pkgs.gnused
      pkgs.gawk
      pkgs.kubectl
      # the module's dockerCompat wrapper is an internal runCommand; reproduce it on the
      # service PATH so workflows can call `docker`
      (pkgs.writeShellScriptBin "docker" "exec ${pkgs.podman}/bin/podman \"$@\"")
    ];
    serviceOverrides = {
      # module defaults (ProtectSystem=strict, PrivateUsers, syscall filter) break podman/docker
      ProtectSystem = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      RestrictAddressFamilies = lib.mkForce ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" "AF_PACKET"];
      RestrictNamespaces = lib.mkForce false;
      SystemCallFilter = lib.mkForce [];
    };
  };

  system.stateVersion = "25.11";
}
