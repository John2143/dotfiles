# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
# ./shared-games-configuration.nix
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  ...
}:
let
  vast-waybar-status = pkgs.writeShellApplication {
    name = "vast-waybar-status";
    runtimeInputs = with pkgs; [ fish jq coreutils gnused gnugrep ];
    text = ''
      CACHE=/tmp/vast-waybar-status.json
      MAX_AGE=55

      if [ -f "$CACHE" ]; then
          age=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
          if [ "$age" -lt "$MAX_AGE" ]; then
              content=$(cat "$CACHE")
              if [ -n "$content" ]; then
                  echo "$content"
                  exit 0
              else
                  exit 1
              fi
          fi
      fi

      if output=$(timeout 15 fish -c "vast-status" 2>/dev/null); then
          label=$(echo "$output" | sed -n 's/=== Vast.ai status (label: \(.*\)) ===/\1/p')
          tunnel_line=$(echo "$output" | grep "^Tunnel:" || true)
          vllm_line=$(echo "$output" | grep "^vLLM:" || true)

          if echo "$tunnel_line" | grep -q "UP"; then
              if echo "$vllm_line" | grep -q "READY"; then
                  class="vast-ready"
                  icons="▲●"
              else
                  class="vast-tunnel-up"
                  icons="▲○"
              fi
          else
              class="vast-tunnel-down"
              icons="▼○"
          fi

          balance_out=$(timeout 10 fish -c "vast-balance" 2>/dev/null) || balance_out=""
          show_out=$(timeout 10 fish -c "vast-show" 2>/dev/null) || show_out=""

          # "Credit: $12.34" -> "12.34"
          balance=$(echo "$balance_out" | sed -n 's/Credit: \$//p') || balance=""
          # "... hourly=0.45 ..." -> "0.45"
          hourly=$(echo "$show_out" | sed -n 's/.*hourly=\([0-9.]*\).*/\1/p') || hourly=""

          hrs_str=""
          if [ -n "$balance" ] && [ -n "$hourly" ]; then
              hrs_str=$(jq -rn --arg b "$balance" --arg h "$hourly" '
                  ($b | tonumber) as $bal | ($h | tonumber) as $hr |
                  if $hr > 0 then
                      ($bal / $hr) as $total_hours |
                      ($total_hours | floor) as $hours |
                      (($total_hours - $hours) * 60 | round) as $minutes |
                      "\($hours):\($minutes | tostring | if length == 1 then "0" + . else . end)"
                  else "?:??" end
              ' 2>/dev/null) || hrs_str=""
          fi

          text="$label $icons"
          [ -n "$balance" ] && text="$text \$$balance"
          [ -n "$hrs_str" ] && text="$text $hrs_str"

          tooltip="$output"
          if [ -n "$balance" ] || [ -n "$hourly" ]; then
              tooltip="$tooltip

Balance:   \$$balance
Rate:      \$$hourly/hr
Remaining: ~$hrs_str"
          fi

          result=$(jq -nc --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
              '{text: $t, tooltip: $tt, class: $c}')
          printf '%s' "$result" > "$CACHE"
          echo "$result"
      else
          : > "$CACHE"
          exit 1
      fi
    '';
  };

  weather-status = pkgs.writeShellApplication {
    name = "weather-status";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      response=$(curl -sf "wttr.in/?format=j1") || {
        echo '{"text": "\u26a0", "class": "error", "tooltip": "Weather unavailable"}'
        exit 0
      }

      echo "$response" | jq -ce '
        .current_condition[0] as $cc |
        .weather as $w |
        ($cc.temp_F // "?") as $temp |
        if $temp == "?" then
          {text: "\u26a0", class: "error", tooltip: "Missing weather data"}
        else
          [
            "<b>\($cc.weatherDesc[0].value // "Unknown")</b>  \($temp)°F (feels \($cc.FeelsLikeF // "?")°F)",
            "Wind \($cc.windspeedMiles // "?") mph \($cc.winddir16Point // "?")  |  Humidity \($cc.humidity // "?")%",
            "UV \($cc.uvIndex // "?")  |  Pressure \($cc.pressureInches // "?") in  |  Vis \($cc.visibilityMiles // "?") mi",
            "",
            ( $w | to_entries[] |
              (if .key == 0 then "Today"
               elif .key == 1 then "Tomorrow"
               else .value.date end) as $label |
              "<b>\($label)</b>: \(.value.hourly[4].weatherDesc[0].value // "?")  \u2191\(.value.maxtempF // "?")° \u2193\(.value.mintempF // "?")°  \u2600\(.value.sunHour // "?")h"
            )
          ] | join("\n") as $tooltip |
          {text: "\($temp)°F", tooltip: $tooltip, class: "weather"}
        end
      ' || echo '{"text": "\u26a0", "class": "error", "tooltip": "Failed to parse weather data"}'
    '';
  };
in {
  # setup my two input channels
  nixpkgs.config = {
    permittedInsecurePackages = [
    ];
  };

  fonts.packages = with pkgs; [
    scientifica
  ];

  # audio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    extraConfig = {
      pipewire-pulse."chrome-no-audio" = {
        "pulse.rules" = [
          {
            # prevent all sources matching "Chromium" from messing with the volume
            matches = [{"application.name" = "~Chromium.*";}];
            actions = {quirks = ["block-source-volume"];};
          }
        ];
      };
    };
    wireplumber.extraConfig = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [
          "hsp_hs"
          "hsp_ag"
          "hfp_hf"
          "hfp_ag"
        ];
      };
    };
    #jack.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
    xdgOpenUsePortal = true;
    config = {
      Hyprland = {
        default = [ "hyprland" "gtk" ];
      };
    };
  };
  xdg.mime = rec {
    enable = true;
    addedAssociations = defaultApplications;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "x-scheme-handler/spotify" = "com.spotify.Client.desktop";
      "application/pdf" = "firefox.desktop";
      "application/json" = "firefox.desktop";
      "application/zip" = "ark.desktop";
      "application/vnd.appimage" = "AppImageLauncher.desktop";
      "application/x-7z-compressed" = "ark.desktop";
      "application/x-compressed-tar" = "ark.desktop";
      "application/yaml" = "firefox.desktop";
      "audio/x-mpegurl" = "mpv.desktop";
      "image/jpeg" = "gwenview.desktop";
      "image/png" = "gwenview.desktop";
      "image/svg+xml" = "gwenview.desktop";
      "image/webp" = "gwenview.desktop";
      "inode/directory" = "thunar.desktop";
      "text/css" = "firefox.desktop";
      "text/csv" = "firefox.desktop";
      "text/plain" = "firefox.desktop";
      "video/mp4" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
    };
  };

  # graphical
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    #enableNvidiaPatches = true;
  };
  security.polkit.enable = true;

  # games
  services.flatpak.enable = true;

  programs.ydotool = {
    enable = true;
  };

  # bluetooth
  services.blueman.enable = true;

  #systemd.timers."kdeconnect-refresh" = {
  #wantedBy = [ "timers.target" ];
  #timerConfig = {
  #OnBootSec = "5m";
  #OnUnitActiveSec = "5m";
  #Unit = "kdeconnect-refresh.service";
  #};
  #};

  #systemd.services."kdeconnect-refresh" = {
  #script = ''
  #${pkgs.fish}/bin/fish -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus kdeconnect-cli --refresh"
  #'';
  #serviceConfig = {
  #Type = "oneshot";
  #User = "john";
  #};
  #};

  environment.systemPackages = [ vast-waybar-status weather-status ];
}
