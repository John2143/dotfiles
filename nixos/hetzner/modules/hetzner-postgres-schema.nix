# PostgreSQL Schema Import — PowerDNS backend
#
# Oneshot systemd service that waits for the CloudNativePG PostgreSQL
# cluster to be reachable (via NodePort), then imports the PowerDNS
# schema. State file prevents re-run.
#
# Runs on all 3 server nodes + Home Pi.
# On Hetzner nodes: connects to 127.0.0.1:30432 (local NodePort)
# On Home Pi: connects to k3s-ashburn.ts.9s.pics:30432 (remote via tailnet)
{
  config,
  lib,
  pkgs,
  postgresHost ? "127.0.0.1",
  ...
}: {
  systemd.services.hetzner-postgres-schema = {
    description = "Import PowerDNS schema into CloudNativePG PostgreSQL";
    after = ["network.target" "tailscaled.service"];
    wants = ["network.target" "tailscaled.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.postgresql pkgs.pdns];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      STATE_FILE=/var/lib/postgres-schema-done
      if [ -f "$STATE_FILE" ]; then
        echo "Schema import already done, skipping."
        exit 0
      fi

      echo "Waiting for PostgreSQL at ${postgresHost}:30432..."
      for i in $(seq 1 60); do
        if pg_isready -h ${postgresHost} -p 30432 -U pdns -d pdns 2>/dev/null; then
          echo "PostgreSQL is ready."
          break
        fi
        echo "  attempt $i/60..."
        sleep 5
      done

      if ! pg_isready -h ${postgresHost} -p 30432 -U pdns -d pdns 2>/dev/null; then
        echo "ERROR: PostgreSQL not reachable after 5 minutes."
        exit 1
      fi

      # Check if schema already imported (table 'domains' exists)
      if PGPASSWORD=$(cat ${config.age.secrets."hetzner/postgres-pdns-password".path}) \
         psql -h ${postgresHost} -p 30432 -U pdns -d pdns \
         -c "SELECT 1 FROM domains LIMIT 1" &>/dev/null; then
        echo "Schema already imported, skipping."
        touch "$STATE_FILE"
        exit 0
      fi

      echo "Importing PowerDNS schema..."
      PGPASSWORD=$(cat ${config.age.secrets."hetzner/postgres-pdns-password".path}) \
        psql -h ${postgresHost} -p 30432 -U pdns -d pdns \
        -f ${pkgs.pdns}/share/doc/pdns/schema.pgsql.sql

      echo "Schema imported successfully."
      touch "$STATE_FILE"
    '';
  };

  # agenix secret: pdns PostgreSQL user password
  age.secrets."hetzner/postgres-pdns-password" = {
    file = ../secrets/hetzner/postgres-pdns-password.age;
    owner = "pdns";
    group = "pdns";
  };

  # State directory
  systemd.tmpfiles.rules = [
    "d /var/lib 0755 root root - -"
  ];
}
