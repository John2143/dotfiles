# PowerDNS Zone Bootstrap
#
# Oneshot systemd service that creates the 9s.pics zone and TSIG key
# in PowerDNS on first boot. Uses pdnsutil (pdns 5.0.x command syntax).
# State file prevents re-run.
#
# Runs on all 3 server nodes + Home Pi (via mkServer/mkHome).
# Each node independently creates the zone in its own view of the
# PostgreSQL database (single CNPG cluster, shared data).
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
    after = ["pdns.service"];
    wants = ["pdns.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.pdns];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # State file in /var/lib guards against re-execution.
    script = ''
      STATE_FILE=/var/lib/pdns-zone-bootstrap-done
      if [ -f "$STATE_FILE" ]; then
        echo "Zone bootstrap already done, skipping."
        exit 0
      fi

      PDNSUTIL="pdnsutil --config-dir=/run/pdns"
      # Wait for pdns to be fully ready
      for i in $(seq 1 30); do
        $PDNSUTIL list-all-zones &>/dev/null && break
        sleep 2
      done

      # Check if zone already exists
      if $PDNSUTIL list-all-zones | grep -q "9s.pics"; then
        echo "Zone 9s.pics already exists, skipping creation."
        touch "$STATE_FILE"
        exit 0
      fi

      # Create zone (pdns 5.0.x: zone create replaces create-zone)
      $PDNSUTIL zone create 9s.pics
      $PDNSUTIL zone set-kind 9s.pics master
      # Set SOA via rrset replace (set-soa removed in 5.0.x)
      $PDNSUTIL rrset replace 9s.pics 9s.pics SOA 60 "ns1.9s.pics. hostmaster.9s.pics. 1 10800 3600 604800 60"

      # Create TSIG key for ExternalDNS RFC2136 updates
      TSIG_KEY=$(tr -d '\n' < "${config.age.secrets."hetzner/powerdns-tsig-key".path}")
      $PDNSUTIL tsigkey generate externaldns hmac-sha256 2>/dev/null || true
      $PDNSUTIL tsigkey import externaldns hmac-sha256 "$TSIG_KEY"

      # Set NS records
      $PDNSUTIL rrset add 9s.pics 9s.pics NS 60 ns1.9s.pics
      $PDNSUTIL rrset add 9s.pics 9s.pics NS 60 ns2.9s.pics
      $PDNSUTIL rrset add 9s.pics 9s.pics NS 60 ns3.9s.pics

      # Allow TSIG key to update the zone
      $PDNSUTIL metadata set 9s.pics TSIG-ALLOW-DNSUPDATE externaldns
      $PDNSUTIL metadata set 9s.pics ALLOW-DNSUPDATE-FROM 127.0.0.0/8

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
