# MariaDB Galera Cluster Member
#
# Multi-master replication for PowerDNS backend.
# Nodes: k3s-ashburn, k3s-hillsboro, k3s-nuremberg, home-pi.
#
# BOOTSTRAP PROCEDURE (run after all 4 nodes are on the tailnet):
#   1. On home-pi (bootstrap the cluster):
#      sudo systemctl stop mysql
#      sudo rm -f /run/mysqld/mysqld.sock
#      echo 1 | sudo tee /var/lib/mysql/grastate.dat
#      sudo systemctl start mysql
#      # Verify: sudo mysql -e "SHOW STATUS LIKE 'wsrep%'" | grep -E 'cluster_size|status'
#      # Should show cluster_size=1, cluster_status=Primary
#
#   2. On each Hetzner node (join the cluster):
#      sudo systemctl restart mysql
#      # MySQL will auto-join via wsrep_cluster_address (Tailscale DNS)
#      # Verify cluster_size grows: 1 → 2 → 3 → 4
#
# NOTE: MariaDB 11.x requires wsrep_on=1 and binlog_format=ROW (set below).
#       The wsrep_provider must be explicitly loaded (set below).
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
    package = pkgs.mariadb;
  };

  services.mysql.settings = {
    mysqld = {
      innodb_flush_log_at_trx_commit = 2;
      innodb_buffer_pool_size = "128M";

      # Galera requires ROW-based binary logging
      binlog_format = "ROW";

      wsrep_provider = "${pkgs.mariadb-galera}/lib/galera/libgalera_smm.so";
      wsrep_on = 1;  # Required in MariaDB 11.x (defaults to OFF)
      wsrep_cluster_name = "powerdns";
      wsrep_cluster_address = lib.mkDefault "gcomm://k3s-ashburn.ts.9s.pics,k3s-hillsboro.ts.9s.pics,k3s-nuremberg.ts.9s.pics,home-pi-clnydbkx.ts.9s.pics";
      wsrep_node_name = lib.mkDefault "${config.networking.hostName}";
      wsrep_node_address = lib.mkDefault "";  # auto-detect (correct for single-interface Hetzner nodes)

      wsrep_sst_method = "rsync";
      wsrep_slave_threads = 2;
      wsrep_certify_nonPK = 1;

      auto_increment_increment = 4;  # 4 nodes: ashburn, hillsboro, nuremberg, home-pi
      auto_increment_offset = lib.mkDefault 1;
    };
  };

  # Wait for Tailscale DNS before starting MariaDB (Galera needs cross-node resolution)
  systemd.services.mysql = {
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
    # rsync and mariadb bin must be in PATH for wsrep_sst_method=rsync to work
    # (posix_spawnp needs to find wsrep_sst_rsync and rsync)
    path = [ pkgs.rsync pkgs.mariadb ];
    # ProtectSystem=strict and stacked systemd hardening options create 21 seccomp
    # filters that block execve/clone in child processes, breaking posix_spawnp()
    # used by wsrep_sst_rsync.  Explicitly allow @process syscalls to override.
    serviceConfig = {
      ProtectSystem = lib.mkForce "full";
      SystemCallFilter = lib.mkForce "@default @process";
    };
  };

  # Galera ports: 4567 (group comm), 4568 (IST), 4444 (SST/rsync)
  networking.firewall.allowedTCPPorts = [ 4444 4567 4568 ];
}
