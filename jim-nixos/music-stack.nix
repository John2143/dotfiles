# =============================================================================
# Music stack — full Spotify replacement (self-hosted)
# =============================================================================
#
# Components:
#   Navidrome   → http://localhost:4533   music streaming (Subsonic API)
#   Lidarr      → http://localhost:8686   music collection manager
#   slskd       → http://localhost:5030   Soulseek P2P downloader
#   explo       → http://localhost:7288   auto-playlists (daily/weekly/monthly)
#   aurral      → http://localhost:5000   music requests (like Overseerr)
#   Tubifarry   → Lidarr plugin           wires slskd + lyrics into Lidarr
#
# Music data lives under /var/lib/music/:
#   downloads/    lidarr incomplete downloads
#   library/      finished imports → navidrome scans this
#   explo/        explo playlists (mounted as /data in the container)
#
# =============================================================================
# INSTALL INSTRUCTIONS
# =============================================================================
#
# --- Step 1: enable the module ---
#
#   In jim-nixos/configuration.nix, uncomment this line:
#     imports = [ ./music-stack.nix ];
#
# --- Step 2: create a Soulseek account ---
#
#   Download a client from https://www.slsknet.org, launch it, and register
#   a username + password. You can uninstall the client afterwards.
#
# --- Step 3: create the slskd credentials file ---
#
#     sudo mkdir -p /var/lib/slskd
#     echo 'SLSKD_SLSK_USERNAME=your-username' | sudo tee /var/lib/slskd/slskd.env
#     echo 'SLSKD_SLSK_PASSWORD=your-password' | sudo tee -a /var/lib/slskd/slskd.env
#     sudo chmod 600 /var/lib/slskd/slskd.env
#
# --- Step 4: sign up for MusicBrainz + ListenBrainz ---
#
#   https://musicbrainz.org/         (metadata)
#   https://listenbrainz.org/        (sign in with MusicBrainz — recommendations)
#
#   Do this on a Thursday/Friday so ListenBrainz has time to build your first
#   weekly recommendation playlist by Monday.
#
# --- Step 5: fix the Tubifarry hash ---
#
#   The fetchFromGitHub call below uses lib.fakeHash. On first build, Nix will
#   print the correct hash. Copy it into the `hash =` field and rebuild.
#
# --- Step 6: rebuild ---
#
#     sudo nixos-rebuild switch --flake .#jim
#
#   If this is a fresh install from the live ISO:
#     sudo nixos-install --flake .#jim && reboot
#     # then after reboot, run step 6 again to pick up the fixed hash
#
# --- Step 7: post-install setup ---
#
#   7a. Open Lidarr (http://localhost:8686) → Settings → Plugins.
#       Tubifarry should appear. Configure:
#         • Soulseek (point at http://localhost:5030 with your creds)
#         • Lyrics Enhancer
#         • Search Sniper
#
#   7b. Open Navidrome (http://localhost:4533) → Profile (top-right avatar).
#       Enable "Scrobble to ListenBrainz" so your listens feed recommendations.
#
#   7c. Open aurral (http://localhost:5000) → follow the setup wizard.
#       Connect it to Lidarr and Navidrome.
#       Click "Apply Davo's Recommended Settings."
#
#   7d. (Optional) Set up a reverse proxy if you want these accessible from
#       outside your LAN. Caddy example:
#
#         services.caddy.virtualHosts."music.example.com".extraConfig = ''
#           reverse_proxy localhost:4533
#         '';
#
# --- Daily use ---
#
#   • Add artists in Lidarr or request them through aurral.
#   • Lidarr searches Soulseek via Tubifarry and downloads matching releases.
#   • Stream from Navidrome directly, or use any Subsonic-compatible client:
#       https://www.navidrome.org/apps/
#   • explo generates daily/weekly/monthly playlists automatically.
#   • ListenBrainz sends a fresh "Discover" playlist every Monday.
#
# =============================================================================
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
