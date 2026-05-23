{
  config,
  lib,
  pkgs,
  ...
}:
let
  teamspeak-mute-proxy = pkgs.writers.writePython3Bin "teamspeak-mute-proxy"
    { libraries = []; }
    ''
    """TeamSpeak 3 ClientQuery proxy daemon.

    Maintains one persistent connection, serves many clients.
    """

    import os
    import sys
    import socket
    import json
    import time
    import signal
    import select
    import re
    import struct

    SOCK_PATH = os.path.join(
        os.environ.get(
            "XDG_RUNTIME_DIR", os.path.expanduser("~/.cache")
        ),
        "ts3query-proxy.sock",
    )
    TS3_HOST = "127.0.0.1"
    TS3_PORT = 25639
    _INI_BASE = (
        "$HOME/.var/app/com.teamspeak.TeamSpeak3"
        "/.ts3client/clientquery.ini"
    )
    INIFILE_CANDIDATES = [
        os.path.expandvars(_INI_BASE),
        os.path.expandvars("$HOME/.ts3client/clientquery.ini"),
        "/home/john/.var/app/com.teamspeak.TeamSpeak3"
        "/.ts3client/clientquery.ini",
    ]

    DISCONNECTED_JSON = json.dumps({
        "text": "\uf130  \u2b1c",
        "class": "disconnected", "alt": "disconnected",
        "tooltip": "TeamSpeak not connected to a server",
    })
    MUTED_JSON = json.dumps({
        "text": "\uf130  \U0001f534",
        "class": "muted", "alt": "muted",
        "tooltip": "Mic Muted (click to unmute)",
    })
    UNMUTED_JSON = json.dumps({
        "text": "\uf130  \U0001f7e2",
        "class": "unmuted", "alt": "unmuted",
        "tooltip": "Mic Active (click to mute)",
    })


    def read_apikey():
        for path in INIFILE_CANDIDATES:
            try:
                with open(path) as f:
                    for line in f:
                        if line.startswith("api_key="):
                            return line.split("=", 1)[1].strip()
            except (OSError, IOError):
                continue
        return None


    def ts3_connect():
        """Connect to TS3 ClientQuery, auth, return (sock, clid)."""
        apikey = read_apikey()
        if not apikey:
            print("No API key found", file=sys.stderr, flush=True)
            return None, None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.setsockopt(
                socket.SOL_SOCKET, socket.SO_LINGER,
                struct.pack('ii', 1, 0),
            )
            sock.connect((TS3_HOST, TS3_PORT))
            # Read banner
            data = b""
            sock.settimeout(2)
            while True:
                try:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if b"\n\r" in data:
                        break
                except socket.timeout:
                    break
            # Auth
            sock.sendall(f"auth apikey={apikey}\n".encode())
            time.sleep(0.1)
            auth_resp = b""
            try:
                while True:
                    sock.settimeout(1)
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    auth_resp += chunk
                    if b"error id=" in auth_resp:
                        break
            except socket.timeout:
                pass
            if b"error id=0" not in auth_resp:
                msg = auth_resp.decode(errors="replace").strip()
                print(
                    f"Auth failed: {msg}",
                    file=sys.stderr, flush=True,
                )
                sock.close()
                return None, None
            # Get clid
            sock.sendall(b"whoami\n")
            time.sleep(0.1)
            whoami = b""
            try:
                while True:
                    sock.settimeout(1)
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    whoami += chunk
                    if b"error id=" in whoami:
                        break
            except socket.timeout:
                pass
            for line in whoami.decode(errors="replace").split("\n"):
                if line.startswith("clid="):
                    clid = line.split("=")[1].split()[0]
                    sock.settimeout(5)
                    print(
                        f"Connected to TS3 ClientQuery,"
                        f" clid={clid}",
                        file=sys.stderr, flush=True,
                    )
                    return sock, clid
            sock.close()
            return None, None
        except Exception as e:
            print(
                f"TS3 connection failed: {e}",
                file=sys.stderr, flush=True,
            )
            return None, None


    def ts3_cmd(sock, cmd):
        """Send a command, return response text."""
        try:
            sock.sendall(f"{cmd}\n".encode())
            resp = b""
            sock.settimeout(2)
            while True:
                try:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    resp += chunk
                    if b"error id=" in resp:
                        break
                except socket.timeout:
                    break
            return resp.decode(errors="replace")
        except Exception:
            return "error id=1 msg=connection_lost"


    def handle_request(sock, clid, cmd):
        """Handle a client command, return (response, connection_ok)."""
        if cmd == "status":
            if clid is None:
                return DISCONNECTED_JSON, True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_input_muted",
            )
            if "connection_lost" in resp:
                return DISCONNECTED_JSON, False
            m = re.search(r"client_input_muted=(\d+)", resp)
            muted = m.group(1) if m else "0"
            if muted == "1":
                return MUTED_JSON, True
            return UNMUTED_JSON, True
        elif cmd == "toggle":
            if clid is None:
                return "", True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_input_muted",
            )
            if "connection_lost" in resp:
                return "", False
            m = re.search(r"client_input_muted=(\d+)", resp)
            cur = m.group(1) if m else "0"
            new = "0" if cur == "1" else "1"
            ts3_cmd(sock, f"clientupdate client_input_muted={new}")
            return "", True
        elif cmd == "toggle-output":
            if clid is None:
                return "", True
            resp = ts3_cmd(
                sock,
                f"clientvariable clid={clid} client_output_muted",
            )
            if "connection_lost" in resp:
                return "", False
            m = re.search(r"client_output_muted=(\d+)", resp)
            cur = m.group(1) if m else "0"
            new = "0" if cur == "1" else "1"
            ts3_cmd(sock, f"clientupdate client_output_muted={new}")
            return "", True
        else:
            return "", True


    def main():
        if os.path.exists(SOCK_PATH):
            try:
                os.unlink(SOCK_PATH)
            except OSError:
                pass

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCK_PATH)
        server.listen(5)
        os.chmod(SOCK_PATH, 0o600)
        server.setblocking(False)

        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

        print(
            f"Proxy listening on {SOCK_PATH}",
            file=sys.stderr, flush=True,
        )

        ts3_sock = None
        clid = None
        last_attempt = 0.0

        while True:
            now = time.time()
            if ts3_sock is None and now - last_attempt >= 5:
                last_attempt = now
                ts3_sock, clid = ts3_connect()

            try:
                readable, _, _ = select.select(
                    [server], [], [], 1.0,
                )
            except (select.error, ValueError, InterruptedError):
                continue

            if server in readable:
                try:
                    client, _ = server.accept()
                    raw = client.recv(1024)
                    data = raw.decode(errors="replace").strip()
                    if data:
                        result, ok = handle_request(
                            ts3_sock, clid, data,
                        )
                        if not ok:
                            try:
                                ts3_sock.close()
                            except Exception:
                                pass
                            ts3_sock = None
                            clid = None
                        if result:
                            client.sendall(result.encode())
                    client.close()
                except Exception as e:
                    print(
                        f"Client error: {e}",
                        file=sys.stderr, flush=True,
                    )

            # Health-check TS3 connection via MSG_PEEK
            if ts3_sock is not None:
                try:
                    ts3_sock.setblocking(False)
                    try:
                        ts3_sock.recv(1, socket.MSG_PEEK)
                    except BlockingIOError:
                        pass
                except (
                    ConnectionResetError,
                    BrokenPipeError,
                    OSError,
                ) as e:
                    print(
                        f"TS3 connection lost: {e}",
                        file=sys.stderr, flush=True,
                    )
                    try:
                        ts3_sock.close()
                    except Exception:
                        pass
                    ts3_sock = None
                    clid = None
                finally:
                    ts3_sock and ts3_sock.setblocking(True)
                    ts3_sock and ts3_sock.settimeout(5)


    if __name__ == "__main__":
        main()
    '';

  teamspeak-mute-status = pkgs.writeShellApplication {
    name = "teamspeak-mute-status";
    runtimeInputs = [ pkgs.libressl.nc ];
    text = ''
      SOCK="$XDG_RUNTIME_DIR/ts3query-proxy.sock"
      if [ "''${1:-}" = "--toggle" ]; then
        printf '%s\n' "toggle" | nc -UN -w 2 "$SOCK" > /dev/null 2>&1 || true
      elif [ "''${1:-}" = "--toggle-output" ]; then
        printf '%s\n' "toggle-output" | nc -UN -w 2 "$SOCK" > /dev/null 2>&1 || true
      else
        RESULT=$(printf '%s\n' "status" | nc -UN -w 2 "$SOCK" 2>/dev/null)
        if [ -n "$RESULT" ]; then
          printf '%s\n' "$RESULT"
        else
          echo '{"text": "  ⬜", "class": "disconnected", "alt": "disconnected", "tooltip": "TeamSpeak not connected to a server"}'
        fi
      fi
    '';
  };
in {
  environment.systemPackages = [
    teamspeak-mute-status
    teamspeak-mute-proxy
  ];

  systemd.user.services.teamspeak-mute-proxy = {
    description = "TeamSpeak 3 ClientQuery proxy daemon";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    requisite = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${teamspeak-mute-proxy}/bin/teamspeak-mute-proxy";
      Restart = "on-failure";
      RestartSec = 5;
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
