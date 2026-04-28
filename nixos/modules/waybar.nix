{pkgs, ...}: {
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
          "custom/thermostat"
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
        "custom/thermostat" = {
          exec = "hass-thermostat-status";
          return-type = "json";
          interval = 30;
          signal = 8;
          format = "{}";
          tooltip = true;
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
}
