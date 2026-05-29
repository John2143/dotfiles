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
}: let
  vast-waybar-status = pkgs.writeShellApplication {
    name = "vast-waybar-status";
    runtimeInputs = with pkgs; [jq coreutils curl systemd];
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

            # Non-secret config from the user profile (label, local port). The
            # vastai wrapper handles its own VAST_API_KEY sourcing, so we don't
            # need to touch /run/agenix/vast-credentials here.
            LABEL=vllm-deepseek-v4
            LOCAL_PORT=8001
            PROFILE="$HOME/.config/vast/profile"
            if [ -f "$PROFILE" ]; then
                set -a
                # shellcheck disable=SC1090
                . "$PROFILE"
                set +a
                # If the profile uses fish syntax (set -gx ...) instead of bash-
                # compatible KEY=value, sourcing silently sets nothing. Detect by
                # checking whether key vars are empty despite a non-empty profile.
                if [ -z "''${VAST_LABEL:-}" ] && [ -z "''${VAST_LOCAL_PORT:-}" ] && [ -s "$PROFILE" ]; then
                  echo "vast-waybar-status: $PROFILE sourced but no KEY=VALUE vars read (fish syntax?). Using defaults." >&2
                fi
                LABEL="''${VAST_LABEL:-$LABEL}"
                LOCAL_PORT="''${VAST_LOCAL_PORT:-$LOCAL_PORT}"
            fi

            if ! raw=$(timeout 15 vastai show instances --raw 2>/dev/null); then
                : > "$CACHE"
                exit 1
            fi
            if ! credit_raw=$(timeout 15 vastai show user --raw 2>/dev/null); then
                : > "$CACHE"
                exit 1
            fi
            # Hide the widget when there are zero instances at all (any status).
            # A sleeping/stopped instance still counts — only truly empty → hidden.
            total=$(echo "$raw" | jq --arg label "$LABEL" \
                '[.[] | select(.label == $label)] | length')
            if [ "$total" = "0" ]; then
                : > "$CACHE"
                exit 0
            fi

            running=$(echo "$raw" | jq -c --arg label "$LABEL" \
                '[.[] | select(.label == $label) | select(.actual_status == "running")]')
            count=$(echo "$running" | jq 'length')
            hourly=$(echo "$running" | jq '[.[].dph_total | tonumber] | add // 0')
            credit=$(echo "$credit_raw" | jq -r '.credit // 0')

            tunnel_up=0
            systemctl --user is-active --quiet vast-tunnel.service && tunnel_up=1
            vllm_ready=0
            curl -fsS --max-time 3 "http://localhost:$LOCAL_PORT/v1/models" \
                >/dev/null 2>&1 && vllm_ready=1

            if [ "$tunnel_up" = 1 ] && [ "$vllm_ready" = 1 ]; then
                class="vast-ready"; icons="▲●"; state="tunnel UP, vLLM READY"
            elif [ "$tunnel_up" = 1 ]; then
                class="vast-tunnel-up"; icons="▲○"; state="tunnel UP, vLLM not responding"
            else
                class="vast-tunnel-down"; icons="▼○"; state="tunnel DOWN"
            fi

            hrs_str=""
            if [ "$(echo "$hourly" | jq '. > 0')" = "true" ]; then
                hrs_str=$(jq -rn --arg b "$credit" --arg h "$hourly" '
                    ($b | tonumber) as $bal | ($h | tonumber) as $hr |
                    ($bal / $hr) as $total_hours |
                    ($total_hours | floor) as $hours |
                    (($total_hours - $hours) * 60 | round) as $minutes |
                    "\($hours):\($minutes | tostring | if length == 1 then "0" + . else . end)"
                ')
            fi

            count_suffix=""
            [ "$count" -gt 1 ] && count_suffix="×$count"

            balance_fmt=$(printf '%.2f' "$credit")
            hourly_fmt=$(printf '%.2f' "$hourly")

            text="''${LABEL}''${count_suffix} $icons \$$balance_fmt"
            [ -n "$hrs_str" ] && text="$text $hrs_str"

            if [ "$count" = "0" ]; then
                per_instance="  (no running instances)"
            else
                per_instance=$(echo "$running" | jq -r '.[] |
                    "  inst \(.id): \(.gpu_name)×\(.num_gpus // 1) $\(.dph_total)/hr"')
            fi

            tooltip="Vast.ai (label: $LABEL)
      $per_instance

      State:     $state
      Balance:   \$$balance_fmt
      Rate:      \$$hourly_fmt/hr (sum)"
            [ -n "$hrs_str" ] && tooltip="$tooltip
      Remaining: ~$hrs_str"

            result=$(jq -nc --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
                '{text: $t, tooltip: $tt, class: $c}')
            printf '%s' "$result" > "$CACHE"
            echo "$result"

    '';
  };

  # Renders PNG graphs + ASCII summary from a vast-destroy metrics dir.
  # vast-destroy invokes this after scp; user can also run it manually for
  # re-rendering historical sessions in ~/vast-metrics/.
  vast-render-metrics = pkgs.writeShellApplication {
    name = "vast-render-metrics";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: with p; [pandas matplotlib numpy]))
    ];
    text = ''
      exec python3 ${../.config/vast-render-metrics.py} "$@"
    '';
  };

  weather-status = pkgs.writeShellApplication {
    name = "weather-status";
    runtimeInputs = [pkgs.curl pkgs.jq];
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
    noto-fonts
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = ["JetBrainsMono Nerd Font" "Noto Sans Mono"];
    sansSerif = ["Noto Sans"];
    serif = ["Noto Serif"];
    emoji = ["Noto Color Emoji"];
  };
  fonts.fontconfig.antialias = true;
  fonts.fontconfig.hinting = {
    enable = true;
    style = "slight";
  };
  fonts.fontconfig.subpixel = {
    rgba = "rgb";
    lcdfilter = "default";
  };

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
        default = ["hyprland" "gtk"];
      };
    };
  };
  # Ensure systemd user services (xdg-desktop-portal and backends)
  # inherit the user's environment so they can find Firefox and MIME
  # associations.  This is normally done by display managers like GDM/SDDM
  # but Lemurs does not.  Without it, flatpak apps cannot open links.
  systemd.user.extraConfig = ''
    DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin:/home/%u/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin"
    DefaultEnvironment="XDG_DATA_DIRS=/home/%u/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/run/current-system/sw/share"
    DefaultEnvironment="XDG_CONFIG_DIRS=/home/%u/.local/share/flatpak/exports/etc/xdg:/var/lib/flatpak/exports/etc/xdg:/run/current-system/sw/etc/xdg"
    DefaultEnvironment="XDG_RUNTIME_DIR=/run/user/%U"
  '';
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
  # Bubblewrap setuid wrapper — flatpak needs this to create sandboxes.
  # The flatpak module doesn't auto-configure this in nixpkgs 25.11+.
  security.wrappers.bubblewrap = {
    source = "${pkgs.bubblewrap}/bin/bwrap";
    capabilities = "cap_sys_admin+ep";
    owner = "root";
    group = "root";
  };

  programs.ydotool = {
    enable = true;
  };

  # bluetooth
  services.blueman.enable = true;
  # Fix blueman-applet user service: the NixOS module generated an override
  # that adds a second ExecStart= line on top of the package's Type=dbus
  # service, which systemd refuses to load.
  systemd.user.services.blueman-applet.serviceConfig.ExecStart = lib.mkForce "${pkgs.blueman}/bin/blueman-applet";

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
  # FIXME(2026-05-23): Waybar Lua dispatch patch — backports upstream PR #5013
  # to fix workspace button clicks on Hyprland >= 0.55. Remove this overlay
  # (and nixos/modules/waybar-lua-dispatch.patch) once nixpkgs ships a Waybar
  # release > v0.15.0 that includes the upstream fix.
  # Track: https://github.com/Alexays/Waybar/pull/5013
  # Check: https://github.com/Alexays/Waybar/releases

  nixpkgs.overlays = [
    (final: prev: {
      autoclicker = inputs.autoclicker.packages.${prev.system}.default;
    })
    (final: prev: {
      waybar = prev.waybar.overrideAttrs (old: {
        patches =
          (old.patches or [])
          ++ [
            ./modules/waybar-lua-dispatch.patch
          ];
      });
    })
  ];

  # crates.io blocks cargo's default User-Agent (returns 403 from this IP).
  # Mount a system-wide cargo config into the Nix sandbox so buildRustPackage's
  # cargo vendor can download crate tarballs with a browser User-Agent.
  environment.etc."cargo/config.toml".text = ''
    [http]
    user-agent = "Mozilla/5.0 (X11; Linux x86_64; rv:137.0) Gecko/20100101 Firefox/137.0"
  '';
  nix.extraOptions = ''
    extra-sandbox-paths = /etc/cargo/config.toml
  '';
  environment.systemPackages = [pkgs.autoclicker vast-waybar-status vast-render-metrics weather-status];
}
