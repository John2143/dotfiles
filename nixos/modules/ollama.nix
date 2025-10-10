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
    package = pkgs-stable.ollama;
    loadModels = [
      #"deepseek-coder-v2"
      #"llama3.2"
    ];
  };
}
