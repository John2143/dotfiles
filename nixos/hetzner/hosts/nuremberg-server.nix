# Nuremberg Server — CPX32, EU
# PowerDNS + MariaDB Galera + k3s server
{
  config,
  lib,
  pkgs,
  inputs,
  compName,
  sshKeys,
  ...
}: {
  imports = [
    ../modules/hetzner-disko.nix
    ../modules/hetzner-k3s-server.nix
  ];

  networking.hostName = "k3s-nuremberg";

  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  # Galera node-specific
  services.mysql.settings.mysqld = {
    wsrep_cluster_address = "gcomm://ashburn-server,nuremberg-server,home-pi";
    wsrep_node_name = "k3s-nuremberg";
    auto_increment_offset = 2;
  };
}
