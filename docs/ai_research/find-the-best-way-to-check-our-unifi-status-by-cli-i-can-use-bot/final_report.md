# Final Report: Best Way to Check UniFi Status by CLI

## 1. Answer

The best method to query UniFi wireless access point status from the CLI against your k3s-hosted UniFi Network Application 10.0.162 is the **REST API using cookie-based session authentication**, wrapped in fish functions with agenix-secured credentials. Two complementary approaches are available, ranked by use case:

**Primary (daily use):** Use `/api/login` (NOT `/api/auth/login`) with local admin credentials to obtain a `unifises` session cookie, then query `/api/s/default/stat/device` (filter `type==uap`) for AP status and `/api/s/default/stat/sta` for wireless clients. Wrap this in three fish functions — `unifi-status`, `unifi-clients`, `unifi-ap` — that load credentials from `secrets/unifi-credentials.age`, cache sessions at `/run/user/$UID/unifi-cookies`, and format output with `jq`. Complete Nix expressions are ready in [integration-patterns](reports/integration-patterns_report.md).

**Secondary (ad-hoc debugging):** Use `kubectl exec` to query the embedded MongoDB directly — zero authentication, millisecond latency. The database is `ace` on `localhost:27117` inside the container. Example: `kubectl exec deploy/unifi -n default -- mongo --quiet --port 27117 ace --eval 'db.device.find({type:/uap/}, {name:1, state:1, num_sta:1}).forEach(printjson)'`.

**API keys are not available.** The k3s deployment runs the legacy self-hosted Network Application, not UniFi OS. API key authentication requires UniFi OS and cannot be enabled on your controller. No pre-built CLI tool with v10 support exists — the ecosystem bifurcated when v10 introduced a different auth flow for UniFi OS while leaving legacy self-hosted controllers on the old `/api/login` path.

## 2. Evidence Summary

| Finding | Source Report |
|---------|---------------|
| K3s deployment is legacy self-hosted (not UniFi OS), `/api/login` is the correct endpoint, API keys unavailable | [Auth Report](reports/unifi-api-authentication_report.md) |
| MongoDB at `localhost:27117`, database `ace`, collections `device`/`client`/`stat_ap` accessible via `kubectl exec` | [kubectl Report](reports/kubectl-unifi-access_report.md) |
| `stat/device` (type==uap) and `stat/sta` endpoints survive v10, provide RF telemetry not in logs | [Endpoints Report](reports/unifi-ap-api-endpoints_report.md) |
| No pre-built v10 CLI tool exists; aiounifi (Python) and Art-of-WiFi (PHP) are the only compatible libraries | [Tools Report](reports/unifi-cli-tools_report.md) |
| Complete fish function Nix expressions (`unifi-status`, `unifi-clients`, `unifi-ap`) with agenix + session caching | [Integration Report](reports/integration-patterns_report.md) |

## 3. Confidence Assessment

**High confidence** on authentication mechanism and endpoint availability. Five independent sources — the Art-of-WiFi PHP client source code, Ubiquiti Community forum, Home Assistant UniFi integration source code, unpoller Go library structs, and the Ubiquiti release notes — all confirm the legacy self-hosted vs. UniFi OS distinction, the `/api/login` endpoint behavior, and the absence of API keys on self-hosted deployments.

**High confidence** on MongoDB access patterns. The jacobalberty/unifi-docker Dockerfile and entrypoint are authoritative on container internals. The Incredigeek and unifi-find-ap sources provide independently verifiable query examples against the same schema.

**Medium confidence** on fish function correctness. The implementation follows established NixOS patterns from the dotfiles repository but was not tested against the live controller due to auth troubleshooting during research.

## 4. Limitations and Open Questions

- The fish function auth endpoint needs correction: the Integration report uses `/api/auth/login` (UniFi OS path); implementation should use `/api/login` (legacy self-hosted path).
- CSRF token handling may be unnecessary for the legacy controller; test both with and without the `X-CSRF-Token` header.
- MongoDB schema stability across UniFi upgrades is not guaranteed; test queries after each controller version bump.
- The `/api/login` endpoint was not confirmed working during research due to credential format issues — the first implementation step should be a manual curl test with the credentials from `secrets/unifi-credentials.age`.

## 5. Bibliography

Art of WiFi. (n.d.). *UniFi API authentication: Local admin vs. API key vs. Site Manager*. https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager

Art of WiFi. (n.d.). *UniFi API client* (Version 2.2.0) [Source code]. GitHub. https://github.com/Art-of-WiFi/UniFi-API-client/blob/main/src/Client.php

Alberty, J. (n.d.). *jacobalberty/unifi-docker: Unifi Docker files* [Source code]. GitHub. https://github.com/jacobalberty/unifi-docker

madbrain. (2025, November). *Unifi network API - self-hosted. Is there a token option?* Ubiquiti Community. https://community.ui.com/questions/Unifi-network-API-self-hosted-Is-there-a-token-option/50b00beb-1edc-442e-9bbc-2bd8c9542fbb

Svensson, R. (2026). *Kane610/aiounifi: Asynchronous library to communicate with Unifi Controller* [Source code]. GitHub. https://github.com/Kane610/aiounifi

Ubiquiti Community Wiki contributors. (n.d.). *UniFi Controller API*. https://ubntwiki.com/products/software/unifi-controller/api

Ubiquiti Inc. (n.d.). *Self-hosting UniFi*. https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi

unpoller. (2026). *unifi: Go Library (w/ structures) to grab data from a Ubiquiti UniFi Controller* (Version master). GitHub. https://github.com/unpoller/unifi
