let
  # Per-machine age keys (~/.ssh/age on each host).
  # Generate on a new computer with: ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p
  # Then add the public key here and re-encrypt any secrets that host should read.
  #
  # Re-encrypt all secrets (run from the office host, the admin):
  #   cd ~/dotfiles/secrets && agenix -r -i ~/.ssh/age
  #
  # NOTE: The k3s token committed before this was introduced is in git history.
  # Rotate the k3s cluster token to fully remove exposure.
  office = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office";
  arch = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbTSIq65Gz8pgHX5uLas3Z/paU9SC5KvG1G2lNMfPH7 john@arch";
  closet = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN3VC6q1KhVCI3BRzbTi9Di/pS7I1ASEYoNBwBzU4jgT john@closet";
  pite = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAh9fgjUMvSfYUYteUHeI/JkjxUJLwVAnoLyluU1Uknd john@pite";
  security = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILO6ntnqr4ERZLUdL2MOMeC++HPIsigce4d42h8UogA2 john@security";
  secu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4vMixKG/e9b3ttJy9Xb5ymavp7Gny6dxKrViQl8AUl john@secu";
  nas = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzgxUuaZUG9Dr5ZTZImKqt3SUSPVD/FLO2wKQfwz98A john@nas";
  # generate with `ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p` on each host, then paste here

  # Collect all keys that should be able to re-encrypt / manage secrets.
  allKeys = [ office arch ];
in
{
  # Readable only by the office machine (k3s agent token).
  "k3s-local-token.age".publicKeys = [ office arch pite ];
  # Samba credentials for mounting NAS shares (username/password/domain).
  "smb-credentials.age".publicKeys = [ arch office closet secu ];
  # Per-machine restic repository passwords (each machine can only decrypt its own).
  # Generate: agenix -e restic-password-<host>.age -i ~/.ssh/age
  "restic-password-arch.age".publicKeys = [ arch office ];
  "restic-password-office.age".publicKeys = [ office arch ];
  "restic-password-closet.age".publicKeys = [ closet office arch ];
  "restic-password-secu.age".publicKeys = [ secu office arch ];
  # Private SSH key for the backup user on the NAS (all backup clients need this).
  # Generate once: ssh-keygen -t ed25519 -f /tmp/backup-key -N "" -C "backup@nas"
  # Then: agenix -e backup-ssh-key.age -i ~/.ssh/age  (paste the private key)
  # Add the public key to nas-configuration.nix backup user's authorizedKeys.
  "backup-ssh-key.age".publicKeys = [ office arch closet secu ];
  # gocryptfs passphrase for encrypted vault on NAS scratch share.
  # Only workstations that mount the vault need this — the NAS never sees the key.
  "gocryptfs-passphrase.age".publicKeys = [ arch office closet ];
  # RustFS (minio) credentials for bigjuush/juush.
  # Format: RUSTFS_USER=...\nRUSTFS_PASSWORD=...\nJUUSH_KEY=...
  "rustfs-credentials.age".publicKeys = [ office arch nas closet ];
}
