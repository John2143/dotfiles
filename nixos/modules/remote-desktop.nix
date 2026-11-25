# Remote desktop into this host with RustDesk, reachable only through SSH.
# Runbook: docs/remote-desktop.md. Imported by arch and office only.
#
# Non-obvious decisions:
# - ScreenCast AND RemoteDesktop both go to xdg-desktop-portal-luminous. The
#   Hyprland portal has no RemoteDesktop, and the portal frontend sends a
#   RemoteDesktop session's source selection to the ScreenCast backend, so both
#   must come from the same backend. InputCapture stays on Hyprland (Deskflow).
# - RustDesk runs as a plain in-session user service with no arguments, which
#   gives portal capture and portal input. Never run it with --server or
#   --service: that switches it to uinput, which needs its root service.
# - Monitor picker: luminous-autopick answers luminous's picker with the focused
#   monitor only after 30 s without physical input; at the desk, the person
#   there picks. When ~/.config/luminous-autopick/monitor names a connected
#   output, that monitor wins over focus, so the choice survives a reboot.
#   Luminous hands the portal exactly one monitor per session, so "all desktops
#   at once" is not possible with this backend.
# - SSH is the gate. RustDesk's whitelist is loopback only and the firewall
#   drops 21118 on every interface but lo, so the only way in is `rd <host>`
#   (an ssh -L tunnel with a pinned host key). Never widen the whitelist to the
#   tailnet: RustDesk's own login is a single, offline-crackable password.
# - The unused rendezvous, relay and API servers point at privileged loopback
#   ports purely so another local uid cannot squat them.
# - Policy is pinned before every start because RustDesk writes its own config
#   and its option setters (`rustdesk --option`) need root.
{
  lib,
  pkgs,
  ...
}: let
  luminous-autopick =
    pkgs.writers.writePython3Bin "luminous-autopick" {
      libraries = [];
      flakeIgnore = ["E501"];
    } ''
      """Answer xdg-desktop-portal-luminous's monitor picker when nobody is at the desk.

      luminous asks whoever listens on $XDG_RUNTIME_DIR/luminus_selector.sock instead
      of showing its own picker, but only while that file exists. This daemon creates
      the socket after IDLE_SECONDS without physical input and removes it on the next
      input, so at the desk luminous shows its normal picker and away from the desk
      a monitor is shared automatically. That monitor is the one named in PREF_PATH
      when it is set and still connected, otherwise the focused one, so a choice
      survives a reboot: fresh from a reboot nothing holds focus and Hyprland has
      settled on the first output, which is not necessarily the one used last time.
      """

      import json
      import os
      import selectors
      import signal
      import socket
      import struct
      import subprocess
      import sys
      import time

      LIBINPUT = "${pkgs.libinput.bin}/bin/libinput"
      STDBUF = "${pkgs.coreutils}/bin/stdbuf"
      HYPRCTL = "${pkgs.hyprland}/bin/hyprctl"
      IDLE_SECONDS = 30
      SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "luminus_selector.sock")
      PREF_PATH = os.path.join(
          os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
          "luminous-autopick",
          "monitor",
      )


      def log(msg):
          print(msg, flush=True)


      def remove_socket():
          try:
              os.unlink(SOCK_PATH)
          except FileNotFoundError:
              pass


      def open_socket():
          remove_socket()
          sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
          old = os.umask(0o177)
          try:
              sock.bind(SOCK_PATH)
          finally:
              os.umask(old)
          sock.listen(4)
          return sock


      def focused_index(monitors):
          try:
              out = subprocess.run([HYPRCTL, "monitors", "-j"], capture_output=True, timeout=2, check=True).stdout
              for mon in json.loads(out):
                  if mon.get("focused") and mon.get("name") in monitors:
                      return monitors.index(mon["name"])
          except Exception as err:
              log(f"hyprctl failed, using first monitor: {err}")
          return 0


      def preferred_index(monitors):
          """Return the index of the monitor named in PREF_PATH, if it is connected.

          One output name per file, nothing else in it. Re-read on every request so
          the choice can be changed without restarting the unit, and ignored when the
          named output is gone, so an unplugged monitor falls back to focus instead
          of failing the share.
          """
          try:
              with open(PREF_PATH, encoding="utf-8") as pref:
                  name = pref.read().strip()
          except OSError:
              return None
          if name in monitors:
              return monitors.index(name)
          log(f"{PREF_PATH} names {name!r}, not one of {monitors}; ignoring it")
          return None


      def chosen_index(monitors):
          idx = preferred_index(monitors)
          if idx is not None:
              log(f"pinned choice: {monitors[idx]}")
              return idx
          return focused_index(monitors)


      def recv_exact(conn, n):
          buf = b""
          while len(buf) < n:
              chunk = conn.recv(n - len(buf))
              if not chunk:
                  raise EOFError("peer closed")
              buf += chunk
          return buf


      def send(conn, obj):
          body = json.dumps(obj).encode()
          conn.sendall(struct.pack("=I", len(body)) + body)


      def answer(conn):
          with conn:
              conn.settimeout(2)
              (length,) = struct.unpack("=I", recv_exact(conn, 4))
              req = json.loads(recv_exact(conn, length))
              monitors = req.get("monitors") or []
              if req.get("type") != "screen_share" or not monitors:
                  send(conn, {"type": "cancel"})
                  return
              idx = chosen_index(monitors)
              log(f"auto-selected {monitors[idx]} from {monitors}")
              send(conn, {"type": "success", "index": idx})


      def on_term(signum, frame):
          raise SystemExit(0)


      def main():
          remove_socket()
          proc = subprocess.Popen([STDBUF, "-oL", LIBINPUT, "debug-events"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
          sel = selectors.DefaultSelector()
          sel.register(proc.stdout, selectors.EVENT_READ, "input")
          listener = None
          last_input = time.monotonic()
          signal.signal(signal.SIGTERM, on_term)
          signal.signal(signal.SIGINT, on_term)
          try:
              while True:
                  for key, _ in sel.select(timeout=1):
                      if key.data == "input":
                          if not os.read(proc.stdout.fileno(), 65536):
                              sys.exit("libinput debug-events exited; leaving the picker interactive")
                          last_input = time.monotonic()
                      else:
                          conn, _ = listener.accept()
                          try:
                              answer(conn)
                          except Exception as err:
                              log(f"request failed: {err}")
                  idle = time.monotonic() - last_input >= IDLE_SECONDS
                  if idle and listener is None:
                      listener = open_socket()
                      sel.register(listener, selectors.EVENT_READ, "socket")
                      log("idle: answering the picker automatically")
                  elif not idle and listener is not None:
                      sel.unregister(listener)
                      listener.close()
                      remove_socket()
                      listener = None
                      log("input seen: picker is interactive")
          finally:
              if listener is not None:
                  listener.close()
              remove_socket()
              proc.terminate()


      main()
    '';

  rustdesk-pin-options =
    pkgs.writers.writePython3Bin "rustdesk-pin-options" {
      libraries = [pkgs.python3Packages.tomli-w];
      flakeIgnore = ["E501"];
    } ''
      """Pin RustDesk's connection policy before every start.

      Connection policy is Config2 (RustDesk2.toml); the update check is a local
      option (RustDesk_local.toml). Both are rewritten here because RustDesk itself
      writes these files and they cannot be read-only store links.
      """

      import os
      import sys
      import tomllib
      from pathlib import Path

      import tomli_w

      # Config2 [options]; key names from libs/base/src/config/keys.rs.
      OPTIONS = {
          # Reachability: direct IP only, and only from this machine's loopback, so
          # the sole way in is an ssh -L tunnel. Empty means "allow every peer"
          # (src/server/connection.rs:1410-1437), so this value must never be empty.
          "direct-server": "Y",
          "direct-access-port": "21118",
          "whitelist": "127.0.0.1/32,::1/128",
          # Login: permanent password only, no approval dialog to accept.
          "approve-mode": "password",
          "verification-method": "use-permanent-password",
          "access-mode": "custom",
          # Anything that hands out more than a screen and an input device.
          "enable-terminal": "N",
          "enable-tunnel": "N",
          "enable-camera": "N",
          "enable-remote-restart": "N",
          "enable-record-session": "N",
          "enable-lan-discovery": "N",
          "allow-remote-config-modification": "N",
          # Kept: these are why RustDesk is used instead of a plain VNC server.
          "enable-keyboard": "Y",
          "enable-clipboard": "Y",
          "enable-file-transfer": "Y",
          "enable-file-copy-paste": "Y",
          "enable-audio": "Y",
          # A forgotten session must not stay unlocked forever.
          "allow-auto-disconnect": "Y",
          "auto-disconnect-timeout": "10",
          # Unused, but they must not answer on squattable ports: a local uid can bind
          # :21114 (an unauthenticated heartbeat rewrites options) or :21116 (a fake
          # RequestRelay overrides every enable-*=N). Ports under 1024 cannot be bound
          # by another uid.
          "custom-rendezvous-server": "127.0.0.1:9",
          "relay-server": "127.0.0.1:10",
          "api-server": "http://127.0.0.1:7",
      }

      # LocalConfig [options]: the update check is the only vendor contact left.
      LOCAL_OPTIONS = {
          "enable-check-update": "N",
      }


      def pin(path, values):
          data = tomllib.loads(path.read_text()) if path.exists() else {}
          options = data.setdefault("options", {})
          changed = {k: v for k, v in values.items() if options.get(k) != v}
          if not changed:
              return False
          options.update(changed)
          path.parent.mkdir(parents=True, exist_ok=True)
          tmp = path.with_name(path.name + ".tmp")
          tmp.write_text(tomli_w.dumps(data))
          os.replace(tmp, path)
          return True


      config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
      rustdesk = config_home / "rustdesk"
      config2 = rustdesk / "RustDesk2.toml"
      local = rustdesk / "RustDesk_local.toml"
      changed = [pin(path, values) for path, values in ((config2, OPTIONS), (local, LOCAL_OPTIONS))]
      if not any(changed):
          sys.exit(0)
      print(
          f"rustdesk: pinned {len(OPTIONS)} options in {config2} "
          f"and {len(LOCAL_OPTIONS)} in {local}"
      )
    '';
in {
  # Merges with the shared `hyprland` portal config (default=hyprland;gtk).
  xdg.portal = {
    extraPortals = [pkgs.xdg-desktop-portal-luminous];
    config.hyprland = {
      "org.freedesktop.impl.portal.ScreenCast" = "luminous";
      "org.freedesktop.impl.portal.RemoteDesktop" = "luminous";
    };
  };

  # RustDesk runs unsandboxed, so its portal app id is empty and luminous cannot
  # whitelist it; with the check on, every connection would wait on a dialog
  # nobody is there to click. Monitor choice stays gated by luminous-autopick.
  environment.etc."xdg/xdg-desktop-portal-luminous/config.toml".text = ''
    remote_permission_check = false
  '';

  # Fail-closed: a stale socket would make every screencast fail, so it is also
  # removed after the daemon stops.
  systemd.user.services.luminous-autopick = {
    description = "Answer luminous's monitor picker after 30 s without physical input";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    startLimitIntervalSec = 60;
    startLimitBurst = 5;
    serviceConfig = {
      ExecStart = "${luminous-autopick}/bin/luminous-autopick";
      ExecStopPost = "${pkgs.coreutils}/bin/rm -f %t/luminus_selector.sock";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  environment.systemPackages = [
    pkgs.rustdesk-flutter
    (import ../rustdesk-tunnel.nix {inherit pkgs;})
  ];

  # Restart=always: quitting from the tray must not leave the host unreachable
  # until the next login. A failed ExecStartPre (unparseable TOML) keeps RustDesk
  # from starting with an unknown policy.
  systemd.user.services.rustdesk = {
    description = "RustDesk in the Hyprland session (portal capture and input; never --server/--service)";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    startLimitIntervalSec = 60;
    startLimitBurst = 5;
    serviceConfig = {
      ExecStartPre = "${rustdesk-pin-options}/bin/rustdesk-pin-options";
      ExecStart = lib.getExe pkgs.rustdesk-flutter;
      # Settings → Security → Unlock runs `sudo /bin/sh -c …` via execvp
      # (src/platform/gtk_sudo.rs:468-534), and a systemd *service* gets the
      # stock service PATH, not the manager's: without this, execvp("sudo")
      # fails with ENOENT because sudo lives in /run/wrappers/bin, and the
      # permanent password cannot be set from the GUI at all. The CLI cannot
      # stand in: `rustdesk --password` goes through the service IPC daemon,
      # which this setup deliberately does not run.
      Environment = "PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.tmpfiles.rules = [
    # There is no root service. Owning the path as root means RustDesk's IPC
    # connect to it simply fails, and no other local uid can answer as the
    # service and inject options, password hash and key pair.
    "d /tmp/RustDesk-service 0711 root root -"
    "d /tmp/RustDesk-1000 0700 john users -"
  ];

  # RustDesk's direct listener binds [::]:21118 dual-stack and cannot be told to
  # bind loopback only (src/rendezvous_mediator.rs:1343-1412), so the port has to
  # be dropped for everything but the SSH tunnel on lo.
  #
  # The raw table, not the filter table: `-A INPUT -j ts-input` runs before the
  # nixos-fw jump, and Tailscale's own `ts-input -i tailscale0 -j ACCEPT` accepts
  # every tailnet packet first (verified on arch 2026-11-24: a nixos-fw DROP for
  # 21118 stayed at 0 packets while office connected). raw/PREROUTING is touched
  # by neither Tailscale nor k3s, so a drop there holds.
  networking.firewall.extraCommands = ''
    # -C first: this script runs on every firewall start, and raw/PREROUTING is
    # not flushed by NixOS, so a bare -I would stack duplicates.
    iptables -t raw -C PREROUTING -p tcp -m tcp --dport 21118 ! -i lo -j DROP 2>/dev/null ||
      iptables -t raw -I PREROUTING 1 -p tcp -m tcp --dport 21118 ! -i lo -j DROP
    ip6tables -t raw -C PREROUTING -p tcp -m tcp --dport 21118 ! -i lo -j DROP 2>/dev/null ||
      ip6tables -t raw -I PREROUTING 1 -p tcp -m tcp --dport 21118 ! -i lo -j DROP
  '';

  # extraCommands stay behind when the firewall is stopped; these chains are
  # flushed by NixOS, so remove ours by hand.
  networking.firewall.extraStopCommands = ''
    iptables -t raw -D PREROUTING -p tcp -m tcp --dport 21118 ! -i lo -j DROP 2>/dev/null || true
    ip6tables -t raw -D PREROUTING -p tcp -m tcp --dport 21118 ! -i lo -j DROP 2>/dev/null || true
  '';
}
