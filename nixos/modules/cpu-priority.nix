# CPU priority tiers for the graphical session, expressed as cgroup v2 CPUWeight.
#
# Measured topology on arch (2026-11-15, `/proc/<pid>/cgroup` and
# `systemctl show -p CPUWeight`):
#
#   user-1000.slice                    default 100
#   ├── session-c1.scope               default 100   Hyprland, Xwayland, start-hyprland,
#   │                                               tmux, terminals          <- tier 1
#   └── user@1000.service              40            (this file)
#       ├── app.slice                  60            waybar, portals, teamspeak,
#       │                                            steam client, other services <- tier 2
#       ├── discord.slice              30            discord                  <- tier 3
#       └── games.slice                10            Path of Exile, firefox   <- tier 4
#
# CPUWeight is a proportional weight, not a cap: it decides nothing while cores
# are idle, so the game still gets every core it asks for. It decides only who
# waits during the bursts where all 16 threads are runnable.
#
# At full saturation with the numbers below the compositor's branch takes
# 100/140 = 71 %, app.slice 17 %, discord.slice 9 %, games.slice 3 %. Raise
# `games` if load-time and shader-compile bursts feel starved -- the ordering
# survives as long as compositor > services > discord > games.
#
# Getting a process into a tier needs the launcher to name the slice; weights
# alone cannot separate two processes that already share a cgroup. Discord and
# firefox are wrapped below. The game is not launched from this repo: put
#   systemd-run --user --scope --slice=games.slice -- %command%
# in the game's Steam launch options.
{...}: let
  tiers = {
    # Everything the user manager launches. The compositor's session scope is a
    # sibling of this, so pushing the whole branch under its 100 default is what
    # makes the compositor the top tier without having to name logind's
    # per-login scope (session-c1, c2, ...), which cannot take a drop-in.
    appsBranch = 40;

    services = 60;
    discord = 30;
    games = 10;
  };

  # GUI apps inherit the cgroup of whoever launched them, so a desktop entry has
  # to name its slice explicitly to get out of the session scope.
  launchInSlice = slice: command: "systemd-run --user --scope --slice=${slice} -- ${command}";

  # Metadata copied from the packaged .desktop so overriding Exec does not drop
  # the URL handlers (default-browser association keys off this file's name).
  firefoxEntry = {
    name = "Firefox";
    genericName = "Web Browser";
    exec = launchInSlice "games.slice" "firefox %U";
    icon = "firefox";
    terminal = false;
    type = "Application";
    categories = ["Network" "WebBrowser"];
    mimeType = [
      "text/html"
      "text/xml"
      "application/xhtml+xml"
      "application/vnd.mozilla.xul+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    settings.StartupWMClass = "firefox";
  };

  discordEntry = {
    name = "Discord";
    exec = launchInSlice "discord.slice" "discord";
    icon = "discord";
    terminal = false;
    type = "Application";
    categories = ["Network" "InstantMessaging"];
    mimeType = ["x-scheme-handler/discord"];
    settings.StartupWMClass = "discord";
  };
in {
  # Tier 1 is logind's session scope and owns its own name, so instead of raising
  # it we hold everything the user manager launches below its default of 100.
  #
  # This cannot be an environment.etc entry: environment.etc."systemd/system" is
  # a single symlink into the generated `system-units` derivation, so adding a
  # file below it fails with "Permission denied" at build time. The systemd
  # module owns that tree, and user@.service is already defined there as an
  # asDropinIfExists override (the LOCALE_ARCHIVE/PATH environment), so contribute
  # to the same definition — it lands in
  # /etc/systemd/system/user@.service.d/overrides.conf.
  systemd.services."user@".serviceConfig.CPUWeight = tiers.appsBranch;

  home-manager.users.john = {
    xdg.configFile = {
      # app.slice already exists (systemd ships it), so weight it as a drop-in
      # rather than shadowing the packaged unit.
      "systemd/user/app.slice.d/50-cpu-priority.conf".text = ''
        [Slice]
        CPUWeight=${toString tiers.services}
      '';

      # These two do not exist yet; systemd-run --slice= needs a unit to place
      # scopes in, so define them with their weights.
      "systemd/user/discord.slice".text = ''
        [Slice]
        CPUWeight=${toString tiers.discord}
      '';

      "systemd/user/games.slice".text = ''
        [Slice]
        CPUWeight=${toString tiers.games}
      '';
    };

    xdg.desktopEntries = {
      firefox = firefoxEntry;
      discord = discordEntry;
    };
  };
}
