# UniFi REST API Authentication (v10.x) — Research Report

## 1. Summary

The UniFi Network Application exposes three distinct authentication surfaces depending on deployment type. For a **self-hosted k3s deployment running UniFi Network Application 10.0.162** — which is the legacy Java-based Network Server, not UniFi OS Server — only one authentication method is available: **username/password login via a local admin account**. API keys are not supported on this platform; they require a UniFi OS console (UDM, Cloud Key Gen2+, etc.) or UniFi OS Server.

The login endpoint for legacy self-hosted controllers is **`/api/login`** (POST), not `/api/auth/login`. The `/api/auth/login` endpoint is specific to UniFi OS-based controllers. Detection is straightforward: a GET to the controller's base URL returns an HTTP 302 redirect for legacy controllers, versus HTTP 200 for UniFi OS. The login payload is a simple JSON body: `{"username": "<local_admin>", "password": "<password>"}`. On success, the controller returns a session cookie named `unifises` which must be sent on all subsequent requests.

Ubiquiti SSO (cloud/UI.com) accounts cannot be used for automated API access because multi-factor authentication (MFA) has been mandatory since July 2024. The only reliable approach for CLI scripting is to create a **dedicated local admin account** on the controller with "Remote Access" disabled and the minimum required role (typically Site Admin for read/write, or View Only for read-only queries). This account is exempt from MFA and will authenticate cleanly.

The CSRF token landscape differs between platforms. Legacy self-hosted controllers rely on session cookies without requiring a separate CSRF token header for API calls. UniFi OS controllers return a JWT-based `TOKEN` cookie and require an `x-csrf-token` header (extracted from the JWT payload) on mutating requests.

## 2. Relation to Primary Question

The authentication mechanism directly constrains which CLI tools and curl one-liners will work. Since the k3s deployment runs the legacy self-hosted Network Application, any CLI solution **must** use local-admin username/password authentication against `/api/login` (not `/api/auth/login`) and manage the `unifises` session cookie — API keys and bearer-token approaches will fail with 401.

## 3. Source Evaluation

### Source 1: Art of WiFi — "UniFi API Authentication: Local Admin vs. API Key vs. Site Manager"
- **URL:** https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager
- **Credibility:** Secondary source with high technical authority. The Art of WiFi team maintains the most widely-used open-source UniFi API PHP client (1,300+ GitHub stars, 385,000+ Packagist downloads). They have been building on the UniFi API since 2015 and are cited by both the UniFi community and third-party integrators. This article is a definitive, detailed comparison of all three authentication methods with explicit platform-support matrices.
- **Weighting:** Very high. Directly addresses the API-key-vs-local-admin question and includes explicit statements about which platforms support which methods.

### Source 2: Art of WiFi — "How to Create a Local Admin Account for UniFi API & Captive Portal Integrations"
- **URL:** https://artofwifi.net/blog/use-local-admin-account-unifi-api-captive-portal
- **Credibility:** Same author/organization as Source 1. Step-by-step operational guide with version-specific UI navigation. Cites the July 2024 MFA enforcement date and community-reported breakage patterns.
- **Weighting:** Very high for the practical "how to set up auth" dimension.

### Source 3: Art of WiFi — "UniFi APIs: A Practical Guide for Developers and Network Admins"
- **URL:** https://artofwifi.net/unifi-api
- **Credibility:** Same author. Comprehensive orientation covering all three API surfaces (internal, official, Site Manager). Explicitly states that the official API requires Network Application 10.1.84+ and UniFi OS, and that API keys are UniFi OS-only.
- **Weighting:** Very high for the architectural overview and platform-compatibility matrix.

### Source 4: Art of WiFi UniFi API Client — Source Code (`src/Client.php`)
- **URL:** https://github.com/Art-of-WiFi/UniFi-API-client/blob/main/src/Client.php
- **Credibility:** Primary source (source code). MIT-licensed, actively maintained, supports UniFi versions 5.x–10.x. Shows exactly how login detection, endpoint selection, cookie handling, CSRF token extraction, API key injection, and error handling are implemented in production code.
- **Weighting:** Very high. This is the most authoritative source available short of reading Ubiquiti's own (undocumented) controller code. The logic is battle-tested across thousands of deployments.

### Source 5: Ubiquiti Community — "Unifi network API - self-hosted. Is there a token option?"
- **URL:** https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb
- **Credibility:** Primary source (official Ubiquiti Community forum). Contains direct Q&A between self-hosted users and community experts. Multiple respondents confirm that the legacy self-hosted Network Application does not expose API token/key functionality, that API keys are UniFi OS-only, and that local admin accounts are the only path.
- **Weighting:** High. Reflects real-world deployment experience and community consensus.

### Source 6: Ubiquiti Help Center — "Self-Hosting UniFi"
- **URL:** https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi
- **Credibility:** Primary source (official Ubiquiti documentation). Clarifies the distinction between the legacy UniFi Network Server and the newer UniFi OS Server. States that UniFi OS Server is the "new standard" and that the legacy Network Server lacks "key UniFi OS features."
- **Weighting:** High for establishing the platform distinction, though it does not directly address API authentication details.

### Source 7: Ubiquiti Community — "UniFi Network Application 10.0.160" Release Notes
- **URL:** https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced
- **Credibility:** Primary source (official release notes). Notes that 10.0.160 "extends the official API." 10.0.162 (the user's version) is a patch release with two bug fixes and no API changes.
- **Weighting:** Medium. Confirms API extensions in the 10.x line but does not address authentication mechanisms.

### Source 8: GitHub — hyperb1iss/unifly (CLI tool)
- **URL:** https://github.com/hyperb1iss/unifly
- **Credibility:** Secondary source. A community-built CLI/TUI tool for UniFi management. Its documentation confirms that API keys are generated under "Settings > Integrations" on UniFi OS controllers.
- **Weighting:** Low–medium. Useful corroboration but not authoritative.

### Source 9: Web search result aggregations (various)
- Multiple web search queries returned AI-summarized results that surfaced consistent patterns: `/api/auth/login` for UniFi OS, session cookie management, CSRF token requirements, 401/403 error semantics, and the local-vs-SSO account distinction. These were used for discovery but claims were verified against primary sources (Sources 1–6) before inclusion.
- **Weighting:** Low individually; collectively useful for triangulation.

## 4. Conclusions

### 4.1 Platform Determination Is Critical
The user's k3s deployment runs the **legacy self-hosted UniFi Network Application**, not UniFi OS Server. This is the single most important fact for authentication decisions. Evidence:
- The legacy Network Application is the only UniFi component that is routinely deployed as a plain Docker container in Kubernetes/k3s environments.
- UniFi OS Server uses Podman with systemd integration, not k3s.
- The legacy application exposes port 8443 (HTTPS); UniFi OS consoles use port 443.

### 4.2 API Keys Are Not Available
API keys (both Network Application API keys and Site Manager API keys) require a UniFi OS console or UniFi OS Server. The legacy self-hosted Network Application — even at version 10.0.162 — does not support API key generation or authentication. Multiple independent sources confirm this.

### 4.3 The Correct Authentication Flow for This Deployment

**Step 1:** Create a dedicated local admin account on the controller:
- Log into the UniFi Network Application web UI.
- Navigate to **Admins** (left sidebar icon, not under Settings).
- Create a new admin with "Remote Access" disabled (local-only).
- Assign the minimum required role: **Site Admin** for read/write, **View Only** for read-only.

**Step 2:** Authenticate via curl:
```bash
curl -k -c cookies.txt -X POST \
  "https://<controller-host>:8443/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"<local_admin_username>","password":"<password>"}'
```

**Step 3:** Use the session cookie for subsequent requests:
```bash
curl -k -b cookies.txt \
  "https://<controller-host>:8443/api/s/default/stat/device"
```

**Key details:**
- The endpoint is `/api/login`, **not** `/api/auth/login` (which is UniFi OS-only).
- The session cookie is named `unifises` (not `TOKEN`, which is UniFi OS-only).
- No CSRF token header is needed for the legacy controller's internal API.
- The `-k` flag skips TLS certificate validation (self-signed certificates are typical).
- Port 8443 is the default HTTPS port for legacy self-hosted controllers.

### 4.4 SSO/Cloud Accounts Must Be Avoided
Ubiquiti SSO (UI.com) accounts have required MFA since July 22, 2024. Even if MFA is not explicitly configured, email verification is auto-enabled. Automated scripts cannot satisfy interactive second-factor prompts, resulting in 401 errors. Local admin accounts are not subject to MFA and are the only reliable path.

### 4.5 Error Code Semantics
- **401 Unauthorized:** Bad credentials, expired session cookie, or attempt to use a UI.com/SSO account that triggers MFA. Also returned if using `/api/auth/login` against a legacy controller.
- **403 Forbidden:** Authenticated user lacks required permissions (e.g., View Only account attempting a write operation), or the controller is in a restricted state.
- **HTTP 302 on base URL GET:** Confirms legacy controller; UniFi OS returns HTTP 200.

### 4.6 Future-Proofing Consideration
Ubiquiti is directing self-hosted users toward **UniFi OS Server**, which supports API keys and the official API. The legacy Network Application is being positioned as deprecated. If API key authentication becomes important, migrating to UniFi OS Server would enable it. However, this requires Podman (not k3s) and may require a UI.com account for initial setup.

## 5. Bibliography

Art of WiFi. (n.d.). *UniFi API authentication: Local admin vs. API key vs. Site Manager*. Art of WiFi Blog. https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager

Art of WiFi. (n.d.). *How to create a local admin account for UniFi API & captive portal integrations (avoid MFA)*. Art of WiFi Blog. https://artofwifi.net/blog/use-local-admin-account-unifi-api-captive-portal

Art of WiFi. (n.d.). *UniFi APIs: A practical guide for developers and network admins*. Art of WiFi. https://artofwifi.net/unifi-api

Art of WiFi. (n.d.). *UniFi API client* (Version 2.2.0) [Source code]. GitHub. https://github.com/Art-of-WiFi/UniFi-API-client/blob/main/src/Client.php

madbrain. (2025, November). *Unifi network API - self-hosted. Is there a token option?* Ubiquiti Community. https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb

Ubiquiti Inc. (n.d.). *Self-hosting UniFi*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi

Ubiquiti Inc. (2025). *UniFi Network Application 10.0.160* [Release notes]. Ubiquiti Community. https://community.ui.com/releases/UniFi-Network-Application-10-0-160/ce7adc5c-4b42-49d3-8447-971992c0bced

hyperb1iss. (n.d.). *unifly: Elegant UniFi network management CLI & TUI* [Source code]. GitHub. https://github.com/hyperb1iss/unifly
