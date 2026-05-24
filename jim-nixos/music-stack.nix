# Music stack — Spotify replacement with Navidrome + Lidarr + slskd + explo + aurral.
#
# Services (all reachable on localhost):
#   Navidrome   → http://localhost:4533   (music streaming, Subsonic API)
#   Lidarr      → http://localhost:8686   (music collection manager)
#   slskd       → http://localhost:5030   (Soulseek P2P downloader)
#   explo       → http://localhost:7288   (auto-playlists: daily/weekly/monthly)
#   aurral      → http://localhost:5000   (music requests, like Overseerr)
#
# === BEFORE REBUILDING ===
#
# 1. Create a Soulseek account: download a client from https://www.slsknet.org
#    and register a username/password on first launch. You can uninstall after.
#
# 2. Create the slskd credentials file:
#      sudo mkdir -p /var/lib/slskd
#      echo 'SLSKD_SLSK_USERNAME=your-username' | sudo tee /var/lib/slskd/slskd.env
#      echo 'SLSKD_SLSK_PASSWORD=your-password' | sudo tee -a /var/lib/slskd/slskd.env
#      sudo chmod 600 /var/lib/slskd/slskd.env
#
# 3. Create accounts on MusicBrainz (https://musicbrainz.org) and
#    ListenBrainz (https://listenbrainz.org — sign in with MusicBrainz).
#
# === POST-INSTALL ===
#
# 4. Open Lidarr → Settings → Plugins → Tubifarry should be loaded.
#    Configure Soulseek, Lyrics Enhancer, and Search Sniper in Tubifarry settings.
#
# 5. Open Navidrome → Profile → enable "Scrobble to ListenBrainz".
#
# 6. Open aurral → follow setup wizard to connect Lidarr and Navidrome.
#    Click "Apply Davo's Recommended Settings".
#
# 7. Start adding artists in Lidarr or request them through aurral.
#    explo will generate playlists after you've listened for a bit.
#
# Music data layout:
#   /var/lib/music/
#   ├── downloads/    # lidarr incomplete downloads
#   ├── library/      # lidarr imports → navidrome scans this
#   └── explo/        # explo playlists (mounted as /data in container)
{
  lib,
  pkgs,
  ...
}: let
  musicRoot = "/var/lib/music";
in {
  # --- Podman (for explo + aurral containers) ---
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    # explo — auto-generates daily/weekly/monthly playlists from listening history
    explo = {
      image = "ghcr.io/lumepart/explo:latest";
      extraOptions = [
        "--network=host"
        "--pull=always"
      ];
      volumes = [
        "${musicRoot}/explo:/data"
      ];
    };

    # aurral — music request management (Overseerr for music)
    aurral = {
      image = "lklynet/aurral:latest";
      extraOptions = [
        "--network=host"
        "--pull=always"
      ];
      volumes = [
        "aurral-data:/data"
      ];
    };
  };

  # --- Navidrome — music streaming server ---
  services.navidrome = {
    enable = true;
    settings = {
      MusicFolder = "${musicRoot}/library";
      DataFolder = "/var/lib/navidrome/data";
      LogLevel = "info";
      Address = "0.0.0.0";
      Port = 4533;
      # Scrobbling — enable in Navidrome UI after first login
      LastFM.Enabled = true;
      ListenBrainz.Enabled = true;
    };
  };

  # --- Lidarr — music collection manager + Tubifarry plugin ---
  services.lidarr = {
    enable = true;
    dataDir = "/var/lib/lidarr";
    settings.update.automatically = false; # Nix manages the version

    extraPlugins = [
      {
        name = "Tubifarry";
        src = pkgs.fetchFromGitHub {
          owner = "TypNull";
          repo = "Tubifarry";
          rev = "v2.1.0";
          # Replace with the hash Nix prints on first build failure:
          hash = lib.fakeHash;
        };
      }
    ];
  };

  # --- slskd — Soulseek P2P downloader ---
  services.slskd = {
    enable = true;
    openFirewall = true; # opens port 50300 for Soulseek protocol
    environmentFile = "/var/lib/slskd/slskd.env";

    settings = {
      directories = {
        downloads = "${musicRoot}/downloads";
        incomplete = "${musicRoot}/downloads/.incomplete";
      };
      web.port = 5030;
      # Share music back to the network (optional — set to false to leech only)
      shares.directories = ["${musicRoot}/library"];
    };
  };

  # --- Shared music directories ---
  systemd.tmpfiles.rules = [
    "d ${musicRoot}             0755 lidarr navidrome - -"
    "d ${musicRoot}/downloads   0755 lidarr navidrome - -"
    "d ${musicRoot}/library     0755 lidarr navidrome - -"
    "d ${musicRoot}/explo       0755 lidarr navidrome - -"
  ];

  # --- Permissions ---
  # lidarr needs to write to the music root
  users.users.lidarr.extraGroups = ["navidrome"];
  users.users.navidrome.extraGroups = ["lidarr"];

  # --- Open firewall for web UIs ---
  networking.firewall.allowedTCPPorts = [
    4533  # navidrome
    5030  # slskd web UI
    8686  # lidarr
    7288  # explo
    5000  # aurral
  ];

  # --- Optional: reverse proxy hint ---
  # To expose these services via nginx/caddy, add virtualHost entries.
  # Example with services.nginx:
  #   services.nginx.virtualHosts."music.example.com" = {
  #     locations."/" = { proxyPass = "http://127.0.0.1:4533"; };
  #   };
}
