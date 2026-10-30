# Link watchdog for secu's USB Wi-Fi adapter (rtw88_8822bu).
#
# The adapter's firmware intermittently stalls: `failed to get tx report from
# firmware`, then `failed to download firmware` / `failed to leave ips state`,
# then wpa_supplicant loops on SCAN-FAILED and 4WAY_HANDSHAKE_TIMEOUT. The box
# stays up and healthy, but it is unreachable until the USB device is
# re-enumerated (2026-10-29 13:42 → 2026-10-30 11:50 was 22 h deaf).
# Re-enumerating reloads the firmware and fixes it, so this timer does that
# locally instead of waiting for a physical reset.
#
# Escalation: 2 consecutive failed pings (~4 min) → unbind/bind the USB
# interface → reconnect via NetworkManager. Rebinds are rate-limited to one per
# 10 minutes so a genuine AP outage does not thrash the device. No reboot:
# that would loop if the access point itself is down.
#
# Layered with the power-save fixes in secu-configuration.nix
# (rtw88_core disable_lps_deep=Y, NetworkManager wifi power save off), which
# address the state the firmware fails to leave.
{ pkgs, ... }:

let
  watchdog = pkgs.writeShellScript "secu-wifi-watchdog" ''
    set -uo pipefail
    state=/var/lib/secu-wifi-watchdog
    fails_file=$state/fails
    reset_file=$state/last-reset
    driver=/sys/bus/usb/drivers/rtw88_8822bu

    iface=
    for p in /sys/class/net/wl*; do
      [ -e "$p" ] || continue
      iface=''${p##*/}
      break
    done
    if [ -z "$iface" ]; then
      echo "no wireless interface present; nothing to do"
      exit 0
    fi

    gw=$(ip -4 route show default | sed -n 's/.* via \([0-9.]\{1,\}\) .*/\1/p' | head -1)
    # The gateway is the honest test: a link that is up but deaf still fails it.
    if [ -n "$gw" ] && ping -c 2 -W 2 -I "$iface" "$gw" >/dev/null 2>&1; then
      echo 0 > "$fails_file"
      exit 0
    fi

    fails=$(cat "$fails_file" 2>/dev/null || echo 0)
    case "$fails" in *[!0-9]*|"") fails=0 ;; esac
    fails=$((fails + 1))
    echo "$fails" > "$fails_file"
    echo "link down (gw=''${gw:-none}, consecutive failures: $fails)"

    [ "$fails" -lt 2 ] && exit 0

    now=$(date +%s)
    last=$(cat "$reset_file" 2>/dev/null || echo 0)
    case "$last" in *[!0-9]*|"") last=0 ;; esac
    if [ $((now - last)) -lt 600 ]; then
      echo "rebind skipped: last one $((now - last))s ago"
      exit 0
    fi

    dev=$(basename "$(readlink -f "/sys/class/net/$iface/device")")
    if [ -z "$dev" ] || [ ! -e "$driver/bind" ]; then
      echo "cannot resolve the USB interface for $iface (dev='$dev', driver=$driver)" >&2
      exit 1
    fi
    echo "$now" > "$reset_file"
    echo "rebinding $dev for $iface"
    if ! echo "$dev" > "$driver/unbind"; then
      echo "unbind of $dev failed" >&2
      exit 1
    fi
    sleep 2
    if ! echo "$dev" > "$driver/bind"; then
      echo "bind of $dev failed" >&2
      exit 1
    fi
    sleep 5
    nmcli device connect "$iface" >/dev/null 2>&1 || true
    echo 0 > "$fails_file"
  '';
in
{
  systemd.services.secu-wifi-watchdog = {
    description = "Rebind the USB Wi-Fi adapter when the link is deaf";
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.iproute2
      pkgs.iputils
      pkgs.networkmanager
    ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "secu-wifi-watchdog";
    };
    script = ''
      ${watchdog}
    '';
  };

  systemd.timers.secu-wifi-watchdog = {
    description = "Check the Wi-Fi link every 2 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "2min";
      AccuracySec = "15s";
      Unit = "secu-wifi-watchdog.service";
    };
  };
}
