# Ashburn Agent — CPX31, US East
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

  networking.hostName = "k3s-ashburn-agent";

  # Join Ashburn server's k3s cluster
  services.k3s.serverAddr = "https://k3s-ashburn:6443";

  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
