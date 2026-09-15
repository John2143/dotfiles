# Smart mirror — a host that boots straight into a single fullscreen Home
# Assistant dashboard on a black background, with no window manager, no
# desktop session, and no keyboard input required.
#
# Session stack: greetd (no greeter — starts the session directly) →
# cage (Wayland kiosk compositor; runs exactly one client fullscreen) →
# chromium in --kiosk. Same boot-to-one-app shape as secu-configuration.nix,
# minus Hyprland: a mirror needs no WM, workspaces, keybinds, or bar.
#
# The HA side is not configured here. For a clean single-screen result:
#   - create a dashboard with one view, make it the kiosk user's default,
#   - install the HACS "kiosk-mode" integration so "?kiosk" hides the
#     sidebar/header (see the `url` option),
#   - use a dark theme with a black background
#     (--primary-background-color: #000000).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.smart-mirror;

  # kanshi applies the panel rotation, and re-applies it every time the output
  # is (re-)initialised. That re-application is the whole point: cage resets an
  # output to the unrotated default whenever the connector is re-probed (which
  # on this mirror happens whenever the HDMI link blips or the screen is
  # power-cycled), so a one-shot rotation does not survive. kanshi watches the
  # output configuration and re-applies its matching profile when it changes.
  kanshiConfig = pkgs.writeText "smart-mirror-kanshi.conf" ''
    profile {
      output ${cfg.output} enable transform ${cfg.transform}
    }
  '';

  # Runs *inside* the cage session — a Wayland client needs a compositor to
  # talk to — and before the browser, so the browser maps onto the rotated
  # output from the start rather than being resized out from under itself.
  # kanshi creates no window, so cage's single-window mode is unaffected.
  client = pkgs.writeShellApplication {
    name = "smart-mirror-client";
    runtimeInputs = [cfg.browser pkgs.kanshi];
    text = ''
      kanshi -c ${kanshiConfig} &

      # cage paints a solid black backdrop; the chromium window fills it.
      # A persistent --user-data-dir keeps the Home Assistant login across
      # reboots (log in once, by hand, with a keyboard attached).
      args=(
        --ozone-platform=wayland
        --kiosk
        --user-data-dir="$HOME/${cfg.userDataDir}"
        --password-store=basic
        --hide-scrollbars
        --noerrdialogs
        --disable-infobars
        --no-first-run
        --no-default-browser-check
        --disable-session-crashed-bubble
        --disable-component-update
        --check-for-update-interval=31536000
        ${lib.escapeShellArgs cfg.extraFlags}
      )
      exec ${lib.getExe cfg.browser} \
        --disable-features=TranslateUI,Translate,MediaRouter \
        "''${args[@]}" "${cfg.url}"
    '';
  };

  kiosk = pkgs.writeShellApplication {
    name = "smart-mirror-session";
    text = ''
      exec ${pkgs.cage}/bin/cage -s -- ${lib.getExe client}
    '';
  };
in {
  options.services.smart-mirror = {
    enable = lib.mkEnableOption "the Home Assistant smart-mirror kiosk";

    url = lib.mkOption {
      type = lib.types.str;
      example = "https://home.ts.2143.me/mirror/0?kiosk";
      description = "Dashboard URL loaded fullscreen at boot.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "john";
      description = "User the kiosk session runs as (must exist).";
    };

    browser = lib.mkOption {
      type = lib.types.package;
      default = pkgs.chromium;
      defaultText = lib.literalExpression "pkgs.chromium";
      description = "Browser used for the kiosk.";
    };

    output = lib.mkOption {
      type = lib.types.str;
      default = "HDMI-A-1";
      description = ''
        DRM connector the kiosk renders to, as named by wlr-randr and
        /sys/class/drm (for example HDMI-A-1). Used only to apply the rotation.
      '';
    };

    transform = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "90"
        "180"
        "270"
        "flipped"
        "flipped-90"
        "flipped-180"
        "flipped-270"
      ];
      default = "normal";
      description = ''
        Output transform for a panel that is mounted rotated. "90" is a 90°
        counter-clockwise rotation. Applied by kanshi, which re-applies it
        whenever the output configuration changes — cage on its own drops it
        as soon as the HDMI connector is re-probed.
      '';
    };

    userDataDir = lib.mkOption {
      type = lib.types.str;
      default = ".local/share/smart-mirror";
      description = ''
        Browser profile directory, relative to the kiosk user's home.
        Persisted across reboots so the Home Assistant session survives.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--force-device-scale-factor=1" "--lang=en-US"];
      description = "Extra flags appended to the browser command line.";
    };
  };

  config = lib.mkIf cfg.enable {
    # greetd owns the display: no login prompt, the kiosk command *is* the
    # session. If it crashes, greetd restarts it (restart defaults to true),
    # which is exactly the self-healing behaviour a wall-mounted display wants.
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = lib.getExe kiosk;
        user = cfg.user;
      };
    };

    # seatd hands the compositor the GPU/input seat without the caller being
    # a logind session. Same pattern as secu-configuration.nix.
    services.seatd.enable = true;

    # Wayland + GL for cage/chromium.
    hardware.graphics.enable = true;

    # The console must never blank out — the mirror is always-on.
    boot.kernelParams = ["consoleblank=0"];

    # Home Assistant's frontend expects an emoji-capable sans font.
    fonts.packages = with pkgs; [noto-fonts noto-fonts-color-emoji];

    environment.systemPackages = [pkgs.cage cfg.browser];
  };
}
