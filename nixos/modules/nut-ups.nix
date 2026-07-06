# Shared NUT UPS monitoring module.
#
# usbhid-ups with port=auto auto-detects any USB HID UPS (APC, Goldenmate, etc.).
# Common 6s ONBATT delay, then host-specific hooks depending on options.
# Every machine runs standalone — each has its own directly-connected UPS.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}:
let
  cfg = config.custom.nut-ups;

  # ── Conditional shell fragments for the event handler ──
  haSource = lib.optionalString cfg.haWebhooks ''
    set -a; source /run/agenix/hass-webhooks; set +a
    machine=$(echo '${compName}' | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')
    ONBATTERY_URL=$(eval echo \$''${machine}_ONBATTERY_URL)
    OFFBATTERY_URL=$(eval echo \$''${machine}_OFFBATTERY_URL)
  '';


  onbatteryNotify = lib.optionalString cfg.desktopNotifications ''
    ${pkgs.libnotify}/bin/notify-send -u critical "UPS" "On battery power" || true
  '';

  onlineNotify = lib.optionalString cfg.desktopNotifications ''
    ${pkgs.libnotify}/bin/notify-send -u normal "UPS" "Power restored" || true
  '';

  lowbatteryNotify = lib.optionalString cfg.desktopNotifications ''
    ${pkgs.libnotify}/bin/notify-send -u critical "UPS" "Battery critical — shutting down NOW" || true
  '';

  haOnbattery = lib.optionalString cfg.haWebhooks ''
    ${pkgs.curl}/bin/curl -s -X POST "$ONBATTERY_URL" || true
  '';


  haOffbattery = lib.optionalString cfg.haWebhooks ''
    ${pkgs.curl}/bin/curl -s -X POST "$OFFBATTERY_URL" || true
  '';

  k3sDrain = lib.optionalString cfg.k3sDrain ''
    sudo ${pkgs.k3s}/bin/k3s kubectl drain ${compName} --ignore-daemonsets --delete-emptydir-data --grace-period=90 --timeout=150s 2>/dev/null || true
  '';

  extraCmds = lib.concatMapStringsSep "\n" (cmd: "    sudo ${cmd} || true") cfg.extraShutdownCommands;

  lowbatteryWall = lib.optionalString cfg.k3sDrain ''
      sudo ${pkgs.util-linux}/bin/wall "UPS battery critical — draining k3s node and shutting down NOW" || true'';

  lowbatteryWallSimple = lib.optionalString (!cfg.k3sDrain) ''
      sudo ${pkgs.util-linux}/bin/wall "UPS battery critical — shutting down NOW" || true'';
in
{
  options.custom.nut-ups = {
    enable = lib.mkEnableOption "NUT UPS monitoring (usbhid-ups auto-detect)";
    haWebhooks = lib.mkEnableOption "Home Assistant webhook POST on power events";
    k3sDrain = lib.mkEnableOption "k3s node drain before shutdown (Longhorn replica promotion)";
    desktopNotifications = lib.mkEnableOption "notify-send desktop alerts on power events";
    extraShutdownCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra shell commands to run before poweroff (e.g. systemctl stop atticd)";
    };
    poweroffArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Extra args to systemctl poweroff (e.g. -f)";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.nut-ups-password = {
      file = ../../secrets/nut-ups-password.age;
      owner = "nutmon";
      group = "nutmon";
      mode = "0400";
    };

    age.secrets.hass-webhooks = lib.mkIf cfg.haWebhooks {
      file = ../../secrets/hass-webhooks.age;
      owner = "root";
      mode = "0444";
    };

    users.users.nutmon.extraGroups = lib.mkIf (cfg.haWebhooks || cfg.desktopNotifications || cfg.k3sDrain) [ "tty" ];

    # nutmon runs the event handler via upsmon's NOTIFYCMD. wall, k3s drain,
    # and systemctl poweroff all need root — grant passwordless sudo.
    security.sudo.extraRules = lib.mkIf cfg.enable [
      {
        users = ["nutmon"];
        commands = [{ command = "ALL"; options = ["NOPASSWD"]; }];
      }
    ];

    power.ups = {
      enable = true;
      mode = "standalone";
      maxStartDelay = 15;

      ups.main = {
        driver = "usbhid-ups";
        port = "auto";
        description = "USB UPS (auto-detect)";
      };

      users.monitor = {
        passwordFile = config.age.secrets.nut-ups-password.path;
        actions = [ "SET" "FSD" ];
        instcmds = [ "ALL" ];
        upsmon = "primary";
      };

      upsmon = {
        enable = true;
        settings = {
          NOTIFYFLAGS = "EXEC";
        };
        monitor.main = {
          system = "main@localhost";
          user = "monitor";
          powerValue = 1;
          type = "master";
        };
      };

      schedulerRules = "${pkgs.writeText "upssched.conf" (''
        CMDSCRIPT ${pkgs.writeShellScript "nut-event-handler" ''
  ${haSource}
          event_type="$1"
          case "$event_type" in
            onbattery)
              sudo ${pkgs.util-linux}/bin/wall "UPS on battery — ${compName} shutting down when critical" || true
  ${onbatteryNotify}
  ${haOnbattery}
              ;;
            online)
              sudo ${pkgs.util-linux}/bin/wall "UPS power restored on ${compName}" || true
  ${onlineNotify}
  ${haOffbattery}
              ;;
            lowbattery)
  ${lowbatteryWall}
  ${lowbatteryWallSimple}
  ${lowbatteryNotify}
  ${k3sDrain}
  ${extraCmds}
              sleep 5
              sudo ${pkgs.systemd}/bin/systemctl poweroff ${cfg.poweroffArgs}
              ;;
            *)
              logger -t nut-event-handler "Unknown event: $event_type"
              ;;
          esac
        ''}
        PIPEFN /run/nut/upssched.pipe
        LOCKFN /run/nut/upssched.lock
        AT ONBATT * EXECUTE onbattery
        AT ONLINE * EXECUTE online
        AT LOWBATT * EXECUTE lowbattery
      '')}";
    };
  };
}
