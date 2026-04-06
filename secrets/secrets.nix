let
  # Per-machine age keys (~/.ssh/age on each host).
  # Generate on a new computer with: ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p
  # Then add the public key here and re-encrypt any secrets that host should read
  # using: nix run github:ryantm/agenix -- -r -i ~/.ssh/age
  #
  # NOTE: The k3s token committed before this was introduced is in git history.
  # Rotate the k3s cluster token to fully remove exposure.
  office = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office";
  arch = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbTSIq65Gz8pgHX5uLas3Z/paU9SC5KvG1G2lNMfPH7 john@arch";
  closet = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN3VC6q1KhVCI3BRzbTi9Di/pS7I1ASEYoNBwBzU4jgT john@closet";
  pite = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAh9fgjUMvSfYUYteUHeI/JkjxUJLwVAnoLyluU1Uknd john@pite";
  security = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILO6ntnqr4ERZLUdL2MOMeC++HPIsigce4d42h8UogA2 john@security";

  # Collect all keys that should be able to re-encrypt / manage secrets.
  allKeys = [ office arch closet pite security ];
in
{
  # Readable only by the office machine (k3s agent token).
  "k3s-local-token.age".publicKeys = [ office arch pite ];
}
