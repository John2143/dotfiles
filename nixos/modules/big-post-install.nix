# Post-install module for big.
# Uncomment in flake.nix AFTER generating the age key and re-encrypting secrets:
#   1. ssh-keygen -f ~/.ssh/age -N "" -C "john@big"
#   2. cat ~/.ssh/age.pub  → paste into secrets/secrets.nix as "big = ..."
#   3. On office: cd ~/dotfiles/secrets && agenix -r -i ~/.ssh/age
#   4. Rebuild: sudo nixos-rebuild switch --flake .#big
{
  ...
}: {
  imports = [
    ./k3s-agent.nix
    ./restic-backup.nix
    ./attic.nix
    ./remote-builders.nix
  ];
}
