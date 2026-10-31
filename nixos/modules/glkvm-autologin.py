#!/usr/bin/env python3
"""Log the GLKVM kiosk back in after a Firefox restart.

The GLKVM UI keeps its session in a browser-session cookie, so every Firefox
restart drops it and the kiosk sits on #/login. The admin password is already
saved in the Firefox profile and autofilled into #form_item_passwd, so all
this has to do is press the "Log In" button.

Driven over Marionette (Firefox's built-in automation protocol, 127.0.0.1:2828)
rather than synthetic mouse events at fixed coordinates, so it survives layout
changes. Exits 0 when logged in or already logged in, 1 on failure.
"""
import json
import socket
import sys
import time

PORT = 2828
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
LOGIN_URL = "https://glkvm.ts.2143.me/"


def log(msg):
    print(f"glkvm-autologin: {msg}", flush=True)


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


def connect(timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            return socket.create_connection(("127.0.0.1", PORT), 2)
        except OSError:
            time.sleep(2)
    return None


def main():
    sock = connect(180)
    if sock is None:
        log("marionette unreachable; is Firefox running with --marionette?")
        return 1
    m = Marionette(sock)
    m.cmd("WebDriver:NewSession")

    deadline = time.time() + 120
    while time.time() < deadline:
        state = json.loads(m.js(PAGE_STATE))
        if not state["has_password"]:
            if state["url"] != "about:blank" and "/login" not in state["url"]:
                log(f"already signed in ({state['url'][:60]})")
                return 0
            time.sleep(3)
            continue
        if not state["password_filled"]:
            log("password field is empty: Firefox did not autofill, cannot sign in")
            return 1
        if not state["has_button"]:
            log("Log In button not found")
            return 1
        m.js("""
const b = [...document.querySelectorAll('button')]
  .find(x => (x.innerText || '').trim().toLowerCase() === 'log in');
if (b) { b.id = 'glkvm-autologin-button'; }
return b ? 1 : 0;
""")
        element = m.cmd("WebDriver:FindElement",
                        {"using": "css selector", "value": "#glkvm-autologin-button"})
        # Marionette wraps the element reference: {"value": {<w3c-key>: "<uuid>"}}
        reference = element.get("value", element)
        m.cmd("WebDriver:ElementClick", {"id": reference[ELEMENT_KEY]})
        log("clicked Log In")

        deadline = time.time() + 30
        while time.time() < deadline:
            state = json.loads(m.js(PAGE_STATE))
            if not state["has_password"] and "/login" not in state["url"]:
                log(f"signed in ({state['url'][:60]})")
                return 0
            time.sleep(2)
        log(f"login did not complete; page shows: {state['text']!r}")
        return 1

    log("timed out waiting for the login form")
    return 1


if __name__ == "__main__":
    sys.exit(main())
