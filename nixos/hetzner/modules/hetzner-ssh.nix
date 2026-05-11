# Shared SSH authorized keys for root
#
# Imported by all Hetzner host configs (servers, agents, home-pi).
# Eliminates the `users.users.root.openssh.authorizedKeys.keys = sshKeys`
# duplication across 7 files.
{ sshKeys, ... }: {
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
