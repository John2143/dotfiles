# PowerDNS Zone Bootstrap
#
# Oneshot systemd service that creates the 9s.pics zone and TSIG key
# in PowerDNS on first boot. Uses pdnsutil. State file prevents re-run.
#
# Only runs on nodes with PowerDNS (Ashburn, Nuremberg, Home Pi).
# Only one node needs to create the zone — Galera replicates it.
# Uses a state file guard so it only runs once cluster-wide.
{
  config,
  pkgs,
  ...
}: {
  systemd.services.pdns-zone-bootstrap = {
    description = "Create PowerDNS zone and TSIG key for 9s.pics";
    after = ["pdns.service" "mysql.service"];
    wants = ["pdns.service" "mysql.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.pdns];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # Only run on ashburn (first server provisioned). Galera replicates to others.
    # State file in /var/lib guards against re-execution.
    script = ''
      STATE_FILE=/var/lib/pdns-zone-bootstrap-done
      if [ -f "$STATE_FILE" ]; then
        echo "Zone bootstrap already done, skipping."
        exit 0
      fi

      # Wait for pdns to be fully ready
      for i in $(seq 1 30); do
        pdnsutil list-all-zones &>/dev/null && break
        sleep 2
      done

      # Check if zone already exists (replicated via Galera from another node)
      if pdnsutil list-all-zones | grep -q "9s.pics"; then
        echo "Zone 9s.pics already exists (replicated via Galera), skipping creation."
        touch "$STATE_FILE"
        exit 0
      fi

      # Create zone
      pdnsutil create-zone 9s.pics
      pdnsutil set-kind 9s.pics master
      pdnsutil set-soa 9s.pics "ns1.9s.pics hostmaster.9s.pics 1 10800 3600 604800 60"

      # Create TSIG key for ExternalDNS RFC2136 updates
      TSIG_KEY=$(tr -d '\n' < "${config.age.secrets."hetzner/powerdns-tsig-key".path}")
      pdnsutil generate-tsig-key externaldns hmac-sha256
      pdnsutil set-tsig-key externaldns "$TSIG_KEY"

      # Set NS records
      pdnsutil add-record 9s.pics @ NS ns1.9s.pics
      pdnsutil add-record 9s.pics @ NS ns2.9s.pics

      # Allow TSIG key to update the zone
      pdnsutil set-meta 9s.pics TSIG-ALLOW-DNSUPDATE externaldns
      pdnsutil set-meta 9s.pics ALLOW-DNSUPDATE-FROM 127.0.0.0/8

      touch "$STATE_FILE"
      echo "Zone 9s.pics bootstrapped successfully."
    '';

    scriptArgs = "%S";
  };

  # Access to the TSIG key secret
  age.secrets."hetzner/powerdns-tsig-key" = {
    file = ../secrets/hetzner/powerdns-tsig-key.age;
    owner = "root";
    group = "root";
  };

  # State directory
  systemd.tmpfiles.rules = [
    "d /var/lib 0755 root root - -"
  ];
}
