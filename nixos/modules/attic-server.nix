# Attic Server — Nix binary cache on Tailscale
#
# Runs atticd on home-pi, listening on 0.0.0.0:8280 (port-forwarded through home router).
# All Hetzner nodes push/pull via http://headscale.9s.pics:8280.
# Works both pre-Tailscale (via port forward) and post-Tailscale.
# Cache name: 2143nix (signing key in nix.settings.trusted-public-keys)
# Endpoint: http://headscale.9s.pics:8280 (port-forwarded)
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfgFile = pkgs.writeText "atticd.toml" ''
    listen = "0.0.0.0:8280"

    [database]
    url = "sqlite:///var/lib/attic/attic-server.db"

    [storage]
    type = "local"
    path = "/var/lib/attic/storage"

    [chunking]
    nar-size-threshold = 65536
    min-size = 16384
    avg-size = 65536
    max-size = 262144
  '';
in {
  # ── HS256 server secret (base64-encoded, used by atticd for JWT signing) ──
  age.secrets.attic-admin-token = {
    file = ../hetzner/secrets/hetzner/attic-server-secret.age;
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
        export ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64="$(cat ${config.age.secrets.attic-admin-token.path})"
        touch /var/lib/attic/attic-server.db  # SQLite needs file to exist (aarch64 quirk)
        exec atticd --config ${cfgFile}
      '';
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "attic";
      # Ensure the state dir exists (systemd creates /var/lib/attic via StateDirectory)
    };
  };

  # ── Firewall: allow port-forwarded access to atticd ──
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp --dport 8280 -j nixos-fw-accept
  '';

  # ── Basic health check ──
  systemd.services.atticd-health = {
    description = "Verify atticd is responding";
    after = ["atticd.service"];
    wants = ["atticd.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      for i in $(seq 1 30); do
        if curl -sf http://localhost:8280/ >/dev/null 2>&1; then
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
