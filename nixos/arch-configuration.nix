# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  pkgs,
  pkgs-stable,
  inputs,
  lib,
  ...
}:
let
  hass-macro = pkgs.writeShellApplication {
    name = "hass-macro";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.bc pkgs.libnotify pkgs.procps ];
    text = ''
      TOKEN=$(cat /run/agenix/hass-credentials)
      HA="https://home.ts.2143.me"
      AUTH="Authorization: Bearer $TOKEN"

      case "''${1:-}" in
        thermostat-down|thermostat-up)
          current=$(curl -sf -H "$AUTH" "$HA/api/states/climate.john_bedroom" \
            | jq -r '.attributes.temperature')
          if [ "$1" = "thermostat-down" ]; then
            new=$(echo "$current - 1" | bc)
          else
            new=$(echo "$current + 1" | bc)
          fi
          curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
            -d "{\"entity_id\":\"climate.john_bedroom\",\"temperature\":$new}" \
            "$HA/api/services/climate/set_temperature" > /dev/null
          notify-send -h string:x-dunst-stack-tag:hass-thermostat "Thermostat" "Set to ''${new}°"
          pkill -RTMIN+8 waybar || true
          ;;
        thermostat-toggle)
          state=$(curl -sf -H "$AUTH" "$HA/api/states/climate.john_bedroom" \
            | jq -r '.state')
          if [ "$state" = "off" ]; then
            curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
              -d '{"entity_id":"climate.john_bedroom"}' \
              "$HA/api/services/climate/turn_on" > /dev/null
            notify-send -h string:x-dunst-stack-tag:hass-thermostat "Thermostat" "Turned on"
          else
            curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
              -d '{"entity_id":"climate.john_bedroom"}' \
              "$HA/api/services/climate/turn_off" > /dev/null
            notify-send -h string:x-dunst-stack-tag:hass-thermostat "Thermostat" "Turned off"
          fi
          pkill -RTMIN+8 waybar || true
          ;;
        fan-toggle)
          curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
            -d '{"entity_id":"fan.john_ac_combo_fans"}' \
            "$HA/api/services/fan/toggle" > /dev/null
          notify-send -h string:x-dunst-stack-tag:hass-fan "Fan" "Toggled"
          ;;
        *)
          echo "Usage: hass-macro {thermostat-down|thermostat-up|thermostat-toggle|fan-toggle}" >&2
          exit 1
          ;;
      esac
    '';
  };
  hass-thermostat-status = pkgs.writeShellApplication {
    name = "hass-thermostat-status";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      TOKEN=$(cat /run/agenix/hass-credentials)
      HA="https://home.ts.2143.me"
      AUTH="Authorization: Bearer $TOKEN"

      response=$(curl -sf -H "$AUTH" "$HA/api/states/climate.john_bedroom") || {
        echo '{"text": "⚠", "class": "error", "tooltip": "Failed to fetch thermostat"}'
        exit 0
      }

      current=$(echo "$response" | jq -r '.attributes.current_temperature // empty')
      target=$(echo "$response" | jq -r '.attributes.temperature // empty')
      action=$(echo "$response" | jq -r '.attributes.hvac_action // "idle"')

      if [ -z "$current" ] || [ -z "$target" ]; then
        echo '{"text": "⚠", "class": "error", "tooltip": "Missing temperature data"}'
        exit 0
      fi

      current_int=$(printf "%.0f" "$current")
      target_int=$(printf "%.0f" "$target")
      text="''${current_int}° → ''${target_int}°"

      tooltip="Room: ''${current}° | Target: ''${target}° | ''${action}"

      jq -nc --arg t "$text" --arg tt "$tooltip" --arg c "$action" \
        '{text: $t, tooltip: $tt, class: $c}'
    '';
  };
in
{
  imports = [
    ./arch-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/ollama.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;

  #nix.settings.trusted-users = [ "@wheel" ];
  #nix.settings.trusted-public-keys = [
  #"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
  #];

  #services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.supportedFilesystems = ["ntfs"];
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  services.displayManager.lemurs = {
    enable = true;
  };
  services.seatd.enable = true;

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSOverTLS = "true";
        DNSSEC = "true";
        Domains = [
          "~."
        ];
        FallbackDNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
    };
  };

  networking.hostName = "arch"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.nameservers = [
    "1.1.1.1"
    "192.168.1.12"
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Second keyboard (winkeyless ps2avrGB) remapped to F13-F24.
  # Hyprland binds in hyprland.conf map these to actual commands.
  services.keyd = {
    enable = true;
    keyboards.macropad = {
      ids = ["20a0:422d"];
      settings.main = {
        esc = "f13";
        q = "f14";
        w = "f15";
        e = "f16";
        r = "f17";
        t = "f18";
        a = "f19";
        s = "f20";
        d = "f21";
        f = "f22";
      };
    };
  };

  environment.systemPackages = [ hass-macro hass-thermostat-status ];

  age.secrets.hass-credentials = {
    file = ../secrets/hass-credentials.age;
    owner = "john";
    group = "root";
    mode = "0400";
  };

  custom.k3sNodeTaints = ["seated=true:NoSchedule"];
  custom.backup.enable = true;

  systemd.services.screen-control = {
    description = "REST screen control server";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${inputs.screen-control.defaultPackage.x86_64-linux}/bin/screen-control";
      Restart = "always";
      RestartSec = 5;
      User = "john";
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/1000"
      ];
    };
    path = [pkgs.hyprland];
  };

  networking.firewall.allowedTCPPorts = [50051];

  # NAS CIFS mounts live in ./modules/nas-mounts.nix (shared across workstations).

  services.ollama = {
    package = pkgs.ollama-cuda;
  };

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11";
}
