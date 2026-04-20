# NAS configuration — headless NixOS file server.
#
# Services: ZFS (auto-scrub, sanoid snapshots), Samba (cross-platform),
#           Immich (native NixOS), Avahi/mDNS, Tailscale, SSH.
#
# === ZFS POOL SETUP (one-time, after first boot) ===
#
# 1. Identify drives by serial:
#      ls -l /dev/disk/by-id/ | grep -v part
#
# 2. Create tank pool (RAIDZ1 on 4x 8TB HDDs):
#      sudo zpool create -o ashift=12 \
#        -O atime=off -O compression=lz4 -O xattr=sa -O acltype=posixacl \
#        -O mountpoint=none \
#        tank raidz1 \
#          /dev/disk/by-id/ata-ST8000..._1 \
#          /dev/disk/by-id/ata-ST8000..._2 \
#          /dev/disk/by-id/ata-ST8000..._3 \
#          /dev/disk/by-id/ata-ST8000..._4
#
# 3. Add mirrored special vdev (500GB SSD + partition on boot SSD):
#      sudo zpool add tank special mirror \
#        /dev/disk/by-id/ata-<500GB-SSD> \
#        /dev/disk/by-id/ata-WDC_...-part4
#      sudo zfs set special_small_blocks=32K tank
#
# 4. Create datasets:
#      sudo zfs create -o mountpoint=/tank/share    tank/share
#      sudo zfs create -o mountpoint=/tank/media    tank/media
#      sudo zfs create -o mountpoint=/tank/backups  tank/backups
#      sudo zfs create -o mountpoint=/tank/immich   tank/immich
#      sudo zfs create -o mountpoint=/tank/scratch  tank/scratch
#
# 5. Set ownership:
#      sudo chown john:john /tank/share /tank/media /tank/scratch
#      sudo chown immich:immich /tank/immich
#
# 6. Set Samba password:
#      sudo smbpasswd -a john
#
# 7. Rebuild:
#      sudo nixos-rebuild switch --flake /home/john/dotfiles#nas
#

{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  sshKeys,
  ...
}:

{
  imports = [
    ./nas-hardware-configuration.nix
    ./modules/user-john.nix
  ];
  home-manager.users."john" = import ./home-cli.nix;
  services.getty.autologinUser = "john";

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # ================
  # === Network  ===
  # ================

  networking.hostName = compName;
  networking.networkmanager.enable = true;
  # ZFS requires a stable hostId — generate with: head -c 8 /etc/machine-id
  networking.hostId = "115e93a1";

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
    smartmontools # smartctl — inspect SMART on SATA/SCSI disks
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.fish.enable = true;

  # ================
  # === ZFS      ===
  # ================

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };
  services.zfs.trim.enable = true;

  services.sanoid = {
    enable = true;
    datasets = {
      "tank/share" = {
        autosnap = true;
        hourly = 24;
        daily = 30;
        monthly = 6;
      };
      "tank/media" = {
        autosnap = true;
        daily = 7;
        monthly = 3;
      };
      "tank/immich" = {
        autosnap = true;
        hourly = 24;
        daily = 30;
        monthly = 6;
      };
      "tank/backups" = {
        autosnap = true;
        daily = 7;
        monthly = 3;
      };
    };
  };

  # ================
  # === Samba    ===
  # ================

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "server string" = "nas";
        "netbios name" = "nas";
        "workgroup" = "WORKGROUP";
        "server role" = "standalone server";
        # Include Tailscale CGNAT so phones / laptops on the tailnet can reach SMB.
        "hosts allow" = "192.168. 10.10. 100.64.0.0/10 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        # macOS compatibility (Finder metadata, resource forks)
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        "server min protocol" = "SMB2";
        "server max protocol" = "SMB3";
        "ea support" = "yes";
        # iOS Files is picky; avoid SMB3 transport encryption fighting with VPN/Tailscale.
        # Tailscale already encrypts the tunnel; signing still protects auth on LAN.
        "server signing" = "auto";
        "server smb encrypt" = "off";
        "map to guest" = "Bad User";
      };
      share = {
        path = "/tank/share";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0666";
        "directory mask" = "0777";
        "force user" = "john";
        "force group" = "john";
      };
      media = {
        path = "/tank/media";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "john";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      scratch = {
        path = "/tank/scratch";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "john";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # ================
  # === Immich   ===
  # ================

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;
    mediaLocation = "/tank/immich";
    machine-learning.enable = true;
    database.enable = true;
    redis.enable = true;
  };

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;
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

  networking.firewall = {
    #enable = true;
    allowedTCPPorts = [
      2283  # immich
    ];
  };

  system.stateVersion = "26.05";
}
