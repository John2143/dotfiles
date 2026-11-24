# Valve Base Station 2.0 power management over BLE: see basestation.sh.
# The stations boot ON after a power cut (firmware default). This host has no
# UPS, so a power cut reboots the PC with them; the boot timer returns every
# LHB-* station to standby, and `basestation` drives them by hand.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.basestation;
  basestation = pkgs.writeShellApplication {
    name = "basestation";
    runtimeInputs = with pkgs; [bluez jq procps gawk gnugrep coreutils config.systemd.package];
    text = builtins.readFile ./basestation.sh;
  };
in {
  options.custom.basestation = {
    enable = lib.mkEnableOption "Valve base station BLE power management";
    standbyInterval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "How often to return stations to standby while the machine is up.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [basestation];

    systemd.services.basestation-standby = {
      description = "Return Valve base stations to standby";
      after = ["bluetooth.service"];
      wants = ["bluetooth.service"];
      serviceConfig = {
        Type = "oneshot";
        # Give stations powered up alongside the PC time to finish booting.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 20";
        ExecStart = "${basestation}/bin/basestation standby --if-idle";
        TimeoutStartSec = "5min";
      };
    };

    systemd.timers.basestation-standby = {
      description = "Return Valve base stations to standby";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitInactiveSec = cfg.standbyInterval;
        AccuracySec = "1min";
      };
    };
  };
}
