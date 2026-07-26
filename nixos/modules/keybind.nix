{ config, pkgs, lib, ... }:
let
  hass-lib = ''
    TOKEN=$(cat /run/agenix/hass-credentials)
    HA="https://home.ts.2143.me"
    AUTH="Authorization: Bearer $TOKEN"

    hass_get() {
      curl -sf -H "$AUTH" "$HA/api/states/$1"
    }

    hass_post() {
      curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
        -d "$2" "$HA/api/services/$1" > /dev/null
    }

    hass_notify() {
      notify-send -h "string:x-dunst-stack-tag:hass-$1" "$2" "$3" || true
    }

    signal_waybar() {
      pkill -RTMIN+8 waybar || true
    }
  '';

  hass-macro = pkgs.writeShellApplication {
    name = "hass-macro";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.bc pkgs.libnotify pkgs.procps ];
    text = ''
      ${hass-lib}

      case "''${1:-}" in
        thermostat-down|thermostat-up)
          current=$(hass_get climate.john_bedroom \
            | jq -r '.attributes.temperature')
          if [ "$1" = "thermostat-down" ]; then
            new=$(echo "$current - 1" | bc)
          else
            new=$(echo "$current + 1" | bc)
          fi
          hass_post climate/set_temperature \
            "{\"entity_id\":\"climate.john_bedroom\",\"temperature\":$new}"
          signal_waybar
          hass_notify thermostat "Thermostat" "Set to ''${new}°"
          ;;
        thermostat-toggle)
          state=$(hass_get climate.john_bedroom \
            | jq -r '.state')
          if [ "$state" = "off" ]; then
            hass_post climate/turn_on '{"entity_id":"climate.john_bedroom"}'
            signal_waybar
            hass_notify thermostat "Thermostat" "Turned on"
          else
            hass_post climate/turn_off '{"entity_id":"climate.john_bedroom"}'
            signal_waybar
            hass_notify thermostat "Thermostat" "Turned off"
          fi

          ;;
        ac-toggle)
          hass_post fan/toggle '{"entity_id":"fan.john_ac_combo_fans"}'
          signal_waybar
          hass_notify ac "AC" "Toggled"
          ;;
        fan-toggle)
          hass_post fan/toggle '{"entity_id":"fan.plug_upstairs_desktop_computer_switch"}'
          signal_waybar
          hass_notify fan "Fan" "Toggled"
          ;;
        light-lamp)
          hass_post light/toggle '{"entity_id":"light.john_bedroom_lamp"}'
          signal_waybar
          hass_notify lamp "Lamp" "Toggled"
          ;;

        light-dresser)
          hass_post light/toggle '{"entity_id":"light.plug_bedroom_superbright"}'
          signal_waybar
          hass_notify dresser "Dresser Light" "Toggled"
          ;;
        light-ac)
          hass_post light/toggle '{"entity_id":"light.plug_bedroom_ac_and_fan_switch"}'
          signal_waybar
          hass_notify ac-light "AC Light" "Toggled"
          ;;

        light-bedroom)
          hass_post light/toggle '{"entity_id":"light.john_bedroom_light"}'
          signal_waybar
          hass_notify bedroom-light "Bedroom Light" "Toggled"
          ;;
        dyson-fan)
          hass_post fan/toggle '{"entity_id":"fan.k3b_us_pga0539a"}'
          signal_waybar
          hass_notify dyson-fan "Dyson Fan" "Toggled"
          ;;
        desk-light)
          hass_post light/toggle '{"entity_id":"light.wiz_color_strip"}'
          signal_waybar
          hass_notify desk-light "Desk Light" "Toggled"
          ;;
        *)
          echo "Usage: hass-macro {thermostat-down|thermostat-up|thermostat-toggle|ac-toggle|fan-toggle|light-lamp|light-dresser|light-ac|light-bedroom|dyson-fan|desk-light}" >&2
          exit 1
          ;;
      esac
        #
        # ── Adding a new hass-macro command? ─────────────────────────────
        # 1. Add the case entry here (command name → hass_post/service/call).
        # 2. Add a keyd mapping in services.keyd below (physical key → F-key).
        # 3. Add the Hyprland bind below (F-key → hass-macro <name>).
        #    Pattern: name) hass_post <domain>/toggle '{"entity_id":"<domain>.<entity>"}';;
        #    Always include signal_waybar and hass_notify.
        # ─────────────────────────────────────────────────────────────────
    '';
  };

  hass-thermostat-status = pkgs.writeShellApplication {
    name = "hass-thermostat-status";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      ${hass-lib}

      response=$(hass_get climate.john_bedroom) || {
        echo '{"text": "⚠", "class": "error", "tooltip": "Failed to fetch thermostat"}'
        exit 0
      }

      state=$(echo "$response" | jq -r '.state')
      current=$(echo "$response" | jq -r '.attributes.current_temperature // empty')
      target=$(echo "$response" | jq -r '.attributes.temperature // empty')
      action=$(echo "$response" | jq -r '.attributes.hvac_action // "idle"')

      if [ -z "$current" ]; then
        echo '{"text": "⚠", "class": "error", "tooltip": "Missing temperature data"}'
        exit 0
      fi

      current_int=$(printf "%.0f" "$current")

      if [ "$state" = "off" ]; then
        class="off"
        text="''${current_int}° (off)"
        tooltip="Room: ''${current}° | Off (not regulating)"
      else
        if [ -z "$target" ]; then
          echo '{"text": "⚠", "class": "error", "tooltip": "Missing target temperature"}'
          exit 0
        fi
        target_int=$(printf "%.0f" "$target")
        class="$action"
        text="''${current_int}° → ''${target_int}°"
        tooltip="Room: ''${current}° | Target: ''${target}° | ''${action}"
      fi

      jq -nc --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
        '{text: $t, tooltip: $tt, class: $c}'
    '';
  };

  mkLua = lib.generators.mkLuaInline;
in {
  services.keyd = {
    enable = true;
    keyboards.macropad = {
      ids = ["20a0:422d"];
      settings.main = {
        #  ┌───┬───┬───┬───┬───┬───┐
        #  │esc│ 1 │ 2 │ 3 │ 4 │ 5 │
        #  ├───┼───┼───┼───┼───┼───┤
        #  │tab│ q │ w │ e │ r │ y │
        #  ├───┼───┼───┼───┼───┼───┤
        #  │ v │ a │ s │ d │ f │ g │
        #  ├───┼───┼───┼───┼───┼───┤
        #  │ z │ x │ c │ b │ent│   │
        #  └───┴───┴───┴───┴───┴───┘

        # F18-F20 only: 3 keys × {-,C,A,M,CA,CM,AM,CAM} = 8 combos each.
        # Shift deliberately unused — reserved as a future layer modifier.
        # Requires `fkeys:basic_13-24` in hyprland kb_options.
        q   = "f20";      # monitors on
        w   = "C-f20";    # monitors off
        e   = "C-f18";    # light: dresser (light-dresser)
        r   = "A-f18";    # light: window AC (light-ac)
        y   = "f18";      # light: lamp (light-lamp)
        a   = "C-f19";    # thermostat −1° (thermostat-down)
        s   = "M-f19";    # AC toggle (ac-toggle)
        d   = "A-f19";    # thermostat +1° (thermostat-up)
        f   = "f19";      # thermostat toggle (thermostat-toggle)
        g   = "C-A-f19";  # fan toggle (fan-toggle)
        "5" = "M-f18";    # light: bedroom overhead (light-bedroom)
        "3" = "f21";      # Dyson fan toggle (dyson-fan)
        "4" = "C-f21";    # desk light toggle (desk-light)
        #
        # ── Adding a new macropad bind? ──────────────────────────────────
        # 1. Add the keyd mapping here (physical key → F-key + modifier).
        # 2. If it controls Home Assistant, add a `hass-macro` case above.
        # 3. Add the Hyprland bind below (same F-key + modifier as in keyd).
        #    Modifier prefixes: C=Ctrl, A=Alt, M=Super, CA=Ctrl+Alt.
        #    F18-F21 are available; beyond F24 use XF86Launch*.
        # ─────────────────────────────────────────────────────────────────
    };
  };
  };

  environment.systemPackages = [
    hass-macro
    hass-thermostat-status
  ];

  home-manager.users.john.wayland.windowManager.hyprland.settings.bind = [
    # Macro pad F18 group — lights
    { _args = ["F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-lamp")'')]; }
    { _args = ["CTRL + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-dresser")'')]; }
    { _args = ["ALT + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-ac")'')]; }
    { _args = ["SUPER + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-bedroom")'')]; }

    # Macro pad F19 group — climate
    { _args = ["F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-toggle")'')]; }
    { _args = ["CTRL + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-down")'')]; }
    { _args = ["ALT + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-up")'')]; }
    { _args = ["SUPER + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro ac-toggle")'')]; }
    { _args = ["CTRL + ALT + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro fan-toggle")'')]; }

    # Macro pad F20 group — display
    { _args = ["F20" (mkLua ''hl.dsp.dpms({ action = "enable" })'')]; }
    { _args = ["CTRL + F20" (mkLua ''hl.dsp.dpms({ action = "disable" })'')]; }

    # Macro pad F21 group — Home Assistant toggles
    { _args = ["F21" (mkLua ''hl.dsp.exec_cmd("hass-macro dyson-fan")'')]; }
    { _args = ["CTRL + F21" (mkLua ''hl.dsp.exec_cmd("hass-macro desk-light")'')]; }
    #
    # ── Adding a new macropad bind? ──────────────────────────────────
    # 1. Add the keyd mapping above (physical key → F-key + modifier).
    # 2. If it controls Home Assistant, add a `hass-macro` case above too.
    # 3. Add the Hyprland bind here (same F-key + modifier as in keyd).
    #    F-key syntax: "F18" / "CTRL + F18" / "ALT + F18" / "SUPER + F18"
    #    Command syntax: hl.dsp.exec_cmd("hass-macro <name>")
    # ─────────────────────────────────────────────────────────────────
  ];
}
