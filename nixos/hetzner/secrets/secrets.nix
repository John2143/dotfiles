# Hetzner sub-flake — agenix secrets configuration
let
  office = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office";
  arch = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbTSIq65Gz8pgHX5uLas3Z/paU9SC5KvG1G2lNMfPH7 john@arch";
  aman = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILO6ntnqr4ERZLUdL2MOMeC++HPIsigce4d42h8UogA2 john@security";
  allKeys = [office arch aman];
in {
  "hetzner/powerdns-tsig-key.age".publicKeys = allKeys;
  "hetzner/postgres-pdns-password.age".publicKeys = allKeys;
  "hetzner/k3s-token.age".publicKeys = allKeys;
  "hetzner/hcloud-token.age".publicKeys = allKeys;
  "hetzner/luks-passphrase.age".publicKeys = allKeys;
  "hetzner/mongodb-encryption-key.age".publicKeys = allKeys;
  "hetzner/rclone-b2-password.age".publicKeys = allKeys;
  "hetzner/rclone-rustfs-password.age".publicKeys = allKeys;
  "hetzner/seaweedfs-master-key.age".publicKeys = allKeys;
  "hetzner/headscale-preauth-key.age".publicKeys = allKeys;
  "hetzner/desec-token.age".publicKeys = allKeys;
  "hetzner/attic-token.age".publicKeys = allKeys;
}
