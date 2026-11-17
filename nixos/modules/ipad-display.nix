# iPad as a second display, and as a wired peer.
#
# Two independent halves, both applied whenever this module is imported:
#
#   * Sunshine + a Hyprland headless output named MOONLIGHT. The output only
#     exists while a stream does: `prep` (Sunshine's global prep hook) creates
#     and places it at the client's mode, `ipad-display-watch` removes it 20 s
#     after the last stream ends and restarts Sunshine, because a reconnect
#     skips the prep hook and would otherwise capture a clone of the laptop
#     panel (Sunshine's placebo desktop app reports itself as running forever).
#   * The USB-C transport: usbmuxd switched into CDC-NCM mode exposes an NCM
#     data interface, and a NetworkManager dispatcher gives that link a
#     `shared` profile so the host is the iPad's DHCP server and gateway on
#     10.42.0.1/24. Same address in, cable or Wi-Fi.
#
# Only hosts with a Hyprland session may import this (arch, office). The helper
# itself lives in packages/ipad-display.nix because the waybar widget needs it
# too, from a home-manager module.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Same expression the waybar module builds; content-addressed, so both modules
  # get one store path without an overlay (secu and security evaluate home.nix
  # without shared-configuration.nix, where the overlay would live).
  ipadDisplay = pkgs.callPackage ../packages/ipad-display.nix { };

  # NetworkManager dispatcher entry for the iPad's data interface. Filtering
  # here keeps transient units off every unrelated network event.
  ipad-usb-event = pkgs.writeShellApplication {
    name = "ipad-usb-event";
    runtimeInputs = with pkgs; [systemd coreutils];
    text = ''
      [ "''${2:-}" = up ] || exit 0
      ifname=$1
      dev=$(readlink -f "/sys/class/net/$ifname/device" 2>/dev/null) || exit 0
      [ -n "$dev" ] || exit 0
      [ "$(cat "$dev/../idVendor" 2>/dev/null)" = 05ac ] || exit 0
      [ "$(basename "$(readlink -f "$dev/driver" 2>/dev/null)")" = cdc_ncm ] || exit 0
      # A fixed --unit would still be registered on the second plug and make
      # systemd-run refuse, leaving the link unconfigured; --collect lets the
      # transient unit evaporate instead.
      systemd-run --collect --quiet -- "${ipad-usb-attach}/bin/ipad-usb-attach" "$ifname"
    '';
  };

  # Bringing the profile up from inside a dispatcher for the very device being
  # dispatched can deadlock NetworkManager, hence the systemd-run hop in the
  # caller.
  ipad-usb-attach = pkgs.writeShellApplication {
    name = "ipad-usb-attach";
    runtimeInputs = with pkgs; [networkmanager coreutils];
    text = ''
      ifc="''${1:-}"
      # A dispatcher can hand us an interface that has already gone away, or
      # nothing at all.
      if [ -z "$ifc" ] || [ ! -d "/sys/class/net/$ifc" ]; then
        echo "ipad-usb-attach: no such interface: ''${ifc:-<none>}" >&2
        exit 0
      fi
      if ! nmcli connection show ipad-usb >/dev/null 2>&1; then
        echo "ipad-usb: profile missing (NetworkManager-ensure-profiles failed?)" >&2
        exit 1
      fi

      # CDC-NCM consumes a control+data interface pair, so the data netdev's own
      # interface number is not 0 and cannot be used to tell the functions
      # apart. Of the Apple CDC-NCM netdevs the lowest ifindex is the data
      # function; the other is Apple's private multiplexor, which must stay out
      # of NetworkManager entirely.
      data=$(for n in /sys/class/net/*; do
        d=$(readlink -f "$n/device" 2>/dev/null) || continue
        [ "$(cat "$d/../idVendor" 2>/dev/null)" = 05ac ] || continue
        [ "$(basename "$(readlink -f "$d/driver" 2>/dev/null)")" = cdc_ncm ] || continue
        printf '%s %s\n' "$(cat "$n/ifindex")" "$(basename "$n")"
      done | sort -n | head -n1 | cut -d' ' -f2)

      if [ "$ifc" != "$data" ]; then
        nmcli device set "$ifc" managed no
        exit 0
      fi

      nmcli device set "$ifc" managed yes
      nmcli connection up ipad-usb ifname "$ifc"
    '';
  };
in {
  environment.systemPackages = [ipadDisplay];

  services.sunshine = {
    enable = true;
    openFirewall = true;
    settings = {
      # KMS cannot see a headless output; wlr screencopy can, and selects it by
      # the name prep gives it.
      capture = "wlr";
      output_name = "MOONLIGHT";
      # Second screen on the same desk: keep the audio where the speakers are.
      stream_audio = "disabled";
      # `undo` must be an absolute path: the unit runs with PATH unset (the
      # nixpkgs module forces `environment.PATH = null`), so a bare `true`
      # would not resolve.
      global_prep_cmd = ''
        [{"do":"${ipadDisplay}/bin/ipad-display prep","undo":"${pkgs.coreutils}/bin/true"}]
      '';
    };
  };

  systemd.user.services.ipad-display-watch = {
    description = "Remove the MOONLIGHT virtual output when no Sunshine stream is running";
    after = ["graphical-session.target" "sunshine.service"];
    partOf = ["graphical-session.target"];
    wantedBy = ["graphical-session.target"];
    serviceConfig = {
      ExecStart = "${ipadDisplay}/bin/ipad-display watch";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # ---- USB-C transport ----
  services.usbmuxd.enable = true;
  # nixpkgs' usbmuxd (1.1.1+date=2025-12-06) carries the mode-switch support that
  # only exists post-2022 upstream: 3 = CDC-NCM + Apple USB Multiplexor, which is
  # what makes a data interface appear at all. ExecStart is fixed by the module,
  # so the environment is the only supported knob (src/usb.h declares the name).
  systemd.services.usbmuxd.environment.USBMUXD_DEFAULT_DEVICE_MODE = "3";

  # DHCP server for the iPad on the cable.
  networking.firewall.allowedUDPPorts = [67];

  # Declared rather than created with `nmcli connection add`: no interface name
  # is set (the netdev name is dynamic), the dispatcher binds it at `up` time,
  # and the profile is regenerated on every activation instead of drifting in
  # /etc.
  networking.networkmanager.ensureProfiles.profiles.ipad-usb = {
    connection = {
      id = "ipad-usb";
      type = "ethernet";
      autoconnect = "false";
    };
    ipv4.method = "shared";
    ipv6.method = "ignore";
  };

  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = ipad-usb-event;
    }
  ];
}
