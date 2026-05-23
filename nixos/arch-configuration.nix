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
  teamspeak-mute-proxy = pkgs.writers.writePython3Bin "teamspeak-mute-proxy"
    { libraries = []; }
    ''
    """TeamSpeak 3 ClientQuery proxy daemon.

    Maintains one persistent connection, serves many clients.
    """

    import os
    import sys
    import socket
    import json
    import time
    import signal
    import select
    import re
    import struct

    SOCK_PATH = os.path.join(
        os.environ.get(
            "XDG_RUNTIME_DIR", os.path.expanduser("~/.cache")
        ),
        "ts3query-proxy.sock",
    )
    TS3_HOST = "127.0.0.1"
    TS3_PORT = 25639
    _INI_BASE = (
        "$HOME/.var/app/com.teamspeak.TeamSpeak3"
        "/.ts3client/clientquery.ini"
    )
    INIFILE_CANDIDATES = [
        os.path.expandvars(_INI_BASE),
        os.path.expandvars("$HOME/.ts3client/clientquery.ini"),
        "/home/john/.var/app/com.teamspeak.TeamSpeak3"
        "/.ts3client/clientquery.ini",
    ]

    DISCONNECTED_JSON = json.dumps({
        "text": "\uf130  \u2b1c",
        "class": "disconnected", "alt": "disconnected",
        "tooltip": "TeamSpeak not connected to a server",
    })
    MUTED_JSON = json.dumps({
        "text": "\uf130  \U0001f534",
        "class": "muted", "alt": "muted",
        "tooltip": "Mic Muted (click to unmute)",
    })
    UNMUTED_JSON = json.dumps({
        "text": "\uf130  \U0001f7e2",
        "class": "unmuted", "alt": "unmuted",
        "tooltip": "Mic Active (click to mute)",
    })


    def read_apikey():
        for path in INIFILE_CANDIDATES:
            try:
                with open(path) as f:
                    for line in f:
                        if line.startswith("api_key="):
                            return line.split("=", 1)[1].strip()
            except (OSError, IOError):
                continue
        return None


    def ts3_connect():
        """Connect to TS3 ClientQuery, auth, return (sock, clid)."""
        apikey = read_apikey()
        if not apikey:
            print("No API key found", file=sys.stderr, flush=True)
            return None, None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.setsockopt(
                socket.SOL_SOCKET, socket.SO_LINGER,
                struct.pack('ii', 1, 0),
            )
            sock.connect((TS3_HOST, TS3_PORT))
            # Read banner
            data = b""
            sock.settimeout(2)
            while True:
                try:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if b"\n\r" in data:
                        break
                except socket.timeout:
                    break
            # Auth
            sock.sendall(f"auth apikey={apikey}\n".encode())
            time.sleep(0.1)
            auth_resp = b""
            try:
                while True:
                    sock.settimeout(1)
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    auth_resp += chunk
                    if b"error id=" in auth_resp:
                        break
            except socket.timeout:
                pass
            if b"error id=0" not in auth_resp:
                msg = auth_resp.decode(errors="replace").strip()
                print(
                    f"Auth failed: {msg}",
                    file=sys.stderr, flush=True,
                )
                sock.close()
                return None, None
            # Get clid
            sock.sendall(b"whoami\n")
            time.sleep(0.1)
            whoami = b""
            try:
                while True:
                    sock.settimeout(1)
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    whoami += chunk
                    if b"error id=" in whoami:
                        break
            except socket.timeout:
                pass
            for line in whoami.decode(errors="replace").split("\n"):
                if line.startswith("clid="):
                    clid = line.split("=")[1].split()[0]
                    sock.settimeout(5)
                    print(
                        f"Connected to TS3 ClientQuery,"
                        f" clid={clid}",
                        file=sys.stderr, flush=True,
                    )
                    return sock, clid
            sock.close()
            return None, None
        except Exception as e:
            print(
                f"TS3 connection failed: {e}",
                file=sys.stderr, flush=True,
            )
            return None, None


    def ts3_cmd(sock, cmd):
        """Send a command, return response text."""
        try:
            sock.sendall(f"{cmd}\n".encode())
            resp = b""
            sock.settimeout(2)
            while True:
                try:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    resp += chunk
                    if b"error id=" in resp:
                        break
                except socket.timeout:
                    break
            return resp.decode(errors="replace")
        except Exception:
            return "error id=1 msg=connection_lost"


    def handle_request(sock, clid, cmd):
        """Handle a client command, return (response, connection_ok)."""
        if cmd == "status":
            if clid is None:
                return DISCONNECTED_JSON, True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_input_muted",
            )
            if "connection_lost" in resp:
                return DISCONNECTED_JSON, False
            m = re.search(r"client_input_muted=(\d+)", resp)
            muted = m.group(1) if m else "0"
            if muted == "1":
                return MUTED_JSON, True
            return UNMUTED_JSON, True
        elif cmd == "toggle":
            if clid is None:
                return "", True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_input_muted",
            )
            if "connection_lost" in resp:
                return "", False
            m = re.search(r"client_input_muted=(\d+)", resp)
            cur = m.group(1) if m else "0"
            new = "0" if cur == "1" else "1"
            ts3_cmd(sock, f"clientupdate client_input_muted={new}")
            return "", True
        elif cmd == "toggle-output":
            if clid is None:
                return "", True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_output_muted",
            )
            if "connection_lost" in resp:
                return "", False
            m = re.search(r"client_output_muted=(\d+)", resp)
            cur = m.group(1) if m else "0"
            new = "0" if cur == "1" else "1"
            ts3_cmd(sock, f"clientupdate client_output_muted={new}")
            return "", True
        else:
            return "", True


    def main():
        if os.path.exists(SOCK_PATH):
            try:
                os.unlink(SOCK_PATH)
            except OSError:
                pass

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCK_PATH)
        server.listen(5)
        os.chmod(SOCK_PATH, 0o600)
        server.setblocking(False)

        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

        print(
            f"Proxy listening on {SOCK_PATH}",
            file=sys.stderr, flush=True,
        )

        ts3_sock = None
        clid = None
        last_attempt = 0.0

        while True:
            now = time.time()
            if ts3_sock is None and now - last_attempt >= 5:
                last_attempt = now
                ts3_sock, clid = ts3_connect()

            try:
                readable, _, _ = select.select(
                    [server], [], [], 1.0,
                )
            except (select.error, ValueError, InterruptedError):
                continue

            if server in readable:
                try:
                    client, _ = server.accept()
                    raw = client.recv(1024)
                    data = raw.decode(errors="replace").strip()
                    if data:
                        result, ok = handle_request(
                            ts3_sock, clid, data,
                        )
                        if not ok:
                            try:
                                ts3_sock.close()
                            except Exception:
                                pass
                            ts3_sock = None
                            clid = None
                        if result:
                            client.sendall(result.encode())
                    client.close()
                except Exception as e:
                    print(
                        f"Client error: {e}",
                        file=sys.stderr, flush=True,
                    )

            # Health-check TS3 connection via MSG_PEEK
            if ts3_sock is not None:
                try:
                    ts3_sock.setblocking(False)
                    try:
                        ts3_sock.recv(1, socket.MSG_PEEK)
                    except BlockingIOError:
                        pass
                except (
                    ConnectionResetError,
                    BrokenPipeError,
                    OSError,
                ) as e:
                    print(
                        f"TS3 connection lost: {e}",
                        file=sys.stderr, flush=True,
                    )
                    try:
                        ts3_sock.close()
                    except Exception:
                        pass
                    ts3_sock = None
                    clid = None
                finally:
                    ts3_sock and ts3_sock.setblocking(True)
                    ts3_sock and ts3_sock.settimeout(5)


    if __name__ == "__main__":
        main()
    '';

  teamspeak-mute-status = pkgs.writeShellApplication {
    name = "teamspeak-mute-status";
    runtimeInputs = [ pkgs.libressl.nc ];
    text = ''
      SOCK="$XDG_RUNTIME_DIR/ts3query-proxy.sock"
      if [ "''${1:-}" = "--toggle" ]; then
        printf '%s\n' "toggle" | nc -UN -w 2 "$SOCK" > /dev/null 2>&1 || true
      elif [ "''${1:-}" = "--toggle-output" ]; then
        printf '%s\n' "toggle-output" | nc -UN -w 2 "$SOCK" > /dev/null 2>&1 || true
      else
        RESULT=$(printf '%s\n' "status" | nc -UN -w 2 "$SOCK" 2>/dev/null)
        if [ -n "$RESULT" ]; then
          printf '%s\n' "$RESULT"
        else
          echo '{"text": "  ⬜", "class": "disconnected", "alt": "disconnected", "tooltip": "TeamSpeak not connected to a server"}'
        fi
      fi
    '';
  };
in
{
  imports = [
    ./arch-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/ollama.nix
    ./modules/vllm.nix
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
    teamspeak-mute-status
    teamspeak-mute-proxy
    inputs.hyprcap.packages.x86_64-linux.default
  ];

  # openrgb flakes occasionally — keep the unit out of "failed" state so it
  # doesn't trip exit-code-4 in switch-to-configuration's post-activation scan.
  systemd.services.openrgb.enable = lib.mkForce false;
  systemd.user.services.teamspeak-mute-proxy = {
    description = "TeamSpeak 3 ClientQuery proxy daemon";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    requisite = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${teamspeak-mute-proxy}/bin/teamspeak-mute-proxy";
      Restart = "on-failure";
      RestartSec = 5;
    };
    wantedBy = [ "graphical-session.target" ];
  };


  custom.k3sNodeTaints = ["seated=true:NoSchedule"];
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

  networking.firewall.allowedTCPPorts = [50051];

  # NAS CIFS mounts live in ./modules/nas-mounts.nix (shared across workstations).

  services.ollama = {
    package = pkgs.ollama-cuda;
    # Disk-constrained host: only gemma4 is auto-pulled. Don't run ollama-sync
    # here — it would mirror every model from the NAS and fill the SSD.
    modelNames = ["gemma4"];
  };

  # vLLM disabled: GPU VRAM too small for the models we'd want to serve here.

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
