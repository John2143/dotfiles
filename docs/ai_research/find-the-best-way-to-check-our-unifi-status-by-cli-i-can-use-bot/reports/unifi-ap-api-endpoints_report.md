# UniFi Wireless AP API Endpoints — Research Report

## 1. Summary

The UniFi Network Application (v10.0.x) exposes a REST API that provides comprehensive wireless access point and client data through well-established endpoints that have survived the legacy UI removal in v10.0. For an AP-only deployment running in k3s, the most valuable endpoints are `/api/s/default/stat/device` (filtered to `type: "uap"`), `/api/s/default/stat/sta` (wireless clients), and `/api/s/default/stat/health` (site health summary). All three are read-only GET endpoints that require session authentication.

The `/stat/device` endpoint returns all UniFi devices (APs, switches, gateways) in a single JSON array, with each device carrying a `type` field (`"uap"` for access points). Each AP object contains radio configuration (`radio_table`), per-radio statistics (`radio_table_stats`), per-SSID virtual AP data (`vap_table`), system resource metrics (`sys_stats`, `system-stats`), and uplink status. This is the single richest source of AP state.

The `/stat/sta` endpoint returns all **active** wireless clients with per-client RF metrics: signal strength (RSSI and `signal` dBm), channel, radio band (`ng` / `na` / `6e`), protocol (`radio_proto`), TX/RX rates and byte counters, association time, and the AP MAC (`ap_mac`) they are connected to. This data is not available through `kubectl logs` — those logs contain controller application events, not live RF telemetry.

The `/stat/health` endpoint provides a site-level health summary including CPU/memory/load metrics for the controller itself, plus aggregate AP and client counts. The `/stat/rogueap` endpoint returns neighboring APs detected by your APs' radios. The `/rest/wlanconf` endpoint provides CRUD access to WLAN (SSID) configuration.

Authentication uses a cookie+CSRF token flow: POST credentials to `/api/login` (or `/api/auth/login` on UDM/UCG), extract the `unifises` session cookie and `X-CSRF-Token` header from the response, then include both in all subsequent requests. On UDM-class controllers, all API paths are prefixed with `/proxy/network`. For a self-hosted controller in k3s, the standard paths (`/api/s/default/stat/…`) apply directly without the proxy prefix.

## 2. Relation to Primary Question

These endpoints collectively provide the complete wireless telemetry surface: which APs are online and healthy (`/stat/device` filtered to `uap`), which clients are connected and at what signal quality (`/stat/sta`), what WLANs are configured (`/rest/wlanconf`), and what rogue APs are visible (`/stat/rogueap`). Together they answer the core CLI query use case — "show me my APs and their clients" — with data that no log-based approach can provide.

## 3. Source Evaluation

### Source 1: Ubiquiti Community Wiki — UniFi Controller API
- **URL:** https://ubntwiki.com/products/software/unifi-controller/api
- **Credibility:** Secondary source. Community-maintained reverse-engineering documentation based on browser captures, JAR dumps, and review of open-source tools. Not official, but extensively cross-referenced by the UniFi automation community. Provides endpoint inventories, authentication flows, and curl examples. No single owner; maintained collaboratively.
- **Weighting:** High for endpoint discovery and authentication patterns; moderate for field-level accuracy (some fields may be version-specific). Weighted highly because it is the most complete single reference and is validated by production tools (unpoller, unifi-exporter, Ansible modules).

### Source 2: unpoller/unifi Go Library (GitHub)
- **URL:** https://github.com/unpoller/unifi
- **Credibility:** Secondary source. Production-grade open-source Go library (146 stars, MIT-licensed) that parses UniFi controller API responses into typed Go structs. The struct definitions (`uap.go`, `clients.go`, `usg.go`) are effectively a field-level schema for the JSON API. Maintained by the unpoller organization; actively updated (last push May 2026). Used by the UniFi Poller monitoring tool in production deployments.
- **Weighting:** High for field names, types, and JSON tags. The struct definitions represent API responses observed from real controllers. The library's `path()` function documents UDM vs. self-hosted path differences and v10.x `/proxy/network` prefix handling. This is the single most authoritative technical source for response schemas.

### Source 3: Ubiquiti Community — UniFi Network Application 10.0.160 Release
- **URL:** https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced
- **Credibility:** Primary source. Official release announcement from Ubiquiti on their community forum. Confirms that the legacy UI is removed but does not explicitly state whether legacy API endpoints are removed. A community comment asking about `/api/s/<site>/stat/sta` preservation went unanswered in the visible thread, creating ambiguity.
- **Weighting:** High for authoritative release information; limited for API endpoint specifics (the release notes focus on new Official Network API additions, not legacy endpoint status). The unanswered community question about endpoint preservation is a notable gap. However, independent verification from unpoller (which works on 10.x) and the community wiki confirms these endpoints remain functional in 10.0.x.

### Source 4: Ubiquiti Help Center — Getting Started with the Official UniFi API
- **URL:** https://help.ui.com/hc/en-us/articles/30076656117655
- **Credibility:** Primary source. Official Ubiquiti documentation. Directs users to the UniFi Developer Portal (developer.ui.com) and to the in-application API docs at _UniFi Network > Integrations_. The article is high-level and does not enumerate specific endpoints, but it establishes the official API framework and confirms the existence of local application APIs for Network, listing device data, client activity, and traffic insights as available capabilities.
- **Weighting:** Moderate. Authoritative on the existence and official status of the API, but thin on implementation details. The reference to in-application documentation (Integrations tab) is the official path for version-specific endpoint docs.

### Source 5: enuno/unifi-mcp-server (GitHub)
- **URL:** https://github.com/enuno/unifi-mcp-server
- **Credibility:** Secondary source. Active open-source Python MCP server (137 stars, Apache 2.0) implementing the UniFi API. The README documents three API modes (Local Gateway, Cloud EA, Cloud V1) and confirms the `/proxy/network` prefix behavior for local gateway access. The project claims 1,236 passing tests and v10.x compatibility fixes, providing evidence that the stat endpoints remain functional in current versions.
- **Weighting:** Moderate. Valuable for confirming real-world API behavior in 2026 and for documenting UDM/self-hosted path differences, but the field-level detail comes from unpoller's struct definitions.

### Source 6: Web search results — aggregate knowledge
- Various web search summaries aggregated field descriptions from multiple community sources (Reddit, Stack Overflow, gists, forums). These were used only to cross-reference and confirm findings already established by the primary and secondary sources above. No single search result is cited as a standalone authority.
- **Weighting:** Low. Used for corroboration only.

## 4. Conclusions

### 4.1 Recommended Endpoints for AP-Only Monitoring

For a k3s-hosted UniFi Network Application 10.0.162 with only wireless APs:

| Priority | Endpoint | What It Provides |
|----------|----------|------------------|
| **P0** | `GET /api/s/default/stat/device` | Full AP state: online/offline, firmware, uptime, CPU/memory, radio config, per-radio channel/utilization, per-SSID client counts and traffic, uplink speed/errors |
| **P0** | `GET /api/s/default/stat/sta` | Every active wireless client: MAC, IP, hostname, signal/RSSI, channel, band, PHY rate, TX/RX bytes, connected AP, association duration |
| **P1** | `GET /api/s/default/stat/health` | Controller health (CPU/mem/load/uptime), total/offline AP counts, total client count |
| **P2** | `GET /api/s/default/rest/wlanconf` | SSID configuration: name, enabled, security type, band, VLAN, guest policy |
| **P2** | `GET /api/s/default/stat/rogueap` | Neighboring APs: ESSID, BSSID, channel, signal, security, rogue status |

### 4.2 Authentication Mechanism (v10.x, Self-Hosted)

For a self-hosted controller in k3s (NOT a UDM/UCG appliance):

1. **Obtain session:**
   ```bash
   curl -k -X POST \
     --data '{"username":"admin","password":"YOUR_PASS"}' \
     --header 'Content-Type: application/json' \
     -c cookie.txt \
     https://CONTROLLER_IP:8443/api/login
   ```
   The response JSON includes a `csrf_token` field. Also extract the `X-CSRF-Token` response header.

2. **Use session for all subsequent requests:**
   ```bash
   CSRF=$(curl -k -s -X POST \
     --data '{"username":"admin","password":"YOUR_PASS"}' \
     --header 'Content-Type: application/json' \
     -c cookie.txt \
     https://CONTROLLER_IP:8443/api/login | jq -r '.csrf_token // empty')
   
   curl -k -X GET \
     -b cookie.txt \
     --header "X-CSRF-Token: $CSRF" \
     https://CONTROLLER_IP:8443/api/s/default/stat/device
   ```

**Important:** On UDM/UDM Pro/UCG appliances, the login path is `/api/auth/login` and all API paths require the `/proxy/network` prefix (e.g., `/proxy/network/api/s/default/stat/device`). For a self-hosted k3s deployment, the standard paths without `/proxy/network` apply, but verify by checking the `/status` endpoint first — if it reports a UDM-class device, the proxy prefix may be required depending on the UniFi OS version underlying the container.

### 4.3 Data NOT Available via kubectl Logs

`kubectl logs` on the UniFi Network Application pod reveals:
- Application-level events (adoption, provisioning, upgrades, alerts)
- MongoDB queries and connection status
- Java exceptions and stack traces
- Inform messages from devices

The following data is **only** available through the REST API, not logs:

- **RF telemetry:** Client RSSI, signal strength in dBm, noise floor, channel utilization, TX/RX PHY rates, retry counts, MCS index, spatial streams
- **Per-radio state:** Which channel each radio is on, TX power, channel width (HT20/40/80/160), DFS status
- **Per-SSID client counts and traffic:** How many clients per WLAN, per-WLAN byte/packet counters
- **Client association metadata:** BSSID (specific radio MAC), association time, 802.11r/k/v capabilities
- **Rogue AP detection:** Neighboring BSSIDs with signal strength, security type, and channel
- **Client satisfaction scores:** UniFi's computed experience score per client and per AP
- **WLAN configuration:** The live SSID, security, VLAN, and band steering settings

### 4.4 v10.x-Specific Changes

The v10.0 release did **not** remove the legacy `/api/s/{site}/stat/…` endpoints, despite removing the legacy web UI. This is confirmed by:

1. The unpoller library's continued function with 10.x controllers (its `APIDevicePath` constant remains `/api/s/%s/stat/device`).
2. The enuno/unifi-mcp-server project's v10.x compatibility fixes in its 0.2.5 release.
3. The Ubiquiti community wiki, updated to v10.0.156, which still documents all stat endpoints.

**What was added in 10.0.x:**
- Official Integration API at `/proxy/network/integration/v1/` with API key authentication
- New v2 endpoints: `/v2/api/site/{site}/clients/history`, `/v2/api/site/{site}/aggregated-dashboard`, `/v2/api/site/{site}/traffic`
- Device adoption and VLAN management through the new official API

**What was removed:**
- Legacy Web UI (confirmed in release notes)
- Some deprecated endpoint variants (e.g., `stat/device-basic` reported removed by some community sources, though this is not explicitly confirmed in the release notes — the unpoller library does not reference this endpoint)

### 4.5 Quick CLI Queries — jq Filters

**List all APs with name, model, status, and client count:**
```bash
curl -k -s -b cookie.txt --header "X-CSRF-Token: $CSRF" \
  https://controller:8443/api/s/default/stat/device | \
  jq '[.data[] | select(.type == "uap")] | .[] | {
    name: .name,
    model: .model,
    state: .state,
    version: .version,
    uptime: .uptime,
    clients: .num_sta,
    ip: .ip
  }'
```

**List all wireless clients with signal strength and connected AP:**
```bash
curl -k -s -b cookie.txt --header "X-CSRF-Token: $CSRF" \
  https://controller:8443/api/s/default/stat/sta | \
  jq '[.data[] | select(.is_wired == false)] | .[] | {
    hostname: (.hostname // .name // .mac),
    ip: .ip,
    mac: .mac,
    essid: .essid,
    signal: .signal,
    rssi: .rssi,
    channel: .channel,
    radio: .radio,
    proto: .radio_proto,
    tx_rate: .tx_rate,
    rx_rate: .rx_rate,
    ap: .ap_mac,
    uptime: .uptime
  }'
```

**Quick health summary:**
```bash
curl -k -s -b cookie.txt --header "X-CSRF-Token: $CSRF" \
  https://controller:8443/api/s/default/stat/health | \
  jq '.data[0] | {
    status: .status,
    num_ap: .num_ap,
    num_disconnected: .num_disconnected,
    num_sta: .num_sta,
    cpu: .system_stats.cpu,
    mem: .system_stats.mem,
    uptime: .system_stats.uptime
  }'
```

**List rogue APs sorted by signal strength:**
```bash
curl -k -s -b cookie.txt --header "X-CSRF-Token: $CSRF" \
  https://controller:8443/api/s/default/stat/rogueap | \
  jq '[.data[]] | sort_by(.signal) | reverse | .[] | {
    essid: .essid,
    bssid: .bssid,
    channel: .channel,
    signal: .signal,
    security: .security,
    is_rogue: .is_rogue
  }'
```

**List WLAN (SSID) configuration:**
```bash
curl -k -s -b cookie.txt --header "X-CSRF-Token: $CSRF" \
  https://controller:8443/api/s/default/rest/wlanconf | \
  jq '.data[] | {
    name: .name,
    enabled: .enabled,
    security: .security,
    wlangroup_id: .wlangroup_id,
    is_guest: .is_guest,
    band: .radio
  }'
```

### 4.6 Known Gaps and Caveats

1. **Unified response wrapper:** All endpoints return `{"data": […], "meta": {"rc": "ok"}}`. The `meta.rc` field is `"ok"` on success or contains an error code like `"api.err.LoginRequired"`. Always check `meta.rc` before accessing `data`.

2. **State field interpretation:** The `state` field on devices uses numeric codes. From community documentation: `1` = online, `0` = offline/disconnected, `2` = pending adoption. Verify exact values for your controller version.

3. **UDM vs. self-hosted path differences:** The unpoller library's `path()` method documents the logic: if the controller reports itself as "new" (UDM/UCG), login goes to `/api/auth/login` and all API paths are prefixed with `/proxy/network`. For self-hosted k3s, the standard paths should work, but test with both `/api/s/default/stat/device` and `/proxy/network/api/s/default/stat/device` if the first returns 404.

4. **No official endpoint deprecation list for 10.x:** The Ubiquiti release notes do not enumerate removed endpoints. Community reports suggest `stat/device-basic` may have been removed in 10.x, but this endpoint is not needed for AP monitoring (use `stat/device` with a `type == "uap"` filter instead).

5. **SSL/TLS verification:** The controller uses a self-signed certificate by default. All curl examples above use `-k` to skip verification. For production scripts, pin the certificate or use a CA-signed cert.

6. **Session expiration:** Sessions expire after a period of controller inactivity (typically 30 minutes). For long-running scripts, either re-authenticate periodically or use the `remember=true` parameter in the login payload.

## 5. Bibliography

Ubiquiti Community Wiki contributors. (n.d.). *UniFi Controller API*. Ubiquiti Community Wiki. https://ubntwiki.com/products/software/unifi-controller/api

unpoller. (2026). *unifi: Go Library (w/ structures) to grab data from a Ubiquiti UniFi Controller* (Version master). GitHub. https://github.com/unpoller/unifi

Ubiquiti Inc. (2025). *UniFi Network Application 10.0.160*. Ubiquiti Community Releases. https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced

Ubiquiti Inc. (n.d.). *Getting Started with the Official UniFi API*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API

enuno. (2026). *unifi-mcp-server: An MCP server that leverages official UniFi API* (Version 0.2.5). GitHub. https://github.com/enuno/unifi-mcp-server
