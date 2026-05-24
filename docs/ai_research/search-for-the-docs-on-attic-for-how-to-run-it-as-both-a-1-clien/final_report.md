# Final Report: Attic Server & Client Integration

## 1. Answer

Our NAS server configuration (`nas-configuration.nix`) is **correct**. Atticd is properly configured with JWT auth, correct `allowed-hosts` (after the recent additions of port-qualified entries and Tailscale IP), and proper `environmentFile` handling.

Our client configuration (`shared-cli-configuration.nix`) is **incorrect for pulling**. The `attic-login` + `attic-watch-store` services are correct for **pushing** store paths to the cache. But the mechanism for **pulling** — `nix.settings.access-tokens` injected via `!include /run/agenix/attic-access-tokens` — does not apply to binary cache HTTP requests. The `access-tokens` Nix setting is implemented in the Git fetcher subsystem (`libfetchers/github.cc`) and is never consulted by the HTTP binary cache store (`HttpBinaryCacheStore` → `FileTransfer` → curl).

The correct approach, confirmed by attic's own source code (`token/src/lib.rs`) and the `attic use` command implementation, is to use a **netrc file** (`machine nas password <jwt>`) with `nix.settings.netrc-file` pointing to it. Atticd explicitly accepts HTTP Basic auth (extracting the JWT from the password field) specifically for Nix compatibility. The comment in our config stating "Netrc sends Basic auth, but atticd expects Bearer tokens" is factually wrong — atticd accepts both.

The fix: replace the `nix.extraOptions` / `!include` / `access-tokens` mechanism with a `netrc-file` approach, writing the netrc from the agenix-decrypted `attic-admin-token` at activation time, with permissions such that both the nix-daemon (root) and user `nix` commands (john) can read it.

## 2. Evidence Summary

| Finding | Source | Confidence |
|---|---|---|
| atticd accepts both `Bearer` and `Basic` auth | Primary: `token/src/util.rs` `parse_authorization_header()` — regex matches both schemes; `token/src/lib.rs` module docs: "The JWT can be supplied... As the password in Basic Auth (used by Nix)" | **High** — 4 independent reports confirmed from source code |
| `nix.settings.access-tokens` is for Git fetchers only | Primary: `src/libfetchers/github.cc` — `getAccessToken()` used by VCS fetchers; `HttpBinaryCacheStore` delegates to `FileTransfer` which uses curl+netrc | **High** — consistent with Nix manual and source |
| `attic use` configures pulling via netrc | Primary: `client/src/command/use.rs`, `nix_config.rs`, `nix_netrc.rs` — writes substituter, trusted-public-keys, netrc-file, and `machine <host> password <jwt>` to netrc | **High** — canonical implementation |
| Our token is valid | Empirical: curl with `Authorization: Bearer <token>` got 200 OK from atticd | **High** — direct test |
| The `access-tokens` approach is ineffective for binary caches | Primary: Nix source code analysis, corroborated by Cachix and nixbuild.net docs showing netrc pattern | **High** |
| `allowed-hosts` uses exact string match including port | Primary: `server/src/middleware.rs` — `h.as_str() == host` | **High** |
| We already have the trusted public key | Our config `shared-cli-configuration.nix:27`: `2143nix:Ysam0ozURtK+1tkP62M6lzbfoi8BVeL6s7ZWJlB6UxE=` | **High** — already configured |

## 3. Confidence Assessment

**High confidence.** All 4 sub-topic reports independently converged on the same root cause and fix. The key finding (`access-tokens` not applied to binary cache requests) is supported by Nix source code analysis, attic source code analysis, and consistent patterns from other binary caches (Cachix, nixbuild.net). The fix (`netrc-file` with `machine nas password <jwt>`) is the method `attic use` itself configures and is explicitly documented in attic's source code.

## 4. Limitations and Open Questions

- This research did not examine whether Nix re-reads the netrc file on each request or caches it — a daemon restart after activation may be required.
- The `netrc-file` path in `/run/agenix/` exists on a ramfs that is recreated on each boot; the activation script must run before nix-daemon starts.
- We did not test whether Nix's `access-tokens` setting might *also* work for binary caches in some configurations — the research found it unreliable and undocumented for this purpose.
- The `attic-admin-token` has full permissions (`*` push/pull/delete/create/configure). If the token is ever scoped down, ensure it retains `--pull 2143nix`.

## 5. Bibliography

- Zhaofeng Li. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. https://github.com/zhaofengli/attic
  - `token/src/util.rs`: https://github.com/zhaofengli/attic/blob/main/token/src/util.rs
  - `token/src/lib.rs`: https://github.com/zhaofengli/attic/blob/main/token/src/lib.rs
  - `server/src/middleware.rs`: https://github.com/zhaofengli/attic/blob/main/server/src/middleware.rs
  - `server/src/config.rs`: https://github.com/zhaofengli/attic/blob/main/server/src/config.rs
  - `server/src/access/http.rs`: https://github.com/zhaofengli/attic/blob/main/server/src/access/http.rs
  - `client/src/nix_config.rs`: https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_config.rs
  - `client/src/nix_netrc.rs`: https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_netrc.rs
  - `client/src/command/use.rs`: https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/use.rs
  - `client/src/command/login.rs`: https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/login.rs
  - `client/src/config.rs`: https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/config.rs
  - `server/src/adm/command/make_token.rs`: https://github.com/zhaofengli/attic/blob/main/server/src/adm/command/make_token.rs
  - `nixos/atticd.nix`: https://github.com/zhaofengli/attic/blob/main/nixos/atticd.nix
- Zhaofeng Li. (2023–2025). *Attic Documentation*. https://docs.attic.rs/
  - Tutorial: https://docs.attic.rs/tutorial.html
  - User Guide: https://docs.attic.rs/user-guide/index.html
  - FAQs: https://docs.attic.rs/faqs.html
  - NixOS Deployment: https://docs.attic.rs/admin-guide/deployment/nixos.html
- NixOS Foundation. (2025). *Nix* [Source code]. https://github.com/NixOS/nix
  - `filetransfer.cc`: https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/filetransfer.cc
  - `http-binary-cache-store.cc`: https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/http-binary-cache-store.cc
  - PR #12006: https://github.com/NixOS/nix/pull/12006
- NixOS Foundation. (2025). *nix.conf — Nix Reference Manual*. https://nix.dev/manual/nix/2.30/command-ref/conf-file.html
- NixOS Discourse. (2025). *access-tokens is underspecified*. https://discourse.nixos.org/t/access-tokens-is-underspecified/60410
- Cachix. (2025). *Frequently Asked Questions — Cachix Documentation*. https://docs.cachix.org/faq
- nixbuild.net. (2025). *User Settings — nixbuild.net Documentation*. https://docs.nixbuild.net/settings/
