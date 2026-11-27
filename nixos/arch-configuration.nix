# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  pkgs,
  pkgs-stable,
  inputs,
  lib,
  sshKeys,
  ...
}: {
  imports = [
    ./arch-hardware-configuration.nix
    # Direct link to the MacBook's USB Ethernet adapter, same 10.99.0.1 as office
    # so the Mac's `thunderbolt` entry works in either machine.
    ./modules/macbook-link.nix
    ./modules/user-john.nix
    ./modules/vllm.nix
    # ./modules/frigate.nix  # migrated to k8s on big (2026-08-01); file kept for rollback
    ./modules/teamspeak.nix
    ./modules/nut-ups.nix
    ./modules/blueferry.nix
    ./modules/cpu-priority.nix

    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;

  # Login keys for the admin account. shared-cli-configuration.nix enables sshd
  # but no module declared keys for it, so access depended on a hand-edited
  # ~/.ssh/authorized_keys: adding a client key to `my-keys` and rebuilding
  # changed nothing. Doing it here makes flake.nix the single source of truth.
  # sshd still accepts ~/.ssh/authorized_keys too, so nothing is revoked.
  users.users."john".openssh.authorizedKeys.keys = sshKeys;

  # Leave `trusted-users` alone. A trusted user is root-equivalent to the nix
  # daemon — it may override sandboxing, substituters and keys for every user —
  # so it is not worth granting just to silence "ignoring the client-specified
  # setting 'netrc-file' / 'trusted-public-keys': you are not a trusted user".
  # The cache is configured system-wide instead: modules/attic.nix (imported by
  # flake.nix for this host) sets substituters, trusted-public-keys and
  # netrc-file, and the daemon applies those regardless of what the client asks
  # for. Keep ~/.config/nix/nix.conf free of restricted keys — a client copy is
  # ignored with the warning above, and would shadow the system key if john ever
  # did become trusted. John's stale copy was removed 2026-11-24 (it carried the
  # old 2143nix key, and nothing in this repo referenced its netrc).
  # (The commented value below is john's SSH public key, not a nix signing key —
  # nix wants `name:base64` there, so it would be inert.)
  #nix.settings.trusted-users = [ "@wheel" ];
  #nix.settings.trusted-public-keys = [
  #"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
  #];

  #services.getty.autologinUser = "john";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.supportedFilesystems = ["ntfs"];
  # Desktop swap is a safety valve, not a cache: the anonymous working set is
  # ~24.5 GiB resident + ~19.8 GiB swapped on 32 GiB RAM, so a low swappiness
  # would OOM-kill instead of paging (fleet default is 10, see swap-tuning.nix).
  boot.kernel.sysctl."vm.swappiness" = "60";
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.kernelModules = [
    "target_core_mod"
    "iscsi_target_mod"
  ];

  # The Realtek RTL8761BU in the ASUS USB-BT500 (0b05:190e) aborts its firmware
  # with "RTL: hw err, trigger devcoredump (51)" when USB autosuspend parks it,
  # and that crash drops every Bluetooth link at once (2026-11-19 21:23, after
  # ~91 min up, taking the Mac, iPad and iPhone with it). This kernel build sets
  # btusb.enable_autosuspend=Y, so turn it off for the driver and pin the
  # dongle's power control: the parameter covers the driver, the rule covers the
  # device node across re-plugs.
  boot.kernelParams = ["btusb.enable_autosuspend=0"];
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="190e", TEST=="power/control", ATTR{power/control}="on"

    # The onboard Intel radio (8087:0aa7, the "arch(in" controller) is never
    # used: it has no bonded devices, every device lives on the USB dongle, and
    # only the dongle reports the "Arch" alias. Powering it off after the fact
    # does not hold — blueman's PowerManager iterates every adapter and
    # re-powers them (2026-11-20 21:13:10, two minutes after btmgmt-off ran).
    # While it is up, paired phones page it, BlueZ spawns transient
    # /org/bluez/hci1/dev_* objects, blueman throws KeyError on each Connected
    # change, and iOS raises a pairing prompt over and over. Deauthorize the
    # USB device instead, so no hci1 ever exists. The same card's Wi-Fi is PCIe
    # (0000:06:00.0), so this touches Bluetooth only.
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="8087", ATTR{idProduct}=="0aa7", ATTR{authorized}="0"
  '';

  # Panic dumps in reserved RAM: efivarfs is 192K with ~136K free here, too
  # small for a 112-180K dump.
  custom.crashCapture.enable = true;
  custom.crashCapture.ramoops.enable = true;

  services.seatd.enable = true;

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSOverTLS = "true";
        DNSSEC = "true";
        Domains = [
          "~."
        ];
        FallbackDNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
    };
  };

  networking.hostName = "arch";

  # Any spare port, so the cable works wherever it is plugged in (eno1 is the
  # one the MacBook's adapter actually reaches).
  services.macbookLink.interfaces = ["eno1" "enp7s0" "enp2s0f1"];
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # No tailnet subnet route from this desktop. k3s-server.nix advertises the LAN
  # and MetalLB subnets from every k3s server, and headscale makes the online,
  # approved router with the lowest node ID the primary on each restart. arch is
  # node 1, so it kept winning that election, and a host-level exit node on arch
  # then cut the rest of the tailnet off from both subnets. closet is the
  # primary, nas the standby; arch is not a router.
  services.tailscale.extraSetFlags = lib.mkForce [];

  # mDNS on the stable links only. Left to itself avahi joins every interface,
  # including each k3s pod's ephemeral veth pair; the pod churn makes it
  # re-probe the host name, and five conflicts on 2026-11-19 left it calling
  # itself arch-6.local. enp2s0f0 is the LAN, eno1 the direct MacBook link.
  services.avahi.settings.server.allow-interfaces = ["enp2s0f0" "eno1"];

  networking.nameservers = [
    "1.1.1.1"
    "192.168.1.12"
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Second keyboard (winkeyless ps2avrGB) remapped to F13-F24.
  # F23 and F24 are the last standard Linux function keycodes (KEY_F23, KEY_F24).
  # Any additional keys beyond F24 should use XF86Launch* (Launch8, Launch9, etc.)
  # to continue the pattern from the existing XF86Launch5/6/7 mappings.
  # Hyprland binds in hyprland.conf map these to actual commands.

  environment.systemPackages = [
    #inputs.hyprcap.packages.x86_64-linux.default
    pkgs.voxtype
    #inputs.self.packages.x86_64-linux.waytop
    # Discord Rich Presence for Proton games (Timestone/UMVC3). Steam launch
    # option: /run/current-system/sw/bin/rpc-bridge-steam %command%
    (pkgs.callPackage ./packages/rpc-bridge.nix {})
  ];

  # openrgb flakes occasionally — keep the unit out of "failed" state so it
  # doesn't trip exit-code-4 in switch-to-configuration's post-activation scan.
  systemd.services.openrgb.enable = lib.mkForce false;

  custom.k3sStorageAfter = ["mnt-longhorn.mount"];

  # k3s server — joins through the API VIP; identity and cluster networking
  # come from modules/k3s-net.nix.
  custom.k3sNet = {
    ipv4 = "192.168.5.76";
    # The node IPv6 is this NIC MAC's EUI-64 form under the router's fd00:1::/64,
    # i.e. fd00:1::9ab7:85ff:fe23:4890. Derived, so it cannot rotate the way the
    # old stable-privacy address did — flannel's VTEP must not move.
    ipv6Mac = "98:b7:85:23:48:90";
    # Reserve 12 CPU + 16 GiB RAM for the system (Hyprland desktop, 32 GiB total per lshw). k8s gets 4 CPU, ~15.3 GiB.
    systemReserved = "cpu=12,memory=16Gi";
  };
  custom.backup.enable = true;

  # Building screen-control directly instead of nix run (which was slow and
  # didn't reliably pass the systemd `path` environment through to the binary).
  nixpkgs.overlays = [
    (final: prev: {
      screen-control = inputs.screen-control.defaultPackage.${prev.stdenv.hostPlatform.system};
    })
  ];

  # iPhone messages/contacts/notifications over Bluetooth (MAP/PBAP/ANCS).
  services.blueferry.enable = true;

  systemd.services.screen-control = {
    description = "REST screen control server";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.screen-control}/bin/screen-control";
      Restart = "always";
      RestartSec = 5;
      User = "john";
      Group = "users";
    };
    path = [pkgs.hyprland];
  };

  networking.firewall.allowedTCPPorts = [
    50051 # screen-control REST API (arch-configuration.nix:290, screen-control/src/main.rs:129)
    10250 # kubelet (k3s agent)
    18080 # monero p2p (monerod)
    5580 # matter-server (hostNetwork pod)
    179 # BGP (MetalLB speaker)
  ];
  networking.firewall.allowedUDPPorts = [
    5540 # matter-server (hostNetwork pod)
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 30000;
      to = 32767;
    } # Kubernetes NodePort range
  ];

  # NAS CIFS mounts live in ./modules/nas-mounts.nix (shared across workstations).

  # ollama disabled: CUDA build broken upstream (GCC ICE in ggml-cuda),
  # and arch GPU has <8GB VRAM — only gemma4 fits, never used in practice.
  # services.ollama = {
  #   package = pkgs.ollama-cuda;
  #   # Disk-constrained host: only gemma4 is auto-pulled. Don't run ollama-sync
  #   # here — it would mirror every model from the NAS and fill the SSD.
  #   modelNames = ["gemma4"];
  # };
  # vLLM disabled: GPU VRAM too small for the models we'd want to serve here.

  # Firewall enabled via shared-cli-configuration.nix.

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # ── NUT UPS monitoring ────────────────────────────────────────────
  # Desktop k3s node — notify-send, wall, k3s drain, then poweroff.
  # See modules/nut-ups.nix for the shared config.
  custom.nut-ups = {
    enable = false; # TODO: true once Goldenmate UPS arrives
    k3sDrain = true;
    desktopNotifications = true;
  };

  # ── Valve base station power management ───────────────────────────
  # No UPS on this host: after a power cut the PC and the stations reboot
  # together and the stations come up ON (firmware default). The boot timer
  # returns them to standby; the periodic leg covers units plugged in later.
  custom.basestation = {
    enable = true;
    standbyInterval = "30min";
  };
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11";
}
