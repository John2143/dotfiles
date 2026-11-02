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
