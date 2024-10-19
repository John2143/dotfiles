
{ config, lib, pkgs, pkgs-stable, ... }:

{
  services.ollama = {
    loadModels = [
      "deepseek-coder-v2"
      "llama3.2"
    ];
  };
}
