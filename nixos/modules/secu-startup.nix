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
          hl.exec_cmd("sleep 3; firefox https://glkvm.ts.2143.me")
        end
      '')]; }
    ];
    # GL-KVM camera view — fullscreen on open (recreates the old always-on
    # fullscreen grid experience). Inert on other hosts (no GLKVM-titled window).
    window_rule = [
      { match = { title = "^GLKVM$"; }; fullscreen = true; }
    ];
  };
}
