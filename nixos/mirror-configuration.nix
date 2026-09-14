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

  # Both of these are carried over from the configuration this machine is
  # already running, so the switch does not silently drop them:
  #  - the serial + HDMI consoles matter because the finished mirror has no
  #    keyboard; without them a wedged kiosk is only reachable over SSH.
  #  - zram is the machine's only swap. A Pi 4 running a chromium kiosk with
  #    no swap at all is a needless OOM risk.
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
  ];
  zramSwap.enable = true;

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
