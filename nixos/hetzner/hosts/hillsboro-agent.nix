# Hillsboro Agent — CPX31, US West
# k3s agent + workloads. HA toggle node.
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
    ../modules/hetzner-k3s-agent.nix
  ];

  networking.hostName = "k3s-hillsboro-agent";

  services.k3s.serverAddr = "https://k3s-hillsboro:6443";

  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
