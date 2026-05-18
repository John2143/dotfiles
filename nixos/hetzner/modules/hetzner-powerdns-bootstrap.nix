# PowerDNS Zone Bootstrap
#
# Oneshot systemd service that creates the 9s.pics zone and TSIG key
# in PowerDNS on first boot. Uses pdnsutil (pdns 5.0.x command syntax).
# State file prevents re-run.
#
# Runs on all 3 server nodes + Home Pi (via mkServer/mkHome).
# Only the first node to execute creates the zone — Galera replicates to others.
# State file guard prevents re-execution on any node.
#
# NOTE: pdns 5.0.x renamed many subcommands:
#   create-zone → zone create
#   set-kind → zone set-kind
#   set-soa → rrset replace (set-soa removed)
#   generate-tsig-key → tsigkey generate
#   set-tsig-key → tsigkey import
#   add-record → rrset add
#   set-meta → metadata set
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

      # Create zone (pdns 5.0.x: zone create replaces create-zone)
      pdnsutil zone create 9s.pics
      pdnsutil zone set-kind 9s.pics master
      # Set SOA via rrset replace (set-soa removed in 5.0.x)
      pdnsutil rrset replace 9s.pics 9s.pics SOA 60 "ns1.9s.pics. hostmaster.9s.pics. 1 10800 3600 604800 60"

      # Create TSIG key for ExternalDNS RFC2136 updates
      TSIG_KEY=$(tr -d '\n' < "${config.age.secrets."hetzner/powerdns-tsig-key".path}")
      pdnsutil tsigkey generate externaldns hmac-sha256 2>/dev/null || true
      pdnsutil tsigkey import externaldns hmac-sha256 "$TSIG_KEY"

      # Set NS records
      pdnsutil rrset add 9s.pics 9s.pics NS 60 ns1.9s.pics
      pdnsutil rrset add 9s.pics 9s.pics NS 60 ns2.9s.pics
      pdnsutil rrset add 9s.pics 9s.pics NS 60 ns3.9s.pics

      # Allow TSIG key to update the zone
      pdnsutil metadata set 9s.pics TSIG-ALLOW-DNSUPDATE externaldns
      pdnsutil metadata set 9s.pics ALLOW-DNSUPDATE-FROM 127.0.0.0/8

      touch "$STATE_FILE"
      echo "Zone 9s.pics bootstrapped successfully."
    '';

    scriptArgs = "%S";
  };


  # State directory
  systemd.tmpfiles.rules = [
    "d /var/lib 0755 root root - -"
  ];
}
