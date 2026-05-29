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
        *)
          echo "Usage: hass-macro {thermostat-down|thermostat-up|thermostat-toggle|ac-toggle|fan-toggle|light-lamp|light-dresser|light-ac|light-bedroom}" >&2
          exit 1
          ;;
      esac
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
in
{
  imports = [
    ./arch-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/vllm.nix
    ./modules/teamspeak.nix
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
  # F23 and F24 are the last standard Linux function keycodes (KEY_F23, KEY_F24).
  # Any additional keys beyond F24 should use XF86Launch* (Launch8, Launch9, etc.)
  # to continue the pattern from the existing XF86Launch5/6/7 mappings.
  # Hyprland binds in hyprland.conf map these to actual commands.
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
    };
  };
  }; # close services.keyd

  environment.systemPackages = [
    hass-macro
    hass-thermostat-status
    inputs.hyprcap.packages.x86_64-linux.default
    # voxtype disabled: crates.io blocks this IP's User-Agent
    # Re-enable with: CARGO_HTTP_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:137.0) Gecko/20100101 Firefox/137.0" nos
    # inputs.voxtype.packages.x86_64-linux.default
    # inputs.voxtype.packages.x86_64-linux.vulkan
  ];

  # openrgb flakes occasionally — keep the unit out of "failed" state so it
  # doesn't trip exit-code-4 in switch-to-configuration's post-activation scan.
  systemd.services.openrgb.enable = lib.mkForce false;


  custom.k3sNodeTaints = ["seated=true:NoSchedule"];

  # k3s server — join existing cluster via mDNS (bootstrap without tailscale dependency).
  # Dual-stack cluster CIDRs mirror closet's init node config.
  services.k3s.extraFlags = lib.concatStringsSep " " [
    "--server=https://192.168.5.35:6443"
    "--tls-san=arch.local"
    "--tls-san=closet.local"
    "--tls-san=192.168.5.226"
    "--cluster-cidr=10.42.0.0/16,fd42:42:42::/56"
    "--service-cidr=10.43.0.0/16,fd42:42:43::/112"
    "--node-ip=192.168.5.226"
    "--flannel-ipv6-masq"
    "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=24"
    "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
  ];
  custom.backup.enable = true;

  systemd.services.screen-control = {
    description = "REST screen control server";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.nix}/bin/nix run /home/john/dotfiles/screen-control";
      Restart = "always";
      RestartSec = 5;
      User = "john";
      Group = "users";
    };
    path = [pkgs.hyprland];
  };

  networking.firewall.allowedTCPPorts = [
    50051 # screen-control REST API (arch-configuration.nix:290, screen-control/src/main.rs:129)
    10250 # kubelet (k3s agent)
    18080 # monero p2p (monerod)
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # Kubernetes NodePort range
  ];

  # NAS CIFS mounts live in ./modules/nas-mounts.nix (shared across workstations).


  # ollama disabled: CUDA build broken upstream (GCC ICE in ggml-cuda),
  # and arch GPU has <8GB VRAM — only gemma4 fits, never used in practice.
  # services.ollama = {
  #   package = pkgs.ollama-cuda;
  #   # Disk-constrained host: only gemma4 is auto-pulled. Don't run ollama-sync
  #   # here — it would mirror every model from the NAS and fill the SSD.
  #   modelNames = ["gemma4"];
  # };
  # vLLM disabled: GPU VRAM too small for the models we'd want to serve here.

  # Firewall enabled via shared-cli-configuration.nix.

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
