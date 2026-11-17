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
#     data interface, and a udev rule gives that link a `shared` profile, so the
#     host is the iPad's DHCP server and gateway on 10.42.0.1/24. Same address
#     in, cable or Wi-Fi.
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

  # Run from a transient unit by the udev rule below, not directly by the rule:
  # udev blocks until its RUN commands return, and nmcli can take seconds.
  #
  # The interface is discovered here rather than passed in: udev reports the
  # pre-rename kernel name (usb0), and the predictable name differs per port.
  ipad-usb-attach = pkgs.writeShellApplication {
    name = "ipad-usb-attach";
    runtimeInputs = with pkgs; [networkmanager coreutils];
    text = ''
      if ! nmcli connection show ipad-usb >/dev/null 2>&1; then
        echo "ipad-usb: profile missing (NetworkManager-ensure-profiles failed?)" >&2
        exit 1
      fi

      # CDC-NCM exposes a control+data interface pair, so the data netdev's own
      # interface number is not 0 and cannot be used to tell the functions
      # apart (the kernel names them "Apple Tethering" and "Apple Private"). The
      # data function is registered first, so it holds the lowest ifindex; the
      # other is Apple's private multiplexor, which must stay out of
      # NetworkManager entirely.
      list=$(for n in /sys/class/net/*; do
        d=$(readlink -f "$n/device" 2>/dev/null) || continue
        [ "$(cat "$d/../idVendor" 2>/dev/null)" = 05ac ] || continue
        [ "$(basename "$(readlink -f "$d/driver" 2>/dev/null)")" = cdc_ncm ] || continue
        printf '%s %s\n' "$(cat "$n/ifindex" 2>/dev/null)" "$(basename "$n")"
      done | sort -n)
      # Late in an unplug the interfaces can already be gone.
      [ -n "$list" ] || exit 0

      data=$(printf '%s\n' "$list" | head -n1 | cut -d' ' -f2)
      for n in $(printf '%s\n' "$list" | tail -n +2 | cut -d' ' -f2); do
        nmcli device set "$n" managed no 2>/dev/null || true
      done

      # udev fires before NetworkManager has realized the device, and the profile
      # cannot be bound to an interface nmcli does not know yet.
      for _ in $(seq 1 20); do
        nmcli -t -f DEVICE device status | cut -d: -f1 | grep -qx "$data" && break
        sleep 0.5
      done

      nmcli device set "$data" managed yes
      nmcli connection up ipad-usb ifname "$data"
    '';
  };
in {
  # The helper is on PATH so the link can be brought up by hand when udev is not
  # in play (a stale interface, or after changing the profile).
  environment.systemPackages = [ipadDisplay ipad-usb-attach];

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
  # is set (the netdev name is dynamic and differs per port), the udev hook binds
  # it to whichever interface arrived, and the profile is regenerated on every
  # activation instead of drifting in /etc.
  networking.networkmanager.ensureProfiles.profiles.ipad-usb = {
    connection = {
      id = "ipad-usb";
      type = "ethernet";
      autoconnect = "false";
    };
    ipv4.method = "shared";
    ipv6.method = "ignore";
  };

  # NetworkManager dispatcher hooks fire on connection lifecycle, and a freshly
  # appeared interface matches no profile, so nothing activates and no hook runs
  # (verified: the NCM netdevs come up `disconnected` and stay that way). udev
  # fires on arrival, which is the event the link actually needs.
  #
  # Matching uses the properties the usb_id builtin sets, not ATTRS{} plus
  # DRIVERS: a rule cannot combine attributes from two different parents, and
  # here idVendor lives on the USB device (1-9) while bInterfaceClass and the
  # cdc_ncm driver live on the interface node (1-9:5.2). Such a rule is read,
  # is valid, and simply never matches. ID_VENDOR_ID and ID_USB_DRIVER are set
  # by the builtins, which run before 99-local, so they are visible here.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", ENV{ID_VENDOR_ID}=="05ac", ENV{ID_USB_DRIVER}=="cdc_ncm", RUN+="${pkgs.systemd}/bin/systemd-run --collect --quiet -- ${ipad-usb-attach}/bin/ipad-usb-attach"
  '';
}
