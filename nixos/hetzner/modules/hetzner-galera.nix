# MariaDB Galera Cluster Member
#
# Multi-master replication for PowerDNS backend across 3 locations.
# Nodes: ashburn-server, nuremberg-server, home-pi.
{
  config,
  lib,
  pkgs,
  ...
}: {
  age.secrets."hetzner/galera-password" = {
    file = ../secrets/hetzner/galera-password.age;
    owner = "mysql";
    group = "mysql";
  };
  age.secrets."hetzner/mariadb-root-password" = {
    file = ../secrets/hetzner/mariadb-root-password.age;
    owner = "mysql";
    group = "mysql";
  };

  services.mysql = {
    enable = true;
    package = pkgs.mariadb-galera;
  };

  services.mysql.settings = {
    mysqld = {
      innodb_flush_log_at_trx_commit = 2;
      innodb_buffer_pool_size = "128M";

      wsrep_provider = "${pkgs.mariadb-galera}/lib/galera/libgalera_smm.so";
      wsrep_cluster_name = "powerdns";
      wsrep_cluster_address = "gcomm://"; # Override per-node in host config
      wsrep_node_name = "${config.networking.hostName}";
      wsrep_node_address = "${lib.head config.networking.interfaces.eth0.ipv4.addresses}.address";

      wsrep_sst_method = "rsync";
      wsrep_slave_threads = 2;
      wsrep_certify_nonPK = 1;

      auto_increment_increment = 3;
      auto_increment_offset = 1;
    };
  };
}
