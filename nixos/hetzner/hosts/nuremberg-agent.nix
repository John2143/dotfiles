# Nuremberg Agent — CPX32, EU
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

  networking.hostName = "k3s-nuremberg-agent";

  services.k3s.serverAddr = "https://k3s-nuremberg:6443";

  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
