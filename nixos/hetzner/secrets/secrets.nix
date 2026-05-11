# Hetzner sub-flake — agenix secrets configuration
let
  office = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office";
  arch = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbTSIq65Gz8pgHX5uLas3Z/paU9SC5KvG1G2lNMfPH7 john@arch";
  allKeys = [office arch];
in {
  "hetzner/powerdns-tsig-key.age".publicKeys = allKeys;
  "hetzner/galera-password.age".publicKeys = allKeys;
  "hetzner/mariadb-root-password.age".publicKeys = allKeys;
  "hetzner/k3s-token.age".publicKeys = allKeys;
  "hetzner/hcloud-token.age".publicKeys = allKeys;
  "hetzner/luks-passphrase.age".publicKeys = allKeys;
  "hetzner/mongodb-encryption-key.age".publicKeys = allKeys;
  "hetzner/rclone-b2-password.age".publicKeys = allKeys;
  "hetzner/rclone-rustfs-password.age".publicKeys = allKeys;
  "hetzner/seaweedfs-master-key.age".publicKeys = allKeys;
  "hetzner/headscale-preauth-key.age".publicKeys = allKeys;
  "hetzner/pdns-api-key.age".publicKeys = allKeys;
}
