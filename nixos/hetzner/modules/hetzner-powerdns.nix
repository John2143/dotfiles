# PowerDNS Authoritative Server
#
# Provides authoritative DNS. Backend: MariaDB Galera (gmysql).
# RFC2136 enabled for ExternalDNS. Listens on public IP for k8gb queries.
#
# API key is derived from the TSIG key at runtime (systemd preStart).
{
  config,
  lib,
  pkgs,
  ...
}: {
  age.secrets."hetzner/powerdns-tsig-key" = {
    file = ../secrets/hetzner/powerdns-tsig-key.age;
    owner = "pdns";
    group = "pdns";
  };

  services.powerdns = {
    enable = true;
    extraConfig = ''
      launch=gmysql
      gmysql-host=127.0.0.1
      gmysql-port=3306
      gmysql-dbname=pdns
      gmysql-user=pdns

      local-address=0.0.0.0
      local-port=53

      dnsupdate=yes
      allow-dnsupdate-from=127.0.0.0/8

      default-ttl=60

      api=yes
      api-key=@PDNS_API_KEY@
      webserver=yes
      webserver-address=127.0.0.1
      webserver-port=8081

      allow-axfr-ips=127.0.0.1
    '';
  };

  systemd.services.pdns = {
    after = ["mysql.service"];
    wants = ["mysql.service"];
    before = ["k3s.service"];

    # Generate API key from TSIG key at runtime.
    # /etc/pdns/pdns.conf is a symlink into the read-only Nix store,
    # so we write to /run/pdns/ and tell pdns to use that config dir.
    preStart = ''
      mkdir -p /run/pdns
      API_KEY=$(sha256sum "${config.age.secrets."hetzner/powerdns-tsig-key".path}" | head -c 32)
      sed "s/@PDNS_API_KEY@/$API_KEY/" /etc/pdns/pdns.conf > /run/pdns/pdns.conf
    '';

    # Override ExecStart to use the runtime-generated config
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.powerdns}/bin/pdns_server --config-dir=/run/pdns --guardian=no --daemon=no --disable-syslog --log-timestamp=no --write-pid=no"
    ];
  };

  networking.firewall.allowedTCPPorts = [53 8081];
  networking.firewall.allowedUDPPorts = [53];
}
