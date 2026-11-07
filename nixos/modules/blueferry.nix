# BlueFerry — iPhone messages/contacts/notifications over Bluetooth (MAP/PBAP/ANCS).
#
# The package ships a systemd *user* unit ($out/etc/systemd/user), a system unit
# for the privileged Class-of-Device helper, and a polkit rule letting an active
# local session start that helper. systemd.packages installs both unit trees and
# "wantedBy" supplies the default.target wants symlink, which the unit itself
# cannot ship because NixOS ignores *.wants directories inside packages.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.blueferry;
  bluetooth = config.hardware.bluetooth;

  # BlueZ 5.86+ per-transport bearer interfaces (needed for ANCS) are gated
  # behind -E. -P hfp keeps BlueZ 5.87's experimental hands-free profile out of
  # the way, which would otherwise take the iPhone's HFP channel before oFono.
  bluetoothdArgs = [
    "-f"
    "/etc/bluetooth/main.conf"
    "-E"
    "-P"
    (lib.concatStringsSep "," (["hfp"] ++ bluetooth.disabledPlugins))
  ];

  # Separate derivation so the stock pkgs.bluez (and its cached dependents)
  # stays untouched; see the obex unit override below.
  obexd = bluetooth.package.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace obexd/src/logind.c \
          --replace-fail "static gboolean monitoring_enabled = TRUE;" \
            "static gboolean monitoring_enabled = FALSE;"
      '';
  });
in
{
  options.services.blueferry = {
    enable = lib.mkEnableOption "BlueFerry iPhone Bluetooth bridge";

    package = lib.mkPackageOption pkgs "blueferry" { };

    enableExperimentalBluez = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `bluetoothd` with `-E`. Messages and contacts work without it;
        iPhone system notifications (ANCS) and group recognition need it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = bluetooth.enable;
        message = "services.blueferry requires hardware.bluetooth.enable = true";
      }
    ];

    environment.systemPackages = [cfg.package];

    # Installs $out/etc/systemd/user/blueferry.service (user) and
    # $out/lib/systemd/system/blueferry-btmgmt-set-class@.service (system).
    systemd.packages = [cfg.package];

    # Start the daemon with the user session; it exits harmlessly until
    # ~/.config/blueferry/local.env exists (i.e. until pairing is done).
    systemd.user.services.blueferry.wantedBy = ["default.target"];

    # Lets an active local session start blueferry-btmgmt-set-class@N.service,
    # which is the only privileged step the pairing flow needs.
    security.polkit.extraConfig = builtins.readFile
      "${cfg.package}/share/polkit-1/rules.d/49-blueferry-cod.rules";

    # obexd registers the Bluetooth transport (MAP MNS, PBAP, OPP) only from
    # its logind callback, which fires when logind reports the user active on a
    # seat. lemurs + seatd sessions have no seat (loginctl shows Seat=), so
    # obexd exits with "No transport driver registered" and the iPhone has no
    # MNS to deliver incoming messages to. Run a patched obexd for the user
    # unit only: overriding pkgs.bluez instead changes the hash of everything
    # that links it (pipewire -> gtk4 -> chromium, qtwebengine, ...) and loses
    # the binary cache for most of the desktop.
    systemd.user.services.obex.serviceConfig.ExecStart = [
      ""
      "${obexd}/libexec/bluetooth/obexd"
    ];

    # pair-setup refuses to run unless the adapter advertises an audio profile
    # (A2DP sink, HSP headset or HFP hands-free), and BlueZ only advertises one
    # while a client holds a media endpoint. Those endpoints come from
    # pipewire's BlueZ monitor, which WirePlumber gates on logind seat state —
    # and lemurs + seatd sessions here have no seat at all. See the fragment.
    services.pipewire.wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/49-bluez-seat-monitoring.conf" ''
        # No seat on these sessions, so module-logind reports the user as
        # "online" instead of "active" and the BlueZ monitor never starts.
        # Single-user desktop: the seat check buys nothing.
        wireplumber.profiles = {
          main = {
            monitor.bluez.seat-monitoring = disabled
          }
        }
      '')
    ];

    systemd.services.bluetooth = lib.mkIf cfg.enableExperimentalBluez {
      # BlueFerry detects -E by reading /proc/<bluetoothd>/cmdline. The default
      # ProtectProc=invisible makes that unreadable for a user session daemon,
      # which would silently downgrade to "no ANCS notifications".
      serviceConfig.ProtectProc = lib.mkForce "default";

      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${bluetooth.package}/libexec/bluetooth/bluetoothd ${
          utils.escapeSystemdExecArgs bluetoothdArgs
        }"
      ];

      # nixpkgs defaults this to false to protect Bluetooth input devices. The
      # override above only takes effect on restart, and without it the first
      # switch leaves bluetoothd running without -E.
      restartIfChanged = lib.mkForce true;
    };
  };
}
