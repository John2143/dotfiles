# Attic Server — Nix binary cache on Tailscale
#
# Runs atticd on home-pi, listening only on the Tailscale interface.
# All Hetzner nodes push built paths here via attic watch-store.
# Subsequent nodes pull from the cache for near-instant deploys.
#
# Cache name: 2143nix (signing key in nix.settings.trusted-public-keys)
# Endpoint: http://100.64.0.2:8280 (static Tailscale IP)
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfgFile = pkgs.writeText "atticd.toml" ''
    listen = "100.64.0.2:8280"

    [database]
    url = "sqlite:///var/lib/attic/attic-server.db"

    [storage]
    type = "local"
    path = "/var/lib/attic/storage"

    [chunking]
    chunk-size = 65536
    nar-size-threshold = 65536
  '';
in {
  # ── Admin token (same token used by clients for login) ──
  age.secrets.attic-admin-token = {
    file = ../hetzner/secrets/hetzner/attic-token.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # ── State directory ──
  systemd.tmpfiles.rules = [
    "d /var/lib/attic 0755 root root - -"
  ];

  # ── atticd systemd service ──
  # atticd reads ATTIC_SERVER_TOKEN_HS256_SECRET from environment.
  # agenix decrypts to a file, so we use a wrapper script to export the env var.
  systemd.services.atticd = {
    description = "Attic Nix binary cache server";
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target" "tailscaled.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.attic-server];

    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "atticd-start" ''
        export ATTIC_SERVER_TOKEN_HS256_SECRET="$(cat ${config.age.secrets.attic-admin-token.path})"
        exec atticd --config ${cfgFile}
      '';
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "attic";
      # Ensure the state dir exists (systemd creates /var/lib/attic via StateDirectory)
    };
  };

  # ── Firewall: allow Tailscale peers to reach atticd ──
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i tailscale0 -p tcp --dport 8280 -j nixos-fw-accept
  '';

  # ── Basic health check ──
  systemd.services.atticd-health = {
    description = "Verify atticd is responding";
    after = ["atticd.service"];
    wants = ["atticd.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      for i in $(seq 1 30); do
        if curl -sf http://100.64.0.2:8280/ >/dev/null 2>&1; then
          echo "atticd is healthy"
          exit 0
        fi
        sleep 1
      done
      echo "WARNING: atticd not responding after 30s"
      exit 1
    '';
  };
}
