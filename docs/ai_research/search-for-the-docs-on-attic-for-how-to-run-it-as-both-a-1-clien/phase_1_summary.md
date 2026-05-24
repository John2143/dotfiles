# Phase 1 Summary

## Primary Question
How is Attic (the self-hosted Nix binary cache) configured as both server and client, and is our NixOS dotfiles setup correct — particularly the Nix substituter integration so that `nix` commands (not just `attic watch-store`) can pull from the cache?

## Sub-Topic Findings

### Attic server configuration and auth
**Perspective**: none
**Researcher conclusion**: atticd accepts **both** `Authorization: Bearer <jwt>` and `Authorization: Basic base64(<anything>:<jwt>)` — the Basic auth username is discarded and the password extracted as the JWT. This is explicitly documented in the source code (`token/src/lib.rs`) as "The JWT can be supplied to the server in one of two ways: As a normal Bearer token. As the password in Basic Auth (used by Nix)." The `allowed-hosts` setting uses exact string comparison including ports — `nas:8280` and `nas` are distinct. The `environmentFile` must be an absolute path outside the Nix store. Our NAS configuration is correct.
**Relation to primary question**: Confirms the server-side is correctly configured and that Basic auth (what Nix sends via netrc) is natively supported — the comment in our config claiming "Netrc sends Basic auth, but atticd expects Bearer tokens" is factually wrong.

### Attic client CLI usage
**Perspective**: none
**Researcher conclusion**: `attic login` stores tokens in `~/.config/attic/config.toml` (for the attic CLI). `attic use <cache>` is the command that configures Nix for **pulling** — it writes the substituter URL, trusted public key, and `netrc-file` to `~/.config/nix/nix.conf`, and the JWT as `machine <host> password <jwt>` into `~/.config/nix/netrc`. `attic watch-store` is push-only. There is no `attic pull` command — pulling is done through Nix's built-in HTTP binary cache substituter after `attic use` configures it.
**Relation to primary question**: Our `attic-login` + `attic-watch-store` setup is correct for pushing, but we are missing the equivalent of `attic use` for pulling. The `access-tokens` mechanism we configured is not what `attic use` uses — `attic use` uses `netrc-file`.

### Nix binary cache integration — how Nix talks to attic as a substituter
**Perspective**: none
**Researcher conclusion**: `nix.settings.access-tokens` is implemented in `src/libfetchers/github.cc` and applies **only** to Git forge fetchers (GitHub, GitLab). It does not inject headers into binary cache HTTP requests made via `HttpBinaryCacheStore`/`FileTransfer`. Binary cache auth goes through curl, which reads `netrc-file`. This is the root cause of our 401 errors — `access-tokens = nas=<token>` is simply not applied to binary cache requests. The correct approach is `netrc-file` pointing to a netrc with `machine nas password <jwt>`. Other caches (Cachix, nixbuild.net) follow the same netrc pattern.
**Relation to primary question**: Definitively identifies the bug: `access-tokens` is the wrong Nix configuration directive for binary cache auth. The `netrc-file` mechanism (which our earlier netrc approach used) is the correct one — it just needed the file to be readable by john.

### Attic authentication tokens — Bearer vs Basic, Nix access-tokens compatibility
**Perspective**: none
**Researcher conclusion**: `atticadm make-token` and `attic login` operate on the same JWT token format — generation vs storage, not different token types. The `parse_authorization_header()` function in `token/src/util.rs` uses a regex matching both `Bearer` and `Basic` schemes, and for Basic auth extracts the password as the JWT. The `apply_auth` middleware silently ignores invalid tokens (logging at debug level) — endpoints enforce permissions individually via `auth_cache()`. The existing comment in our dotfiles stating "Netrc sends Basic auth, but atticd expects Bearer tokens" is incorrect. The `access-tokens` approach *might* work (Nix sends Bearer, which atticd accepts) but uses an undocumented-for-this-purpose mechanism.
**Relation to primary question**: Confirms our token is valid (curl test passed) and that atticd accepts whatever auth scheme Nix sends — the auth scheme is not the problem. The problem is that Nix isn't sending the token at all when using `access-tokens` for binary cache requests.

## Cross-Cutting Insights

**Unanimous agreement across all 4 reports:** The root cause of the 401 errors is that `nix.settings.access-tokens` (as configured via `!include /run/agenix/attic-access-tokens` in `shared-cli-configuration.nix`) is not applied to binary cache HTTP requests. All 4 reports independently confirmed from source code analysis that `access-tokens` is for Git fetchers, not binary cache substituters.

**Unanimous agreement on the fix:** Use `nix.settings.netrc-file` pointing to a netrc file containing `machine nas password <jwt>`. This is the mechanism `attic use` configures, it's what the attic source code documents, and it's consistent with how other binary caches (Cachix, nixbuild.net) work.

**Additional finding (from attic-client-usage and attic-server-auth):** We are also missing `extra-trusted-public-keys` for the `2143nix` cache. Nix requires the cache's public key to verify signatures on downloaded store paths. Without it, Nix will refuse to substitute even if authentication succeeds. The public key can be obtained via `attic cache info 2143nix` and is `2143nix:Ysam0ozURtK+1tkP62M6lzbfoi8BVeL6s7ZWJlB6UxE=` (already in our config at `shared-cli-configuration.nix:27`).

**Correction to our earlier diagnosis:** The comment added to `shared-cli-configuration.nix` stating "Netrc sends Basic auth, but atticd expects Bearer tokens" is incorrect. atticd explicitly accepts Basic auth (with the JWT as the password) specifically for Nix compatibility. Our earlier netrc approach was architecturally correct — it just needed the file to be readable by the user running the `nix` command.

## Consolidated Bibliography

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
  - `server/src/config-template.toml`: https://github.com/zhaofengli/attic/blob/main/server/src/config-template.toml
- Zhaofeng Li. (2023–2025). *Attic Documentation*. https://docs.attic.rs/
  - Tutorial: https://docs.attic.rs/tutorial.html
  - User Guide: https://docs.attic.rs/user-guide/index.html
  - FAQs: https://docs.attic.rs/faqs.html
  - NixOS Deployment: https://docs.attic.rs/admin-guide/deployment/nixos.html
  - CLI Reference: https://docs.attic.rs/reference/attic-cli.html
  - atticadm CLI Reference: https://docs.attic.rs/reference/atticadm-cli.html
- NixOS Foundation. (2025). *Nix* [Source code]. GitHub. https://github.com/NixOS/nix
  - `filetransfer.cc`: https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/filetransfer.cc
  - `http-binary-cache-store.cc`: https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/http-binary-cache-store.cc
  - PR #12006: https://github.com/NixOS/nix/pull/12006
- NixOS Foundation. (2025). *nix.conf — Nix Reference Manual*. https://nix.dev/manual/nix/2.30/command-ref/conf-file.html
- NixOS Discourse. (2025). *access-tokens is underspecified*. https://discourse.nixos.org/t/access-tokens-is-underspecified/60410
- Cachix. (2025). *Frequently Asked Questions — Cachix Documentation*. https://docs.cachix.org/faq
- nixbuild.net. (2025). *User Settings — nixbuild.net Documentation*. https://docs.nixbuild.net/settings/
- Stenberg, D. (2024). *curl CLI v8.11.1 fails to offer HTTP Basic auth specified in .netrc* [GitHub Issue #15767]. https://github.com/curl/curl/issues/15767
- Wikipedia contributors. (2026). *Basic access authentication*. https://en.wikipedia.org/wiki/Basic_access_authentication
- justus.pw. (n.d.). *Attic on Nix Darwin*. https://www.justus.pw/wiki/Attic_on_Nix_Darwin

## Decision
**SUFFICIENT** — The primary question is answered fully and confidently. All 4 sub-topic reports independently confirm the same root cause (`access-tokens` is not used for binary cache auth) and the same fix (`netrc-file` with `machine nas password <jwt>`). The NAS configuration is correct. The client configuration needs one change: replace the `access-tokens` + `!include` mechanism with a `netrc-file` + activation script approach, using a netrc file readable by both root (for nix-daemon) and john (for user nix commands).
