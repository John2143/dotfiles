# Shared SSH authorized keys for root
#
# Imported by all Hetzner host configs (servers, agents, home-pi).
# Eliminates the `users.users.root.openssh.authorizedKeys.keys = sshKeys`
# duplication across 7 files.
{ sshKeys, ... }: {
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
  services.openssh.enable = true;

  # agenix identity — reads the age private key from /etc/ssh/age-identity
  # This file must be manually provisioned (copied from admin machine).
  age.identityPaths = ["/etc/ssh/age-identity" "/etc/ssh/ssh_host_ed25519_key"];
}
