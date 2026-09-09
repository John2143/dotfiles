# Steam VM — Proxmox VM on bigp (2 cores, 4 GB RAM, SeaBIOS, virtio)
#
# Boots to an XFCE desktop auto-logged-in as `steam`, starts the Steam client
# (kept logged in to a dedicated alt account across reboots), and autostarts
# an external lobby-watcher that drives Steam inside that logged-in session.
#
# === INSTALL FROM LIVE CD ===
#   On bigp: qm create 102 --name steam-nixos --machine q35 --cpu host \
#     --sockets 1 --cores 2 --memory 4096 --net0 virtio,firewall=1,bridge=vmbr0 \
#     --scsihw virtio-scsi-single --scsi0 ZFS-POOL:40,iothread=1 \
#     --ide2 local:iso/nixos-minimal-<current>-x86_64-linux.iso,media=cdrom \
#     --serial0 socket --agent 1 --ostype l26 --boot order=ide2\;scsi0
#   DISK STORAGE: the VM's 40G disk must live on bigp's ZFS-backed Proxmox
#   storage, NEVER local-lvm (no space there). On bigp run `pvesm status` and
#   substitute the ZFS storage's name for ZFS-POOL; if no ZFS storage exists,
#   create one, e.g. `pvesm add <name> zfspool --pool <zpool>/data
#   --content images,rootdir` (names come from bigp — never guess them). The
#   ISO (--ide2) may stay on `local` — it is small and only used to boot the
#   installer. Proxmox allocates the ZFS disk as a zvol, so the guest still
#   sees one virtio-scsi disk at /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_*
#   (disko layout below is unchanged).
#   On installer: clone https://github.com/John2143/dotfiles.git, then
#     sudo nix --experimental-features "nix-command flakes" \
#       run github:nix-community/disko -- --mode disko ./nixos/modules/disko_steam.nix
#     sudo nixos-install --no-root-passwd --flake /tmp/dotfiles#steam
#
# === FIRST BOOT ===
#   XFCE auto-logs in as `steam`; Steam's login window appears on the Proxmox
#   console — sign in to the alt account once (Steam Guard). Then place the
#   lobby watcher's executable at the path named by `lobbyWatcherExec` below
#   (e.g. /opt/lobby-watcher/…) and reboot. Every later boot `steam -silent`
#   restores that session from /home/steam (persists on the root partition;
#   only a disko reinstall wipes it). Watch ~/.local/state/lobby-watcher.log.
#
# === GOTCHAS ===
#   - SeaBIOS + GRUB, like big — disko's EF02 partition provides grub.devices.
#     Do NOT set boot.loader.grub.device (duplicate-device assertion).
{
  config,
  lib,
  pkgs,
  sshKeys,
  modulesPath,
  ...
}: let
  # The lobby watcher lives outside this repo. Clone/place its executable at
  # this path on the VM (e.g. /opt/lobby-watcher/lobby-watcher) and point this
  # single line at it. The autostart wrapper (lobby-watcher-up) waits for the
  # Steam client, then keeps the watcher running inside this graphical session.
  lobbyWatcherExec = "/opt/lobby-watcher/lobby-watcher";
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix") # Proxmox VM virtio drivers
    ./steam-hardware-configuration.nix # fileSystems owned by disko (see modules/disko_steam.nix)
    ./modules/user-john.nix
  ];

  # disko provides boot.loader.grub.devices from the EF02 partition — do NOT set
  # boot.loader.grub.device (big-configuration.nix gotcha: duplicate-device assertion).
  boot.loader.grub.enable = true;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "sd_mod"
    "ext4"
  ];

  networking.hostName = "steam";
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
    xfce.xfce4-terminal # terminal for the one-time Steam login on the console
    # Waits for the Steam client (up to ~2 min), then keeps the lobby watcher
    # alive; logs to the steam user's state dir. Respawns on exit after 10s.
    # Absolute tool paths: XDG-autostarted sessions may not put sw/bin on PATH.
    (pkgs.writeShellScriptBin "lobby-watcher-up" ''
      i=0
      until ${pkgs.procps}/bin/pgrep -x steam >/dev/null || [ "$i" -ge 60 ]; do
        ${pkgs.coreutils}/bin/sleep 2
        i=$((i + 1))
      done
      while :; do
        "${lobbyWatcherExec}" >> "$HOME/.local/state/lobby-watcher.log" 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 10
      done
    '')
  ];

  # ================
  # === Services ===
  # ================

  services.openssh.enable = true;
  users.users."john".openssh.authorizedKeys.keys = sshKeys;
  # Proxmox guest agent — graceful shutdown from hypervisor
  services.qemuGuest.enable = true;

  # Default firewall stays on; only SSH is opened (LAN admin via `john`).
  networking.firewall.allowedTCPPorts = [22];

  # ==============================================
  # === Graphical session — auto-login + Steam ===
  # ==============================================
  # sddm + XFCE: the standard NixOS greeter with native autoLogin, driving an X
  # session (Steam needs X; XDG autostart runs inside it). lightdm is no longer
  # in nixpkgs; lemurs (the desktop hosts' greeter) targets Wayland/Hyprland and
  # lacks autoLogin. The steam user has no password — autoLogin bypasses the
  # greeter; admin goes through `john`.

  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "steam";

  # Steam client — 32-bit/FHS handled by the module; unfree already allowed by
  # shared-cli-configuration.nix (imported in flake.nix). Software rendering
  # (llvmpipe) is fine: no GPU passthrough, no gamescope, no audio in this VM.
  programs.steam.enable = true;

  users.users.steam = {
    isNormalUser = true;
    extraGroups = [
      "video"
      "audio"
      "input"
      "networkmanager"
    ];
    description = "Steam lobby VM account";
  };

  # Start Steam in the autologin session, quiet (no library window). After the
  # first manual login (above), every boot restores the logged-in session.
  environment.etc."xdg/autostart/steam.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Steam
    Exec=${pkgs.steam}/bin/steam -silent
  '';

  # Start the lobby watcher once Steam is up. Inherits the steam user's session
  # env (DISPLAY, DBUS, HOME) — that session is the Steam context it drives.
  environment.etc."xdg/autostart/lobby-watcher.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Lobby watcher
    Exec=/run/current-system/sw/bin/lobby-watcher-up
  '';

  system.stateVersion = "25.11";
}
