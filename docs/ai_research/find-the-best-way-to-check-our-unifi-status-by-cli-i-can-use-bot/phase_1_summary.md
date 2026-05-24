# Phase 1 Summary

## Primary Question
What is the best method to query UniFi wireless access point status from the command line, given a UniFi Network Application 10.0.162 controller running in k3s with only APs (no UniFi switches or routers), and what is the correct authentication mechanism?

## Sub-Topic Findings

### UniFi REST API Authentication (v10.x)
**Perspective**: none
**Researcher conclusion**: The k3s deployment runs the **legacy self-hosted UniFi Network Application**, not UniFi OS. This is the single most important distinction. API keys are NOT available — they require UniFi OS. The correct login endpoint is `/api/login` (POST), not `/api/auth/login`. The session cookie is named `unifises`; no CSRF token header is required for legacy controllers. Local admin accounts are the only viable auth method — Ubiquiti SSO accounts are MFA-locked and break automated logins. A dedicated local admin account (Site Admin or View Only role, Remote Access disabled) must be created on the controller.
**Relation to primary question**: Defines the only viable auth path — username/password to `/api/login` with `unifises` cookie management. API keys and `/api/auth/login` will fail with 401.

### kubectl-Based UniFi Access Patterns
**Perspective**: none
**Researcher conclusion**: Direct MongoDB access via `kubectl exec` is the optimal CLI method for this home network. The embedded MongoDB listens on `localhost:27117`, database `ace`, with collections `device`, `client`, `stat_ap`, `stat_device`, `stat_sessions`, `event`, and `alarm`. No additional dependencies needed — `mongo` shell is already in the container. `kubectl logs` provides event streams but not current state snapshots. Direct DB access has lower latency (~10-50ms) than REST API (~100-500ms) and more complete data, but risks schema-change breakage across upgrades.
**Relation to primary question**: Provides an alternative zero-auth, zero-dependency CLI path that outperforms the REST API in speed and data completeness, though with lower stability guarantees across controller upgrades.

### UniFi API Endpoints for AP Data
**Perspective**: none
**Researcher conclusion**: All legacy stat endpoints (`stat/device`, `stat/sta`, `stat/health`, `stat/rogueap`) remain functional in v10.0.x despite legacy UI removal. `stat/device` with `type==uap` filter provides complete AP state including radio config, per-VAP stats, and system resources. `stat/sta` provides per-client RF metrics (signal, RSSI, channel, rates) not available via kubectl logs. For k3s self-hosted: standard paths (`/api/s/default/stat/…`) apply without `/proxy/network` prefix. Five ready-to-use `jq` filter examples provided for CLI queries.
**Relation to primary question**: Maps the complete read-only API surface for AP monitoring, confirming which endpoints survive v10 and which provide data unique to the REST API (RF telemetry, client satisfaction scores).

### Existing CLI Tools and Wrappers
**Perspective**: none
**Researcher conclusion**: Only two libraries have confirmed v10.x support: Art-of-WiFi PHP client (1,323 stars) and aiounifi Python library (used by Home Assistant, ~13K weekly PyPI downloads). `node-unifi` is capped at v9.x. No pre-built CLI tool supports v10. The v10 auth breaking change replaced `/api/login` with `/api/auth/login` + CSRF token on UniFi OS — but since the user's deployment is legacy self-hosted, the `/api/login` endpoint still works. No AP-only specific tools exist, but all compatible tools filter by device type. For the user's k3s-hosted 10.0.162 controller, a thin Python script using aiounifi or direct curl+jq is recommended over external tool dependencies.
**Relation to primary question**: Eliminates nearly all existing tools as non-functional, narrows the choice to direct HTTP or aiounifi, and confirms no pre-built CLI binary exists for this controller version.

### Integration Patterns (NixOS + fish + agenix)
**Perspective**: none
**Researcher conclusion**: Self-hosted UniFi Network Application 10.x does NOT support API keys — only cookie-based session auth with local admin credentials. Core `stat/device` and `stat/sta` endpoints confirmed working in v10.0.162. Credentials already exist at `secrets/unifi-credentials.age`. Fish functions should follow existing `envsource` pattern from other helpers. Session caching via `/run/user/$UID/unifi-cookies` with automatic re-login on 401. Three-tier function design: `unifi-status` (AP/client overview), `unifi-clients` (wireless client list with signal), `unifi-ap` (per-device detail). Complete Nix fish function implementation provided, ready to drop into `fish-functions.nix`.
**Relation to primary question**: Delivers the concrete answer — a complete, copy-paste-ready NixOS + fish implementation that wraps the REST API with agenix-secured credentials, session caching, and error handling.

## Cross-Cutting Insights

### Auth endpoint disagreement — resolved
The Endpoints and Integration reports reference `/api/auth/login` based on general v10.x documentation, while the Auth report provides a deeper analysis concluding the k3s deployment is the **legacy self-hosted** type using `/api/login`. The Auth report's platform analysis (legacy vs. UniFi OS detection via HTTP redirect behavior, Docker container type, port 8443) is more thorough and specifically tailored to the user's k3s environment. **Resolution**: `/api/login` is correct. The Integration report's fish functions should use `/api/login`, not `/api/auth/login`. This discrepancy is noted and the Integration report's auth endpoint should be corrected to `/api/login` in implementation. The `csrf_token` extraction and CSRF header handling may also be unnecessary for the legacy controller path.

### Two viable approaches — complementary, not competing
The kubectl+MongoDB approach and the REST API approach serve different needs:
- **kubectl+MongoDB**: Best for ad-hoc queries, debugging, and when kubectl access is already available. Zero auth overhead, fastest latency, complete data access. Recommended as the default for quick CLI checks.
- **REST API + fish functions**: Best for regular use, human-readable output, and integration with the network-engineer skill. Requires credential management but provides stable, documented endpoints that survive controller upgrades. The fish functions should implement this path.

**Recommendation**: Implement both. The fish functions use the REST API for polished, everyday use. The kubectl+MongoDB one-liners are documented as a fallback/debugging tool.

### No API keys on self-hosted — confirmed by 4 of 5 reports
All reports that address API keys agree: they require UniFi OS and are not available on the legacy self-hosted Network Application. This is a hard constraint. The only upgrade path to API key support is migrating to UniFi OS Server (which requires Podman, not k3s).

### Fish function implementation ready — one correction needed
The Integration report provides complete, production-quality Nix expressions for fish functions. The only correction needed: change the auth endpoint from `/api/auth/login` to `/api/login` and verify whether CSRF token handling is required (the Auth report says it is not for legacy controllers).

## Consolidated Bibliography

Alberty, J. (n.d.). *jacobalberty/unifi-docker: Unifi Docker files* [Source code]. GitHub. https://github.com/jacobalberty/unifi-docker

Alberty, J. (n.d.). *jacobalberty/unifi* [Docker image]. Docker Hub. https://hub.docker.com/r/jacobalberty/unifi

Art of WiFi. (n.d.). *How to create a local admin account for UniFi API & captive portal integrations (avoid MFA)*. Art of WiFi Blog. https://artofwifi.net/blog/use-local-admin-account-unifi-api-captive-portal

Art of WiFi. (n.d.). *UniFi API authentication: Local admin vs. API key vs. Site Manager*. Art of WiFi Blog. https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager

Art of WiFi. (n.d.). *UniFi APIs: A practical guide for developers and network admins*. Art of WiFi. https://artofwifi.net/unifi-api

Art of WiFi. (n.d.). *UniFi API client* (Version 2.2.0) [Source code]. GitHub. https://github.com/Art-of-WiFi/UniFi-API-client/blob/main/src/Client.php

Art of WiFi. (2026). *Art-of-WiFi/unifi-network-application-api-client: A modern PHP API client for the official UniFi Network Application API* [Source code]. GitHub. https://github.com/Art-of-WiFi/unifi-network-application-api-client

Averred. (2020). *unifi-find-ap* [Source code]. GitHub. https://github.com/averred/unifi-find-ap/blob/master/unifi-find-ap

Delian. (2026). *delian/unificli: Experimental CLI based on node-unifiapi* [Source code]. GitHub. https://github.com/delian/unificli

enuno. (2026). *unifi-mcp-server: An MCP server that leverages official UniFi API* (Version 0.2.5). GitHub. https://github.com/enuno/unifi-mcp-server

Home Assistant Core Contributors. (2026). *Home Assistant Core — UniFi Network Integration* [Source code]. GitHub. https://github.com/home-assistant/core/tree/dev/homeassistant/components/unifi

hyperb1iss. (n.d.). *unifly: Elegant UniFi network management CLI & TUI* [Source code]. GitHub. https://github.com/hyperb1iss/unifly

Incredigeek. (n.d.). *Searching for devices in UniFi via command line / MongoDB*. https://www.incredigeek.com/home/searching-for-devices-in-unifi-via-command-line-mongodb

LinuxServer.io. (n.d.). *docker-unifi-network-application* [Source code]. GitHub. https://github.com/linuxserver/docker-unifi-network-application

madbrain. (2025, November). *Unifi network API - self-hosted. Is there a token option?* Ubiquiti Community. https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb

Maus, J. (2025). *jens-maus/node-unifi: NodeJS class for querying/controlling a UniFi-Controller* [Source code]. GitHub. https://github.com/jens-maus/node-unifi

NixOS Community. (2025). *UniFi OS Server on nixos*. NixOS Discourse. https://discourse.nixos.org/t/unifi-os-server-on-nixos/76039

OutdoorsIdahoTech. (2026, February 7). *UniFi Network v10 Integration API - Confirming Read-Only Limitations for Client Management* [Online forum post]. Reddit. https://www.reddit.com/r/Ubiquiti/comments/1qymsls/unifi_network_v10_integration_api_confirming/

Svensson, R. (2026). *Kane610/aiounifi: Asynchronous library to communicate with Unifi Controller* [Source code]. GitHub. https://github.com/Kane610/aiounifi

Svensson, R. (2026). *aiounifi* [Python package]. PyPI. https://pypi.org/project/aiounifi

theDXT. (2023, December 16). *UniFi Network Server with Docker*. https://thedxt.ca/2023/12/unifi-network-server-with-docker/

tnware. (2026). *tnware/unifi-controller-api: A Python client library for interacting with Ubiquiti UniFi Network Controllers* [Source code]. GitHub. https://github.com/tnware/unifi-controller-api

Ubiquiti Community Wiki contributors. (n.d.). *UniFi Controller API*. Ubiquiti Community Wiki. https://ubntwiki.com/products/software/unifi-controller/api

Ubiquiti Community. (n.d.). *External MongoDB Server* [Online forum post]. https://community.ui.com/questions/External-MongoDB-Server/d311a8f8-43b6-4aeb-859d-eefec9dc1bbc

Ubiquiti Community. (n.d.). *Querying the MongoDB behind the UniFi Controller for Session to SSID/wlanconf association* [Online forum post]. https://community.ui.com/questions/Querying-the-MongoDB-behind-the-UniFi-Controller-for-Session-to-SSIDswlanconf-association/9021199b-69ab-4f5a-8a82-24a7adcb2445

Ubiquiti Community. (2025). *UniFi Network Application 10.0.160* [Release notes]. https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced

Ubiquiti Community. (2025). *UniFi Network Application 10.0.162 Release* [Release notes]. https://community.ui.com/releases/UniFi-Network-Application-10-0-162/2efd581a-3a55-4c36-80bf-1267dbfc2aee

Ubiquiti Community. (2025). *UniFi Network Application 10.1.85*. https://community.ui.com/releases/364f40ee-6976-4299-803e-89e111020f91

Ubiquiti Inc. (n.d.). *Explaining the UniFi system.properties File*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/205202580-Explaining-the-UniFi-system-properties-File

Ubiquiti Inc. (n.d.). *Getting Started with the Official UniFi API*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API

Ubiquiti Inc. (n.d.). *Self-hosting UniFi*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi

Ubiquiti Inc. (n.d.). *UniFi System Logs & SIEM Integration*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration

unpoller. (2026). *unifi: Go Library (w/ structures) to grab data from a Ubiquiti UniFi Controller* (Version master). GitHub. https://github.com/unpoller/unifi

## Decision

**SUFFICIENT** — The primary question can be answered fully and confidently. No major gaps remain. The one contradiction (auth endpoint `/api/login` vs `/api/auth/login`) is resolvable by platform analysis: the k3s deployment runs the legacy self-hosted Network Application, where `/api/login` is correct. The answer is clear: REST API with cookie-based auth via `/api/login`, wrapped in fish functions, with kubectl+MongoDB as a complementary ad-hoc debugging path.
