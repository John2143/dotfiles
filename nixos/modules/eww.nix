{ pkgs, ... }:
let
  ewwDir = ../../eww;
in {
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile "${ewwDir}/eww.yuck";
    scssConfig = builtins.readFile "${ewwDir}/eww.scss";
    systemd.enable = true;
  };
}
