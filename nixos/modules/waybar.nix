{pkgs, compName, lib, ...}: {
  programs.waybar = {
    enable = true;
    style = ../../.config/waybar/style.css;
    settings = {
      mainBar = {
        # Global configuration
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [
          "hyprland/workspaces"
          "custom/newworkspace"
          "hyprland/window"
        ];
        modules-center = [];
        modules-right = [
          #"custom/mullvad"
          "cpu"
          "memory"
          "temperature"
        ] ++ (lib.optionals (compName == "arch") [
          "custom/thermostat"
          "custom/teamspeak-mic"
          "custom/teamspeak-sound"
        ]) ++ [
          "custom/vast"
          "custom/weather"
          "battery"
          "tray"
          "pulseaudio"
          "clock#date"
          "clock#time"
        ];
        # Modules configuration
        "hyprland/workspaces" = {
          format = "{name} {windows}";
          "workspace-taskbar" = {
            enable = true;
            "update-active-window" = true;
            "format" = "{icon}";
            "icon-size" = 20;
            "on-click-window" = "hyprctl dispatch focuswindow address:{address}";
            "ignore-list" = ["^xwaylandvideobridge$"];
          };
          persistent_workspaces = let
            left = if compName == "office" then "DP-2" else "DP-3";
            right = if compName == "office" then "DP-1" else "HDMI-A-2";
          in {
            "A1" = [left]; "A2" = [left]; "A3" = [left]; "A4" = [left]; "A5" = [left];
            "B1" = [right]; "B2" = [right]; "B3" = [right]; "B4" = [right]; "B5" = [right];
            "ts" = [right]; "disc" = [right]; "steam" = [right]; "obsidian" = [right]; "spotify" = [right];
          };
        };

        battery = {
          interval = 10;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "  {icon}  {capacity}%";
          format-discharging = "{icon}  {capacity}%";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
          tooltip = true;
        };

        "custom/newworkspace" = {
          format = "+";
          tooltip = true;
          tooltip-format = "Create new temporary workspace";
          on-click = "NAME=$(cat /dev/random | head -c 10 | sha1sum | head -c 6) && hyprctl dispatch workspace name:$NAME";
        };

        #"custom/mullvad" = {
        #interval = 20;
        #exec = "~/.config/get_mullvad.fish";
        #on-click = "${pkgs.mullvad-vpn}/bin/mullvad connect; sleep 2";
        #on-click-right = "${pkgs.mullvad-vpn}/bin/mullvad disconnect; sleep 1";
        #on-click-middle = "${pkgs.mullvad-vpn}/bin/mullvad reconnect; sleep 2";
        #exec-on-event = true;
        #};

        "clock#time" = {
          interval = 1;
          format = "{:%H:%M:%S}";
          tooltip = false;
        };

        "clock#date" = {
          interval = 10;
          format = "{:%e %b %Y}";
          tooltip-format = "{:%e %B %Y}";
        };

        cpu = {
          interval = 5;
          format = "cpu {usage}%";
          states = {
            warning = 70;
            critical = 90;
          };
        };

        memory = {
          interval = 5;
          format = "{used}Gb";
          states = {
            warning = 70;
            critical = 90;
          };
        };

        #network = {
        #interval = 5;
        #format-wifi = " {essid}";
        #format-ethernet = "󰈀 {ifname}";
        #format-disconnected = "󰈂 Disconnected";
        #tooltip-format = "[{ifname}] - {ipaddr}/{cidr} - ({signalStrength}%)";
        #};

        pulseaudio = {
          interval = 5;
          scroll-step = 3;
          format = "{icon} {volume}%";
          format-bluetooth = "{icon} {volume}%";
          #format-muted = "";
          format-muted = "m";
          format-icons = {
            headphones = "a"; # "";
            handsfree = "a"; # "";
            headset = "a"; # "";
            phone = "a"; # "";
            portable = "a"; # "";
            car = "a"; # "";
            default = [
              "a"
              "b"
            ]; # ["" ""];
          };
          onClickRight = "pavucontrol";
          onClickMiddle = "fish -c '/home/john/.config/polybar/scripts/sinks.fish bluetooth'";
          onClick = "fish -c '/home/john/.config/polybar/scripts/sinks.fish scarlett'";
        };

        temperature = {
          #rotate = 90;
          criticalThreshold = 80;
          interval = 1;
          format = "{temperatureC}°";
          thermalZone = "thermal_zone2";
          formatIcons = [
            "" # Icon: temperature-empty
            "" # Icon: temperature-quarter
            "" # Icon: temperature-half
            "" # Icon: temperature-three-quarters
            "" # Icon: temperature-full
          ];
          tooltip = true;
        };
      } // (lib.optionalAttrs (compName == "arch") {
        "custom/thermostat" = {
          exec = "hass-thermostat-status";
          return-type = "json";
          interval = 30;
          signal = 8;
          format = "{}";
          on-click-right = "hass-macro ac-toggle";
          on-scroll-up = "hass-macro thermostat-up";
          on-scroll-down = "hass-macro thermostat-down";
          on-click-middle = "hass-macro thermostat-toggle";
          tooltip = true;
        };

        "custom/teamspeak-mic" = {
          exec = "teamspeak-mute-status --mic";
          return-type = "json";
          interval = 2;
          format = "{}";
          tooltip = true;
          on-click = "teamspeak-mute-status --toggle";
        };
        "custom/teamspeak-sound" = {
          exec = "teamspeak-mute-status --sound";
          return-type = "json";
          interval = 2;
          format = "{}";
          tooltip = true;
          on-click = "teamspeak-mute-status --toggle-output";
        };
      }) // {
        "custom/vast" = {
          exec = "vast-waybar-status";
          return-type = "json";
          interval = 60;
          signal = 9;
          format = "{}";
          tooltip = true;
          on-click = "rm -f /tmp/vast-waybar-status.json && pkill -RTMIN+9 waybar";
        };
        "custom/weather" = {
          exec = "weather-status";
          return-type = "json";
          interval = 900;
          format = "{}";
          tooltip = true;
        };
        tray = {
          iconSize = 21;
          spacing = 10;
        };
      };
    };
  };

  systemd.user.services.waybar = {
    Unit = {
      Description = "Highly customizable Wayland bar for Sway and Wlroots based compositors";
      Documentation = "https://github.com/Alexays/Waybar/wiki/";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Requisite = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.waybar}/bin/waybar";
      ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
      Restart = "on-failure";
      TimeoutStopSec = 10;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}

