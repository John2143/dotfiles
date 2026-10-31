{ lib, ... }:
let
  mkLua = lib.generators.mkLuaInline;
in {
  home-manager.users.john.wayland.windowManager.hyprland.settings = {
    # Boot: after the compositor is ready and tailscale/MagicDNS has settled,
    # open Firefox on the GL-KVM web UI (KVM-over-IP showing the NVR screen).
    on = [
      { _args = ["hyprland.start" (mkLua ''
        function()
          hl.exec_cmd("sleep 3; firefox --marionette https://glkvm.ts.2143.me")
        end
      '')]; }
    ];
    # GL-KVM camera view — fullscreen on open (recreates the old always-on
    # fullscreen grid experience). Inert on other hosts (no GLKVM-titled window).
    window_rule = [
      { match = { title = "^GLKVM"; }; fullscreen = true; }
      # The device serves a self-signed cert (CN=localhost, expired 1979), so a
      # one-time "Accept the Risk" is needed. Firefox does persist that override
      # (cert_override.txt in the profile) — but only for the exact cert, so a
      # firmware update that regenerates it brings the interstitial back.
      # Fullscreen it too, so accepting lands on a fullscreen window and the
      # GL-KVM view below it stays fullscreen.
      { match = { title = "^(Warning: Security Risk|Potential Security Risk Ahead)"; }; fullscreen = true; }
    ];
  };
}
