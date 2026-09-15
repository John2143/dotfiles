# mirror — wall-mounted Home Assistant display.
#
# Boots straight into one fullscreen HA dashboard on a black background.
# The session (greetd → cage → chromium --kiosk) lives in
# modules/smart-mirror.nix; everything here is host identity + admin access.
#
# Admin is SSH-only: the finished mirror has no keyboard, and greetd owns
# tty1 with no login prompt. To recover a wedged session, Ctrl+Alt+F2 if a
# keyboard is still attached, otherwise reboot (the kiosk restarts itself).
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  compName,
  sshKeys,
  ...
}: {
  imports = [
    ./mirror-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/smart-mirror.nix
  ];
  home-manager.users."john" = import ./home-remote.nix;

  # === Smart mirror session ===
  services.smart-mirror = {
    enable = true;
    user = "john";
    # "mirror" = dashboard slug, "0" = its first view. "?kiosk" is honoured
    # by the HACS kiosk-mode integration to hide the sidebar and header; it
    # is a client-side nicety, not a security boundary.
    url = "https://home.ts.2143.me/mirror/0?kiosk";
  };

  # Raspberry Pi 4: the firmware loads u-boot, which distro-boots
  # /boot/extlinux/extlinux.conf. There is no EFI firmware on this box, so
  # systemd-boot (and grub) are both wrong here. Same pattern the other Pis in
  # this repo use — see remote-cli-config.nix.
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  # Consoles and memory headroom. The consoles are carried over from the
  # configuration this machine already runs; the memory settings are the fix
  # for this Pi locking up (sshd stops answering while ICMP keeps replying —
  # sshd cannot fork, the kernel still does).
  #
  #   zram     ~900 MB of fast compressed swap (the 50%-of-RAM default on a
  #            2 GB Pi 4). On its own this is NOT enough: a chromium kiosk
  #            plus a nix rebuild exhausts it and the box wedges.
  #   swapfile 4 GB backstop on the SD card. Slow, but it is the difference
  #            between "crawling" and "dead". Same pairing the other Pis in
  #            this repo use — see remote-cli-config.nix.
  #
  # The consoles matter because the finished mirror has no keyboard; without
  # them a wedged kiosk is only reachable over SSH.
  #
  # The panel is physically mounted in portrait, so the output needs a 90°
  # counter-clockwise turn — otherwise "up" points to the right. cage cannot
  # rotate at all (its entire option set is -d/-D/-h/-m/-s/-v), so this is
  # pushed down to the DRM/KMS layer.
  #
  # The mode is FORCED to 1920x1080@60 on purpose. Without a mode the panel
  # only gets what the EDID advertises, and this monitor's EDID is frequently
  # unreadable (it reports 0 bytes while the screen is off, and the kernel then
  # falls back to its generic no-EDID VESA list — 1024x768, 800x600, 848x480,
  # 640x480 — so the mirror comes up at 1024x768 on a 1080p panel, and stays
  # there). Forcing the mode makes the signal correct whether or not the
  # display answers EDID probing. 1920x1080 is this panel's native mode; when
  # the EDID does read it reports exactly that, preferred, at a 148.5 MHz
  # pixel clock.
  #
  # Note the forced mode is built by the kernel's GTF maths
  # (drm_mode_create_from_cmdline_mode), not copied from the EDID, so the
  # blanking is a hair different from the native CEA timing — same resolution,
  # same ~60 Hz, hsync within ~0.5% of native. That is the price of "always
  # correct", and it is why `rotate=90` (which also requires a mode) is not
  # used: it would additionally pin the plane rotation, which the compositor
  # then fights over.
  #
  # `panel_orientation=` carries the rotation instead. It sets the connector's
  # "panel orientation" property, which wlroots reads to choose the output
  # transform — and cage is wlroots-based, so it honours it.
  #
  # left_side_up = the panel's left edge is at the top (monitor turned 90°
  # clockwise). If the turn comes out the other way, right_side_up is the
  # alternative.
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
    "video=HDMI-A-1:1920x1080@60,panel_orientation=left_side_up"
  ];
  zramSwap.enable = true;
  swapDevices = [{device = "/swapfile"; size = 4096;}];

  networking.hostName = compName; # Define your hostname.
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    htop
    # Diagnostics for a headless-ish display: grim captures the running
    # compositor (if cage exposes wlr-screencopy), wlr-randr reports/edits
    # output state (if cage exposes wlr-output-management).
    grim
    wlr-randr
  ];

  programs.fish.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;
  users.users."john".openssh.authorizedKeys.keys = sshKeys;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  security.rtkit.enable = true;

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?
}
