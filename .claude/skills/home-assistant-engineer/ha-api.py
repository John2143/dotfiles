#!/usr/bin/env python3
"""Home Assistant API helper for the home-assistant-engineer skill.

Mints a 30-minute token from /run/agenix/ha-aiuser (no password in argv, no
permanent token) and prints the response as JSON.

  ha-api.py GET /api/states
  ha-api.py GET /api/states/sensor.foo
  ha-api.py history sensor.foo 6        # last 6 hours, minimal_response
  ha-api.py GET /api/config

Read-only accounts get 401 on /api/template and /api/error_log; compute derived
values client-side instead.
"""
import datetime
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("HA_BASE", "https://home.ts.2143.me")
CRED = "/run/agenix/ha-aiuser"


def credentials():
    if not os.path.exists(CRED):
        sys.exit("no credential at %s - has agenix been activated?" % CRED)
    values = {}
    with open(CRED) as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"')
    return values["HA_USERNAME"], values["HA_PASSWORD"]


def login():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    user, password = credentials()
    client = BASE + "/"

    def post(path, payload):
        request = urllib.request.Request(
            BASE + path,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        return json.load(urllib.request.urlopen(request, context=ctx, timeout=20))

    flow = post("/auth/login_flow", {
        "client_id": client,
        "handler": ["homeassistant", None],
        "redirect_uri": client,
    })
    code = post("/auth/login_flow/" + flow["flow_id"], {
        "client_id": client,
        "username": user,
        "password": password,
    })["result"]
    body = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "client_id": client,
    }).encode()
    request = urllib.request.Request(BASE + "/auth/token", data=body)
    return ctx, json.load(urllib.request.urlopen(request, context=ctx, timeout=20))["access_token"]


def call(method, path, payload=None):
    ctx, token = login()
    request = urllib.request.Request(
        BASE + path,
        method=method,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        data=json.dumps(payload).encode() if payload is not None else None,
    )
    try:
        response = urllib.request.urlopen(request, context=ctx, timeout=30)
    except urllib.error.HTTPError as exc:
        sys.exit("HTTP %s %s for %s %s" % (exc.code, exc.reason, method, path))
    raw = response.read().decode()
    try:
        print(json.dumps(json.loads(raw), indent=2))
    except ValueError:
        print(raw)


args = sys.argv[1:]
if not args:
    sys.exit(__doc__)
if args[0] == "history":
    if len(args) < 2:
        sys.exit("usage: ha-api.py history <entity_id> [hours]")
    hours = float(args[2]) if len(args) > 2 else 6
    start = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
    call("GET", "/api/history/period/%s?filter_entity_id=%s&minimal_response"
         % (start.strftime("%Y-%m-%dT%H:%M:%S+00:00"), args[1]))
else:
    method = args[0].upper()
    call(method,
         args[1] if len(args) > 1 else "/api/",
         json.loads(args[2]) if len(args) > 2 else None)
