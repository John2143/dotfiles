{
  config,
  lib,
  pkgs,
  pkgs-stable,
  ...
}:

{
  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # NAS CIFS mounts (modules/nas-mounts.nix) use uid=1000/gid=1000 so only `john` can write.
  # The stock ollama unit uses DynamicUser with a different UID, which breaks pulls to
  # /mnt/nas/share/... with "permission denied".
  systemd.services.ollama.serviceConfig = {
    User = lib.mkForce "john";
    Group = lib.mkForce "users";
    DynamicUser = lib.mkForce false;
    PrivateUsers = lib.mkForce false;
  };
}
