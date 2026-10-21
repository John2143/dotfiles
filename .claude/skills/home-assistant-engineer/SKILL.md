---
description: Home Assistant — querying state, history and devices over the API or from inside the pod, diagnosing entity/device confusion, Matter specifics
argument-hint: (none — invoked as skill://home-assistant-engineer)
allowed-tools: Bash(curl *), Bash(ssh *), Read, Search
tool-hints: |
  Read-only. The `aiuser` account is in the read-only group: it can read entities and nothing else.
  Never print the credential and never put a token on a command line — use a header file.
  Never write to /config/.storage while Home Assistant is running, and open the SQLite database
  with mode=ro. Do not restart the pod or reload integrations without approval.
---

# Home Assistant

Home Assistant runs in the home cluster: namespace `default`, Deployment `home-assistant`, config on
a Longhorn volume at `/config`, portal `https://home.ts.2143.me`.

## Access

**API (preferred for state and history).** Account `aiuser`, credentials in agenix as
`/run/agenix/ha-aiuser` (`HA_USERNAME=…`, `HA_PASSWORD=…`). Mint a short-lived token per session —
there is deliberately no permanent token:

```
POST /auth/login_flow                     client_id + handler ["homeassistant", null]
POST /auth/login_flow/<flow_id>           {"client_id": …, "username": …, "password": …} → result = code
POST /auth/token                          grant_type=authorization_code&code=…&client_id=…
```

Tokens last ~30 minutes. Put one in a file and pass it as `-H @file` so it never appears in `ps` or
shell history.

**Files (when the API is not enough).** No credentials needed — read through the cluster:

```
ssh closet 'kubectl -n default exec deploy/home-assistant -- python -' < script.py
```

## The privilege boundary

The read-only group is `{"entities": {"all": {"read": true}}}`. That means: read states and history,
**no** service calls, no control, no editing, and **no config entries** — integration settings are
invisible to this account. Anything that needs an integration's configuration is an owner task.

## What to use for what

| Question | Path |
|---|---|
| Current state, attributes | `GET /api/states`, `/api/states/<entity_id>` |
| History / trends | `GET /api/history/period/<iso8601>?filter_entity_id=<id>&minimal_response` |
| Derived values | `POST /api/template` with `{"template": "…"}` |
| Device/entity/area registries, integrations | `.storage/core.*_registry` from inside the pod |
| Long-term numeric history, thresholds | `/config/home-assistant_v2.db` opened `mode=ro` |

The registries are the truth for *identity*; the database is the truth for *what happened*. State
objects alone will not tell you which integration created a device.

## Matter

Home Assistant keys a Matter device by **(fabric id, node id)** — both appear in the device
identifier as `deviceid_<fabric>-<node>-MatterNodeDevice`. Re-pairing a device after a controller
fabric change therefore creates a *second* device entry, and node ids restart at 1 per fabric, so
old and new entries often share a node number. Devices that expose a serial number get merged into
one entry carrying several identifiers.

A device that is listed but cannot be controlled is usually a stale record, not a broken device.
Controller-side detail and the restore runbook: `argo/docs/matter-server.md`.

## Units

This instance reports Fahrenheit. Sensor values are already in the configured unit — convert when
comparing with a vendor tool that reports Celsius, and never relabel one as the other.

## Safety

- Read-only account; do not promote it.
- Do not restart the pod or reload integrations without approval — a Matter controller restart is
  user-visible.
- `.storage` files are rewritten by Home Assistant; a concurrent edit corrupts configuration.
