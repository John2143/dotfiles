#!/usr/bin/env python3
"""Keep the GLKVM kiosk signed in.

The GLKVM UI authenticates with a browser-session cookie, so a Firefox restart
drops it and the kiosk sits on #/login. The admin password is already saved in
the Firefox profile and autofilled into #form_item_passwd, so the only missing
step is pressing "Log In".

This runs as a long-lived user service and checks once a minute: if the login
form is showing with a filled password it clicks Log In, otherwise it does
nothing. Because it never exits on a "not ready yet" condition, starting it can
never block a `nixos-rebuild switch` / home-manager activation.

Driven over Marionette (Firefox's built-in automation protocol, 127.0.0.1:2828)
rather than synthetic pointer events at fixed coordinates: it locates the
button in the DOM, so layout changes cannot break it.

Usage: glkvm-autologin.py [--once]
  (service mode) loop forever, checking every 60s
  --once  run one check and exit: 0 signed in / nothing to do, 1 needs attention
"""
import json
import socket
import sys
import time

PORT = 2828
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
INTERVAL = 60


def log(msg):
    print(f"glkvm-autologin: {msg}", flush=True)


class NeedsAttention(Exception):
    """Something only a human can fix (e.g. no saved password)."""


class Marionette:
    def __init__(self, sock):
        self.sock = sock
        self.msg_id = 0
        header = b""
        while b":" not in header:
            chunk = sock.recv(1)
            if not chunk:
                raise RuntimeError("marionette closed during handshake")
            header += chunk
        sock.recv(int(header[:-1]))

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def cmd(self, name, params=None, timeout=30):
        self.msg_id += 1
        payload = json.dumps([0, self.msg_id, name, params or {}]).encode()
        self.sock.sendall(str(len(payload)).encode() + b":" + payload)
        self.sock.settimeout(timeout)
        header = b""
        while b":" not in header:
            chunk = self.sock.recv(1)
            if not chunk:
                raise RuntimeError(f"marionette closed during {name}")
            header += chunk
        remaining = int(header[:-1])
        body = b""
        while len(body) < remaining:
            body += self.sock.recv(remaining - len(body))
        _, _, error, result = json.loads(body)
        if error:
            raise RuntimeError(f"{name}: {error.get('error')}: {error.get('message')}")
        return result

    def js(self, script, timeout=30):
        return self.cmd("WebDriver:ExecuteScript",
                        {"script": script, "args": []}, timeout)["value"]


PAGE_STATE = """
const pw = document.querySelector('#form_item_passwd');
const btn = [...document.querySelectorAll('button')]
  .find(b => (b.innerText || '').trim().toLowerCase() === 'log in');
return JSON.stringify({
  url: location.href,
  has_password: !!pw,
  password_filled: !!(pw && pw.value),
  has_button: !!btn,
  text: (document.body.innerText || '').slice(0, 120),
});
"""

TAG_BUTTON = """
const b = [...document.querySelectorAll('button')]
  .find(x => (x.innerText || '').trim().toLowerCase() === 'log in');
if (b) { b.id = 'glkvm-autologin-button'; }
return b ? 1 : 0;
"""


def session(timeout=10):
    """Connect and open a session, or return None when Firefox is not listening."""
    deadline = time.time() + timeout
    sock = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection(("127.0.0.1", PORT), 2)
            break
        except OSError:
            time.sleep(1)
    if sock is None:
        return None
    m = Marionette(sock)
    m.cmd("WebDriver:NewSession")
    return m


def check(m):
    """One decision pass. Returns 'signed_in', 'waiting' or 'logged_in'."""
    state = json.loads(m.js(PAGE_STATE))
    if not state["has_password"]:
        if state["url"] == "about:blank" or "/login" in state["url"]:
            return "waiting"
        return "signed_in"
    if not state["password_filled"]:
        raise NeedsAttention(
            "login form is showing but Firefox has no saved password to autofill")
    if not state["has_button"]:
        raise NeedsAttention("login form has no Log In button")
    if not int(m.js(TAG_BUTTON)):
        raise NeedsAttention("Log In button vanished before it could be clicked")
    element = m.cmd("WebDriver:FindElement",
                    {"using": "css selector", "value": "#glkvm-autologin-button"})
    # Marionette wraps element references: {"value": {<w3c-key>: "<uuid>"}}
    reference = element.get("value", element)
    m.cmd("WebDriver:ElementClick", {"id": reference[ELEMENT_KEY]})
    log("clicked Log In")
    deadline = time.time() + 30
    while time.time() < deadline:
        state = json.loads(m.js(PAGE_STATE))
        if not state["has_password"] and "/login" not in state["url"]:
            log(f"signed in ({state['url'][:60]})")
            return "logged_in"
        time.sleep(2)
    raise NeedsAttention(f"login did not complete; page shows {state['text']!r}")


def once():
    """One decision pass.

    Returns 'signed_in', 'logged_in', 'waiting' (page still loading) or
    'not_ready' (Firefox is not exposing Marionette yet).
    """
    m = session(timeout=5)
    if m is None:
        return "not_ready"
    try:
        return check(m)
    finally:
        m.close()


def main():
    oneshot = "--once" in sys.argv[1:]
    if not oneshot:
        log("watching for the GL-KVM login form")
    while True:
        try:
            result = once()
        except NeedsAttention as exc:
            log(f"needs attention: {exc}")
            result = "needs_attention"
        except (OSError, RuntimeError, ValueError) as exc:
            log(f"error, will retry: {exc}")
            result = "error"

        if oneshot:
            if result in ("signed_in", "logged_in"):
                log(f"ok ({result})")
                return 0
            if result == "not_ready":
                log("marionette not listening; is Firefox running with --marionette?")
            elif result == "waiting":
                log("login page not ready yet")
            return 1
        # service mode: 'not_ready' is the normal state before the browser starts
        time.sleep(INTERVAL)


if __name__ == "__main__":
    sys.exit(main())
