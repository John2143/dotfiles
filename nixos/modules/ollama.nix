
{ config, lib, pkgs, pkgs-stable, ... }:

{
  services.ollama = {
    enable = true;
    loadModels = [
      "deepseek-coder-v2"
      "llama3.2"
    ];
  };
}
