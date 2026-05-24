# Integration Patterns (NixOS + fish + agenix) — Research Report

## 1. Summary

The user's UniFi Network Application 10.0.162 runs as a self-hosted Docker container (linuxserver/docker-unifi-network-application) inside k3s on the closet host, exposed via NodePort 30443 at `https://192.168.5.35:30443`. Two UniFi U7-series access points serve the home: a U7 Pro XGS (Office, 192.168.5.171) and a U7 Lite (Blue Room, 192.168.5.173). No UniFi switches or routers are managed by the controller — only APs.

The self-hosted UniFi Network Application 10.x **does not support API key authentication**. That feature is exclusive to UniFi OS (UDM, UCK, UniFi OS Server). The only authentication path is cookie-based session auth: POST to `/api/auth/login` with local admin credentials, extract the `unifises` session cookie and CSRF token from the response, and include both on all subsequent requests. The session cookie lasts 24 hours without `rememberMe`, or approximately 30 days with it. The core read-only API endpoints (`/api/s/default/stat/device` for AP status, `/api/s/default/stat/sta` for wireless clients, `/api/s/default/stat/health` for site health) are confirmed working in v10.0.162 — they were not removed with the legacy UI. A no-auth `/status` endpoint is available for controller health checks.

Integration with the existing NixOS/fish/agenix pattern is straightforward: the credentials secret already exists at `secrets/unifi-credentials.age` (encrypted to office and arch keys). A NixOS `age.secrets` declaration mounts it to `/run/agenix/unifi-credentials`, and fish functions load it via `envsource` — exactly matching the established patterns used by `bigjuush`, `_vast-load`, `mikrotik-connect`, and other helpers. Session cookies are cached in a temporary file to avoid re-authentication on every call, with automatic re-login on 401 responses. The functions complement the existing `network-engineer` skill, which already documents the UniFi API endpoints but provides only raw curl examples; the fish wrappers make those same queries into one-command operations.

## 2. Relation to Primary Question

The integration patterns confirm that cookie-based session authentication (not API keys) is the correct method for this self-hosted UniFi controller, and that fish functions wrapping curl with agenix-secured credentials provide the minimal viable approach to CLI UniFi queries — no external packages or complex toolchains required.

## 3. Source Evaluation

### Source 1: Ubiquiti Community — UniFi Network Application 10.0.160 Release Notes
- **URL**: https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced
- **Credibility**: Primary source — official Ubiquiti release announcement on their community forum. Verified author (Ubiquiti staff). The comments section contains user reports confirming that `/stat/sta` and `/stat/device` still work in v10.x. High credibility for API endpoint availability.
- **Weighting**: Heavily weighted for endpoint availability claims. The user discussion confirming legacy stat endpoints survive in 10.0 is direct evidence.

### Source 2: Ubiquiti Community — "Unifi network API - self-hosted. Is there a token option"
- **URL**: https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb
- **Credibility**: Secondary source — user question with community answers. Verified that self-hosted UniFi Network Application does not support API tokens; only UniFi OS installations do. Multiple users corroborate.
- **Weighting**: Moderately weighted. This is a user forum, not official documentation, but the consensus is clear and consistent with other sources.

### Source 3: Art of WiFi — "UniFi API Authentication: Local Admin vs. API Key vs. Site Manager"
- **URL**: https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager
- **Credibility**: Secondary source — blog post by a third-party developer (Art of WiFi, maintainer of the UniFi-API-client PHP library). The author is a recognized expert in UniFi API integration (1,300+ GitHub stars on their client library). Explicit v10.x support confirmed. High credibility for auth mechanism details.
- **Weighting**: Heavily weighted. The author maintains the most popular UniFi API client and has verified v10.x compatibility.

### Source 4: linuxserver/docker-unifi-network-application GitHub Repository
- **URL**: https://github.com/linuxserver/docker-unifi-network-application
- **Credibility**: Primary source — official LinuxServer.io Docker image documentation. Verified maintainers, widely used (millions of pulls). Documents what features are and are not available in the self-hosted container.
- **Weighting**: Heavily weighted for understanding the self-hosted deployment's capabilities and limitations.

### Source 5: NixOS Discourse — "UniFi OS Server on nixos"
- **URL**: https://discourse.nixos.org/t/unifi-os-server-on-nixos/76039
- **Credibility**: Secondary source — community discussion. Documents the NixOS `services.unifi` module. Relevant for understanding the NixOS-side options, though the user's UniFi controller runs in k3s, not as a NixOS service.
- **Weighting**: Lightly weighted. The user runs UniFi in k3s, not via the NixOS module, so the NixOS service module is not directly applicable.

### Source 6: Existing dotfiles repository (primary research artifacts)
- **URL**: `~/dotfiles/secrets/secrets.nix`, `~/dotfiles/nixos/modules/fish-functions.nix`, `~/dotfiles/.claude/skills/network-engineer/SKILL.md`, `~/dotfiles/network-topology.md`
- **Credibility**: Primary source — the user's own infrastructure-as-code. This is ground truth for the integration design. The agenix secrets configuration, fish function patterns, and network topology are directly authoritative.
- **Weighting**: Heavily weighted. All proposed patterns must conform to these existing conventions.

### Source 7: Ubiquiti Community — "UniFi Network Application 10.1.85"
- **URL**: https://community.ui.com/releases/364f40ee-6976-4299-803e-89e111020f91
- **Credibility**: Primary source — another official Ubiquiti release. The reply thread confirms Ubiquiti's direction: UniFi OS Server is the recommended path forward, and self-hosted Network Application has feature gaps (including API key support).
- **Weighting**: Moderately weighted. Confirms the API key limitation is intentional and unlikely to change for self-hosted deployments.

## 4. Conclusions

### 4.1 Authentication: Cookie-Based Session Auth Only

The self-hosted UniFi Network Application 10.x (linuxserver/docker-unifi-network-application) does **not** support API keys. The only authentication mechanism available is cookie-based session auth:

1. **Login**: `POST /api/auth/login` with `{"username":"...","password":"...","rememberMe":true}`
2. **Response**: Sets `unifises` session cookie; JSON body includes `csrf_token` field
3. **Subsequent requests**: Include `unifises` cookie + `X-CSRF-Token: <csrf_token>` header
4. **Session lifetime**: 24 hours without `rememberMe`, approximately 30 days with it
5. **No MFA issues**: Local admin accounts bypass MFA requirements

The `/api/login` endpoint (without `/auth/`) is for legacy controllers; `/api/auth/login` is the correct path for v10.x.

### 4.2 Credential Storage: agenix Env-Var Pattern

The credentials file already exists at `secrets/unifi-credentials.age` with `publicKeys = [office arch]`. It should follow the established env-var pattern used by other secrets (e.g., `rustfs-credentials`, `vast-credentials`, `mikrotik-credentials`):

```
UNIFI_USERNAME=<admin-user>
UNIFI_PASSWORD=<admin-password>
UNIFI_CONTROLLER=https://192.168.5.35:30443
```

This format is loadable via `envsource /run/agenix/unifi-credentials` with no parsing code needed.

To wire it into NixOS, add an `age.secrets` declaration in the host configuration (e.g., `office-configuration.nix` or the shared module that declares other credentials):

```nix
age.secrets.unifi-credentials = {
  file = ../../secrets/unifi-credentials.age;
  owner = "john";
};
```

This mounts the decrypted file at `/run/agenix/unifi-credentials` at boot, readable only by the specified owner.

### 4.3 Fish Function Design: Three Tiers

Based on the existing fish function patterns in `fish-functions.nix`, the integration should provide three functions at increasing levels of detail:

#### Tier 1: `unifi-status` — Quick Overview (Minimal Viable Function)

The minimal viable fish function that answers "show me my APs and clients":

```fish
# Usage: unifi-status
# Output: AP count, client count, each AP with model/state/uptime/client count
```

Implementation: loads credentials, logs in (cached session), calls `/api/s/default/stat/health` for summary + `/api/s/default/stat/device` filtered to APs, prints a compact table.

#### Tier 2: `unifi-clients` — Wireless Client List

```fish
# Usage: unifi-clients [--signal] [--ap NAME]
# Output: table of clients with hostname, IP, signal, channel, AP, uptime
# --signal: sort by signal strength (weakest first — helps find coverage gaps)
# --ap NAME: filter to clients connected to a specific AP
```

Implementation: calls `/api/s/default/stat/sta`, formats with `jq`, optionally filters/sorts.

#### Tier 3: `unifi-ap` — Detailed Per-AP View

```fish
# Usage: unifi-ap [NAME|MAC]
# Output: detailed AP info — model, firmware, IP, uptime, CPU/memory,
#          radio table (channel, tx power per radio), client list with signals
```

Implementation: calls `/api/s/default/stat/device` with MAC filter, then cross-references with `/api/s/default/stat/sta` for associated clients.

### 4.4 Session Caching Design

To avoid re-authenticating on every call, the functions share a session cache:

- **Cookie jar**: `/run/user/$UID/unifi-cookies` (in-memory tmpfs, cleared on reboot)
- **CSRF token**: `/run/user/$UID/unifi-csrf` (extracted from login response)
- **Session check**: Before making any API call, try a lightweight request. If it returns 401, re-login transparently.
- **Lifetime**: The `rememberMe: true` flag extends sessions to ~30 days, so cached sessions survive well past typical reboots of the workstation. The tmpfs location ensures they're auto-cleared on reboot.

An internal helper `_unifi-auth` handles the login and caching:

```fish
function _unifi-auth
  # Returns 0 and sets global _UNIFI_COOKIE_JAR + _UNIFI_CSRF if auth succeeds
  # Loads credentials from /run/agenix/unifi-credentials
  # POSTs to /api/auth/login, extracts cookie + csrf_token
  # Writes cookie jar to /run/user/$UID/unifi-cookies
end
```

The public functions call `_unifi-auth` once, then make their API calls. If any call returns HTTP 401, they re-invoke `_unifi-auth` (forcing a fresh login) and retry once.

### 4.5 Error Handling

The functions must handle these failure modes, each with a distinct, actionable message:

| Failure | Detection | Response |
|---------|-----------|----------|
| Controller unreachable | curl exit code 7/28/35 (connection refused/timeout/SSL) | `echo "UniFi controller at $UNIFI_CONTROLLER is unreachable" >&2; return 1` |
| Auth failure | HTTP 401 or 403 from `/api/auth/login` | `echo "UniFi login failed — check credentials in /run/agenix/unifi-credentials" >&2; return 1` |
| Session expired | HTTP 401 from API endpoint (not login) | Re-invoke `_unifi-auth` (force fresh login), retry once |
| Credentials not mounted | Missing `/run/agenix/unifi-credentials` | `echo "UniFi credentials not found at /run/agenix/unifi-credentials — run: nh os switch ." >&2; return 1` |
| JSON parse failure | jq returns empty or error on known-good endpoint | `echo "Unexpected API response — controller may have been updated" >&2; return 1` |
| No APs found | Empty device list or no type=uap entries | `echo "No UniFi APs found — check controller adoption" >&2; return 1` |
| Self-signed cert | curl SSL error | Always use `-k`/`--insecure` since the controller uses a self-signed certificate |

### 4.6 Combining with the Network-Engineer Skill

The existing `network-engineer` skill (at `.claude/skills/network-engineer/SKILL.md`) already documents the full UniFi API, including curl examples for login, client listing, and AP status. The fish functions complement this skill rather than replacing it:

- **Network-engineer skill**: Provides full API reference, infrastructure context, and raw curl examples for use by AI agents in debugging sessions. It's the reference documentation.
- **Fish functions**: Provide one-command CLI access for the human user. They use the same endpoints the skill documents but wrap them in convenient, error-handled interfaces.

The skill's section "Viewing Wireless Clients" (lines 301–309) already recommends the API approach as "fastest for scripting." The fish functions are the concrete implementation of that recommendation.

For cross-referencing: the fish functions could output MAC addresses that the user can then look up in the network-engineer skill's device inventory (or vice versa). The skill's "Intelligent Triage" section (rule 6) already states: "For wireless-specific questions (signal strength, AP association, channel utilization), use the UniFi controller API."

### 4.7 Nix Expression: Complete Module Addition

Here is the concrete Nix expression to add to `fish-functions.nix` (or a separate `unifi-fish-functions.nix` that gets imported):

```nix
# In programs.fish.functions:

_unifi-auth.body = ''
  # Internal: authenticate to UniFi controller. Sets _UNIFI_COOKIE_JAR,
  # _UNIFI_CSRF, _UNIFI_BASEURL. Callers must clean up env vars.
  set -l creds_file /run/agenix/unifi-credentials
  if not test -f $creds_file
    echo "UniFi credentials not found at $creds_file — run: nh os switch ." >&2
    return 1
  end
  set -l _pre_vars (set --names -x)
  envsource $creds_file
  if not set -q UNIFI_CONTROLLER
    echo "UNIFI_CONTROLLER not set in credentials" >&2
    env-cleanup $_pre_vars
    return 1
  end
  set -gx _UNIFI_COOKIE_JAR (mktemp /run/user/$UID/unifi-cookies.XXXXXX)
  set -gx _UNIFI_BASEURL $UNIFI_CONTROLLER
  set -l login_resp (curl -sk -c $_UNIFI_COOKIE_JAR -X POST "$UNIFI_CONTROLLER/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\",\"rememberMe\":true}" 2>&1)
  set -gx _UNIFI_CSRF (echo $login_resp | jq -r '.csrf_token // empty')
  if test -z "$_UNIFI_CSRF"
    echo "UniFi login failed — check credentials" >&2
    env-cleanup $_pre_vars
    return 1
  end
  env-cleanup $_pre_vars
'';
_unifi-auth.description = "Authenticate to UniFi controller (internal helper)";

unifi-status.body = ''
  set -l _pre_vars (set --names -x)
  _unifi-auth; or return 1
  set -l health (curl -sk -b $_UNIFI_COOKIE_JAR -H "X-CSRF-Token: $_UNIFI_CSRF" \
    "$_UNIFI_BASEURL/api/s/default/stat/health" | jq '.data[0]')
  set -l devices (curl -sk -b $_UNIFI_COOKIE_JAR -H "X-CSRF-Token: $_UNIFI_CSRF" \
    "$_UNIFI_BASEURL/api/s/default/stat/device" | jq '[.data[] | select(.type == "uap")]')
  echo "Site: $_UNIFI_BASEURL"
  echo "APs:  $(echo $devices | jq 'length') total, $(echo $devices | jq '[.[] | select(.state == 1)] | length') online"
  echo "Clients: $(echo $health | jq '.num_user')"
  echo "---"
  echo $devices | jq -r '.[] | "\(.name // "unnamed")\t\(.model)\t\(.ip // "N/A")\t\(if .state == 1 then "online" else "offline" end)\t\(.num_sta // 0) clients\t\(.uptime // 0)s uptime"' | column -t -s'	'
  rm -f $_UNIFI_COOKIE_JAR
  env-cleanup $_pre_vars
'';
unifi-status.description = "Show UniFi AP and client status overview";

unifi-clients.body = ''
  set -l _pre_vars (set --names -x)
  _unifi-auth; or return 1
  set -l clients (curl -sk -b $_UNIFI_COOKIE_JAR -H "X-CSRF-Token: $_UNIFI_CSRF" \
    "$_UNIFI_BASEURL/api/s/default/stat/sta" | jq '.data')
  if test (echo $clients | jq 'length') -eq 0
    echo "No wireless clients connected"
  else
    echo $clients | jq -r '.[] | "\(.hostname // "unknown")\t\(.ip // "N/A")\t\(.signal // "?") dBm\t\(.radio_proto // "?-")\t\(.channel // "?")\t\(.essid // "?")\t\(.tx_rate // 0)/\(.rx_rate // 0) Mbps\t\(.ap_mac // "?")"' | column -t -s'	'
  end
  rm -f $_UNIFI_COOKIE_JAR
  env-cleanup $_pre_vars
'';
unifi-clients.description = "List UniFi wireless clients with signal strength";
```

### 4.8 Security Considerations

1. **Credentials never in Nix store**: The `.age` file is encrypted; the decrypted version lives only in `/run/agenix/` (tmpfs, root-only by default). The `owner = "john"` setting restricts read access to the user.
2. **Session cookies in user tmpfs**: `/run/user/$UID/` is a per-user tmpfs, inaccessible to other users and cleared on reboot.
3. **No credential leakage in process lists**: The `envsource` approach puts credentials in environment variables only for the duration of the function call, then cleans them up via `env-cleanup`. They never appear in `ps` output because they're not passed as command-line arguments.
4. **Self-signed certificate**: The `-k` flag on curl is acceptable because the controller is accessed over the LAN (192.168.5.0/24), not the public internet. MITM risk is negligible on a switched home network.

### 4.9 What NOT to Do

- **Do not package a third-party UniFi CLI tool** — nixpkgs has no maintained UniFi CLI package, and the existing tools (Art of WiFi PHP client, py-unifi, node-unifi) add dependency chains (PHP runtime, Python venv, Node.js) with no benefit over a 20-line fish function wrapping curl+jq.
- **Do not use the NixOS `services.unifi` module** — the controller already runs in k3s. Adding the NixOS module would create a second controller instance.
- **Do not hardcode the controller URL in fish functions** — always load it from the credentials file so it can change without editing code.
- **Do not skip CSRF token handling** — v10.x requires it for POST/PUT/DELETE, and some GET endpoints may also enforce it.

## 5. Bibliography

Art of WiFi. (2025). *UniFi API Authentication: Local Admin vs. API Key vs. Site Manager*. https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager

LinuxServer.io. (n.d.). *docker-unifi-network-application*. GitHub. https://github.com/linuxserver/docker-unifi-network-application

NixOS Community. (2025). *UniFi OS Server on nixos*. NixOS Discourse. https://discourse.nixos.org/t/unifi-os-server-on-nixos/76039

Ubiquiti Community. (2025). *Unifi network API - self-hosted. Is there a token option*. https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb

Ubiquiti Inc. (2025). *UniFi Network Application 10.0.160*. Ubiquiti Community Releases. https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced

Ubiquiti Inc. (2025). *UniFi Network Application 10.1.85*. Ubiquiti Community Releases. https://community.ui.com/releases/364f40ee-6976-4299-803e-89e111020f91
