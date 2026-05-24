# Context: secu-nvr-per-channel

> Saved 2026-05-23 23:13 EDT from branch `master` by `john`

## Goal

Configure the NixOS "secu" machine (HP EliteDesk 800 G3, i5-6500T, 7.6GB, at 192.168.5.140) to auto-boot into Hyprland and display 6 Reolink security camera feeds 24/7 from the NVR at 192.168.1.67 — fully hands-off, no login prompts, no browser interaction.

## Current State

- **Branch**: `master`
- **Modified files**: 13 files (5 secu-related, 8 unrelated)
- **Secu-related changes**:
  - `nixos/secu-configuration.nix` — +27/-6: lemurs auto-login, age secret wiring, consoleblank=0, socat
  - `nixos/home.nix` — +8/-5: secu-conditional startup hook, gaps=0 override, gammastep disabled
  - `.config/startup-secu.fish` — new file: 64-line fish script launching 6 mpv RTSP windows
  - `secrets/secrets.nix` — +9: camera-credentials.age entry (encrypted to secu/office/arch)
  - `secrets/camera-credentials.age` — new encrypted age file (user created manually)
- **Unrelated changes** (in working tree but not part of this task): flake.lock, network-engineer skill, hetzner config, reboot.txt, unifi-credentials.age, shared-cli-configuration.nix
- **Last commit**: `933b593 fix(hetzner): postgres schema permission, pdnsutil config-dir, namespace creation, cert-manager operator`

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Pull RTSP from NVR, not individual cameras | Single device (192.168.1.67), one credential set, NVR handles all camera connections internally. Cameras are on a separate subnet (192.168.1.0/24) with WAN egress blocked by firewall. |
| 2 | Use per-channel NVR streams instead of `Preview_All` | `Preview_All` (multi-view grid) not supported on this NVR firmware. User tested: only `h264Preview_0N_sub` works. |
| 3 | Six mpv windows tiled by Hyprland dwindle, not ffmpeg composite | Simpler to implement and debug; Hyprland handles tiling automatically with gaps=0; each stream can fail independently without breaking the whole grid. |
| 4 | Lemurs auto_login settings instead of getty autologin | Lemurs already enabled; its `auto_login` config selects the first Wayland session (Hyprland) without user interaction. `services.getty.autologinUser` kept for TTY fallback. |
| 5 | Gammastep disabled on secu | Night-mode color shifting would interfere with camera monitoring (color accuracy matters for security footage). |
| 6 | JetKVM automation dropped | User said "don't worry about jetkvm" — removed Firefox launch and KVM auto-login from startup script. |

## Ruled Out

| Approach | Why rejected |
|----------|-------------|
| `Preview_All` single RTSP stream from NVR | Not supported on this NVR firmware — user tested and confirmed only per-channel works |
| Pulling RTSP from individual cameras (192.168.1.60-66) | More devices to manage, each on camera subnet, extra network hops |
| ffmpeg grid compositing into single mpv window | Adds complexity, harder to debug individual camera failures |
| Firefox + NVR web UI for camera viewing | Requires browser login, not hands-off |
| Using Reolink desktop client | GUI dependency, not scriptable, may not be available on NixOS |
| Browser-based JetKVM auto-login with password manager | User explicitly said not to worry about JetKVM |

## Open Questions

- [ ] Channel-to-camera mapping: which NVR channel (1-6) corresponds to which physical camera? The channel order on the NVR may differ from the IP list in `network-topology.md`. User should verify after first boot.
- [ ] Monitor output names on secu: the HP EliteDesk 800 G3 may have different DisplayPort names than the office/arch machines. The shared hyprland config assumes `DP-2`/`DP-3` or `DP-1`/`HDMI-A-2`. If secu has different monitor names, the workspace rules may need adjustment.
- [ ] Substream vs main stream: currently using `h264Preview_0N_sub` (low-res). If the grid is too low quality for practical monitoring, switch to `_main` (higher bandwidth, higher CPU).

## Recent Artifacts

| Path | Description | Last Modified |
|------|-------------|---------------|
| `.config/startup-secu.fish` | 64-line fish script: sources camera creds, disables DPMS, launches 6 mpv windows from NVR | 2026-05-23 22:48 |
| `nixos/secu-configuration.nix` | 123 lines: lemurs auto-login, age secret, consoleblank, socat | 2026-05-23 22:10 |
| `nixos/home.nix` | 537 lines: conditional startup hook, gaps=0 for secu, gammastep disabled for secu | 2026-05-23 22:08 |
| `secrets/secrets.nix` | 154 lines: added camera-credentials.age publicKeys entry | 2026-05-23 22:04 |
| `secrets/camera-credentials.age` | Encrypted age file (secu+office+arch), format: `CAMERA_USER=admin\nCAMERA_PASSWORD=<pw>` | 2026-05-23 22:44 |
| `local://secu-nvr-per-channel.md` | Finalized plan document | 2026-05-23 |

## Constraints

- Fully hands-off: no login prompts, no browser interaction, no credential entry at boot
- 24/7 operation: screen must never blank, no night-mode color shift
- Camera credentials stored in age-encrypted secret, decrypted to `/run/agenix/camera-credentials` at boot
- NVR at 192.168.1.67 on camera subnet (192.168.1.0/24), reachable from secu (192.168.5.140) via MikroTik inter-subnet routing
- JetKVM is out of scope
- Do not modify shared config in ways that affect office/arch hosts

## Next Steps

1. [ ] **Pick up here**: Deploy to secu — `nh os switch . -- --target secu` (requires physical access or SSH to secu)
2. [ ] After boot, verify Hyprland starts automatically and the 6 mpv windows appear on workspace A2
3. [ ] Verify camera channel mapping — check which physical camera each NVR channel shows
4. [ ] If monitor layout is wrong, adjust `MONITOR_LEFT`/`MONITOR_RIGHT` variable in `nixos/home.nix` for secu or set up separate monitor config
5. [ ] If substream quality is insufficient, change `_sub` to `_main` in the RTSP URLs in `.config/startup-secu.fish`
6. [ ] Consider adding a systemd user service that restarts mpv if a stream dies (currently no watchdog)

## Verification

- `nix flake check` — secu evaluates without errors: **PASSED**
- `nix eval .#nixosConfigurations.secu.config.services.displayManager.lemurs.settings.auto_login` → `{enabled=true, username=john, default_desktop=0}`: **PASSED**
- `nix eval .#nixosConfigurations.secu.config.home-manager.users.john.wayland.windowManager.hyprland.settings.config.general.gaps_out` → `0`: **PASSED** (office: `5`)
- `nix eval .#nixosConfigurations.secu.config.home-manager.users.john.services.gammastep.enable` → `false`: **PASSED** (office: `true`)
- `nix eval .#nixosConfigurations.secu.config.age.secrets.camera-credentials.file` → `/home/john/dotfiles/secrets/camera-credentials.age`: **PASSED**
- Live test: boot secu, confirm Hyprland auto-starts and 6 mpv windows tile on workspace A2: **NOT DONE** (pending deploy)
