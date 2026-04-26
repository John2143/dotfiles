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
}
