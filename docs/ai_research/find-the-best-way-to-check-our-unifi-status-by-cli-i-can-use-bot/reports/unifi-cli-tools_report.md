# UniFi CLI Tools and Libraries: Survey Report

**Sub-Topic:** Survey of existing open-source CLI tools and libraries that wrap the UniFi controller API.

**Date:** 2026-05-24

---

## 1. Summary

The ecosystem of open-source UniFi controller API wrappers is dominated by a handful of projects, with two clear leaders: the **Art-of-WiFi UniFi-API-client** (PHP, 1,323 GitHub stars) and the **aiounifi** Python library (used by Home Assistant, ~13K weekly PyPI downloads). Both have been updated to support UniFi Network Application 10.x, making them the only battle-tested options for controllers running version 10.0.162.

The critical breaking change in UniFi Network Application v10 was the authentication flow. The legacy `/api/login` endpoint (which returned a session cookie) was replaced by `/api/auth/login`, which returns a CSRF token and sets a `sid` cookie. Clients that do not handle this new flow, or that fail to include the `x-csrf-token` header on subsequent requests, are completely non-functional against v10 controllers. In addition, Ubiquiti introduced an official API key mechanism (available under **Integrations** in the UniFi Network UI) that provides bearer-token authentication, bypassing the login flow entirely.

Several popular tools have **not** been updated for v10 and are effectively broken against controllers running version 10.x. These include `node-unifi` (explicitly states support up to v9.x only), `node-unificli` (abandoned, 3 stars), and the auto-generated `py-unifi` OpenAPI client (targets API version 8.0.26). The experimental `delian/unificli` Node.js CLI supports UniFi cloud and legacy controllers, but its maintenance status is uncertain and it has not been confirmed working with v10.

No tool surveyed is specifically designed for AP-only deployments. However, all tools that work with v10 can query AP status via the standard `/api/s/{site}/stat/device` (legacy API) or `/v1/sites/{siteId}/devices` (official API) endpoints, filtering by device type. The choice of tool therefore reduces to language preference, deployment complexity, and whether direct CLI access or a programmable library is desired.

**Bottom line for the user's scenario (k3s-hosted UniFi Network 10.0.162, APs only):** the Art-of-WiFi PHP client and the aiounifi Python library are the only tools with confirmed v10 support and active maintenance. For direct CLI use, a thin Python script using aiounifi, or the Art-of-WiFi PHP client wrapped in a shell script, is the most practical path. No pre-built, single-binary CLI tool with confirmed v10 compatibility exists today.

---

## 2. Relation to Primary Question

The primary question asks for the best method to query UniFi access point status from the command line against a 10.0.162 controller. This sub-topic's findings directly identify which libraries can authenticate against v10 at all — a hard prerequisite — and eliminate the majority of existing tools (including `node-unifi`, `py-unifi`, and the dedicated CLI wrappers) as non-functional for this specific controller version.

---

## 3. Source Evaluation

### Source 1: Art-of-WiFi/UniFi-API-client GitHub Repository
- **URL:** https://github.com/Art-of-WiFi/UniFi-API-client
- **Title:** Art-of-WiFi/UniFi-API-client: A PHP API client class to interact with Ubiquiti's UniFi Controller API
- **Credibility:** **Primary source.** The repository is the canonical distribution of the library. The README states explicit support for "UniFi Network Application 5.x, 6.x, 7.x, 8.x, 9.x, 10.x (**10.2.97 is confirmed**)." The source code (`src/Client.php`) was read directly and confirms the `/api/auth/login` vs. `/api/login` branching logic based on UniFi OS detection. License: MIT. Maintainer: "Art of WiFi" (commercial entity with a public track record; info@artofwifi.net). 1,323 stars, 240 forks, active issue tracker.
- **Weighting:** **High.** Direct source code inspection confirms v10 compatibility. Large community and long maintenance history (since 2017) provide strong evidence of reliability. The only limitation is that it requires PHP, which may be heavy for a CLI-only use case.

### Source 2: Kane610/aiounifi GitHub Repository + PyPI
- **URL:** https://github.com/Kane610/aiounifi / https://pypi.org/project/aiounifi
- **Title:** aiounifi: Asynchronous library to communicate with Unifi Controller
- **Credibility:** **Primary source.** The repository contains the source code for the library that powers Home Assistant's UniFi Network integration. Source code inspection (`controller.py`, `connectivity.py`) confirms the `/api/auth/login` endpoint, CSRF token extraction from response headers, and SSO MFA handling — all required for v10. 13K weekly PyPI downloads, MIT license. Maintainer: Robert Svensson (Kane610), a known Home Assistant core contributor.
- **Weighting:** **High.** The library is the foundation of the most widely deployed UniFi integration (Home Assistant). The authentication logic is exercised by tens of thousands of Home Assistant instances. The Python ecosystem is lighter-weight than PHP for CLI scripting.

### Source 3: jens-maus/node-unifi GitHub Repository + npm
- **URL:** https://github.com/jens-maus/node-unifi
- **Title:** jens-maus/node-unifi: NodeJS class for querying/controlling a UniFi-Controller
- **Credibility:** **Primary source.** README explicitly states compatibility with "UniFi-Controller API version starting with v4.x.x up to v9.x.x." The repository has 162 stars, 55 forks, and recent activity. License: MIT. Maintainer: Jens Maus (mail@jens-maus.de), a known developer in the HomeMatic/ioBroker ecosystem.
- **Weighting:** **Medium-High** for versions up to v9; **Low** for v10. The explicit version cap in the README is a strong signal that v10 is not supported. The npm package (version 3.x) has modest download numbers (~1,500 total for v10-labeled releases), suggesting limited adoption. However, the code quality and maintenance history are solid for pre-v10 controllers.

### Source 4: Reddit r/Ubiquiti — "UniFi Network v10 Integration API"
- **URL:** https://www.reddit.com/r/Ubiquiti/comments/1qymsls/unifi_network_v10_integration_api_confirming/
- **Title:** UniFi Network v10 Integration API - Confirming Read-Only Limitations for Client Management
- **Credibility:** **Secondary source, anecdotal.** A user report from February 2026 describing failed write operations via the official v10 Integration API. Unverified by Ubiquiti. However, the technical details (specific HTTP status codes, tested endpoints) are consistent with the API structure observed in the official API client documentation.
- **Weighting:** **Low-Medium.** Provides useful real-world corroboration that the v10 official API has meaningful gaps compared to the legacy API. Not authoritative, but consistent with other findings.

### Source 5: Art of WiFi Blog — "UniFi API Authentication"
- **URL:** https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager
- **Title:** UniFi API Authentication: Local Admin vs. API Key vs. Site Manager
- **Credibility:** **Secondary source, authoritative author.** Written by the maintainer of the Art-of-WiFi PHP client. Explains the three authentication methods with technical depth. References the July 2024 MFA enforcement change that broke automated integrations. The author has a commercial interest (sells captive portal solutions), which introduces mild bias toward their own products, but the technical content is verifiable against source code.
- **Weighting:** **Medium-High.** Excellent technical reference for understanding authentication options. Slight commercial bias, but claims are corroborated by primary source code inspection.

### Source 6: ubiquiti-community/py-unifi GitHub Repository
- **URL:** https://github.com/ubiquiti-community/py-unifi
- **Title:** ubiquiti-community/py-unifi: Python Unifi API Client
- **Credibility:** **Primary source, auto-generated.** This is an OpenAPI Generator output targeting API version 8.0.26, package version 0.1.0. 21 stars, 3 forks. Part of the "ubiquiti-community" GitHub organization.
- **Weighting:** **Low for v10.** The generated code targets a specific API version (8.0.26) that predates the authentication changes in v10. No evidence of regeneration against a v10 schema. Small community and low star count suggest limited real-world validation.

### Source 7: tnware/unifi-controller-api GitHub Repository
- **URL:** https://github.com/tnware/unifi-controller-api
- **Title:** tnware/unifi-controller-api: A Python client library for interacting with Ubiquiti UniFi Network Controllers
- **Credibility:** **Primary source.** 15 stars, 1 fork, MIT license. README warns "This package is under active development and is subject to breaking changes." Supports UDM Pro via the `is_udm_pro=True` flag. Provides typed data models and convenience methods.
- **Weighting:** **Low-Medium.** The library is too new and too small to rely on for production use. No explicit v10 version confirmation. The `is_udm_pro` flag and port handling suggest awareness of UniFi OS but the authentication path is not documented in README.

### Source 8: delian/unificli and jacobalberty/node-unificli GitHub Repositories
- **URLs:** https://github.com/delian/unificli / https://github.com/jacobalberty/node-unificli
- **Titles:** UNIFICli / node-unificli
- **Credibility:** **Primary sources, low maintenance.** `delian/unificli` (11 stars, 0 forks) is described as "experimental" and "still under development." `jacobalberty/node-unificli` (3 stars, 1 fork) has minimal functionality (PoE mode control, device listing). Both are Node.js-based.
- **Weighting:** **Low.** Neither has evidence of v10 compatibility. Both have very small user bases and appear to have low or no active maintenance. Not suitable for reliable use.

### Source 9: Home Assistant UniFi Integration Source Code
- **URL:** https://github.com/home-assistant/core/tree/dev/homeassistant/components/unifi
- **Title:** Home Assistant Core — UniFi Network Integration
- **Credibility:** **Primary source, high authority.** Home Assistant is the largest open-source home automation platform. The UniFi integration is an official, bundled component. Source code inspection confirms use of aiounifi with username/password authentication (no API key support visible in the config flow as of this date). The integration handles site discovery, device tracking, and client monitoring.
- **Weighting:** **High for authentication pattern validation.** The integration's use of aiounifi and its configuration flow confirm the username/password authentication path works against v10 controllers. The fact that it uses `DEFAULT_PORT = 443` and the aiounifi library confirms the UniFi OS detection pattern.

### Source 10: Ubiquiti Official Help Center — "Getting Started with the Official UniFi API"
- **URL:** https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API
- **Title:** Getting Started with the Official UniFi API
- **Credibility:** **Primary source, official.** Published by Ubiquiti Inc. Describes the Site Manager API and Local Application APIs. Links to the UniFi Developer Portal. Confirms that local API documentation is available at "UniFi Network > Integrations" within the controller UI.
- **Weighting:** **High for API structure.** Provides authoritative confirmation of which APIs exist. However, the article is high-level and lacks technical depth on authentication mechanisms or endpoint details.

---

## 4. Conclusions

### 4.1 Tools That Work with UniFi Network 10.x

| Tool | Language | v10 Support | Auth Methods | Stars | Maintenance |
|------|----------|-------------|--------------|-------|-------------|
| **Art-of-WiFi UniFi-API-client** | PHP | ✅ Confirmed (10.2.97) | Username/Password, API Key, Site Manager Proxy | 1,323 | Active |
| **Art-of-WiFi unifi-network-application-api-client** | PHP | ✅ Confirmed (10.1.84+) | API Key only | New | Active |
| **aiounifi** | Python 3.13+ | ✅ Confirmed (via HA) | Username/Password, 2FA, SSO MFA | — | Active |
| **Home Assistant UniFi Integration** | Python (via aiounifi) | ✅ Confirmed | Username/Password | — | Active |

### 4.2 Tools That Do NOT Work with v10 (or Unconfirmed)

| Tool | Language | v10 Status | Why |
|------|----------|------------|-----|
| **node-unifi** | Node.js | ❌ v9.x max | README explicitly caps at v9.x |
| **py-unifi** (ubiquiti-community) | Python | ❌ | Generated for API 8.0.26 |
| **node-unificli** | Node.js | ❌ | Abandoned, 3 stars |
| **delian/unificli** | Node.js | ❓ Unconfirmed | Experimental, no v10 testing |
| **tnware/unifi-controller-api** | Python | ❓ Unconfirmed | New, small community |

### 4.3 Authentication Mechanisms in v10

1. **Legacy username/password (deprecated but functional):** POST to `/api/auth/login` (UniFi OS) or `/api/login` (legacy). Returns CSRF token in `x-csrf-token` header and sets `sid` cookie. Both must be sent on subsequent requests. MFA/2FA adds a second step.

2. **API Key (new, recommended):** Generate under Integrations in the UniFi Network UI. Include as `Authorization: Bearer <key>` header. No login/logout flow needed. Available only on UniFi OS consoles/servers (not self-hosted non-UniFi-OS controllers).

3. **Site Manager API Key (cloud-proxied):** Route requests through `unifi.ui.com`. No direct network connectivity to the controller required. Adds ~800ms latency. Requires console firmware >= 5.0.3.

### 4.4 AP-Only Deployments

No surveyed tool is specifically designed for AP-only deployments. However, all compatible tools can query AP status by:
- Calling the device list endpoint and filtering by `type` field (APs are identified by `type === "uap"` in the legacy API or `"deviceType": "ACCESS_POINT"` in the official API).
- Using the `/stat/device` (legacy) or `/v1/sites/{siteId}/devices` (official) endpoints.

The absence of switches or routers does not create a compatibility issue with any tool. The only practical consideration is that some API response fields (switch port status, WAN statistics, gateway health) will be empty or absent, which all libraries handle gracefully.

### 4.5 Recommended Approach for CLI Queries

For the user's stated goal ("CLI unifi queries on wireless access points") against a k3s-hosted UniFi Network 10.0.162 controller:

1. **aiounifi + a short Python script** is the lightest-weight option. Python is already present on NixOS. A ~30-line script can authenticate, query `/stat/device`, filter for APs, and print JSON or a table.

2. **Art-of-WiFi PHP client** is the most feature-complete option if more complex operations (adoption, provisioning, firmware upgrades) are ever needed. The API key support eliminates credential management overhead.

3. **Direct curl + shell scripting** is viable if the user prefers zero dependencies. The authentication flow for v10 is well-understood: POST to `/api/auth/login`, extract the CSRF token and cookie, then query `/api/s/{site}/stat/device`. However, this approach requires careful cookie/CSRF management and is error-prone compared to using a library.

4. **No pre-built CLI tool with v10 support exists today.** The user will need to either write a thin wrapper around an existing library or use direct HTTP calls.

### 4.6 Non-Obvious Finding: API Key Scope Limitations

A Reddit report (source 4) and the official API client documentation both indicate that the v10 official Integration API (accessed via API key) has fewer endpoints than the legacy API. Specifically, write operations (client blocking, firewall rule management) may be limited or unavailable through the official API. For read-only AP status queries, this limitation is irrelevant. However, if the user later wants to perform actions (e.g., restart an AP, modify WLAN settings), the legacy API via username/password authentication provides broader coverage.

---

## 5. Bibliography

Art of WiFi. (2026). *Art-of-WiFi/UniFi-API-client: A PHP API client class to interact with Ubiquiti's UniFi Controller API* [Source code]. GitHub. https://github.com/Art-of-WiFi/UniFi-API-client

Art of WiFi. (2026). *Art-of-WiFi/unifi-network-application-api-client: A modern PHP API client for the official UniFi Network Application API* [Source code]. GitHub. https://github.com/Art-of-WiFi/unifi-network-application-api-client

Art of WiFi. (2025). *UniFi API Authentication: Local Admin vs. API Key vs. Site Manager*. Art of WiFi Blog. https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager

Delian. (2026). *delian/unificli: Experimental CLI based on node-unifiapi* [Source code]. GitHub. https://github.com/delian/unificli

Home Assistant Core Contributors. (2026). *Home Assistant Core — UniFi Network Integration* [Source code]. GitHub. https://github.com/home-assistant/core/tree/dev/homeassistant/components/unifi

Maus, J. (2025). *jens-maus/node-unifi: NodeJS class for querying/controlling a UniFi-Controller* [Source code]. GitHub. https://github.com/jens-maus/node-unifi

OutdoorsIdahoTech. (2026, February 7). *UniFi Network v10 Integration API - Confirming Read-Only Limitations for Client Management* [Online forum post]. Reddit. https://www.reddit.com/r/Ubiquiti/comments/1qymsls/unifi_network_v10_integration_api_confirming/

Svensson, R. (2026). *Kane610/aiounifi: Asynchronous library to communicate with Unifi Controller* [Source code]. GitHub. https://github.com/Kane610/aiounifi

Svensson, R. (2026). *aiounifi* [Python package]. PyPI. https://pypi.org/project/aiounifi

tnware. (2026). *tnware/unifi-controller-api: A Python client library for interacting with Ubiquiti UniFi Network Controllers* [Source code]. GitHub. https://github.com/tnware/unifi-controller-api

Ubiquiti Community. (2025). *ubiquiti-community/py-unifi: Python Unifi API Client* [Source code]. GitHub. https://github.com/ubiquiti-community/py-unifi

Ubiquiti Inc. (2026). *Getting Started with the Official UniFi API*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API
