# Attic Authentication Mechanism — Research Report

## 1. Summary

Attic uses **stateless JWT-based authentication**. Both `atticd-atticadm make-token` (server-side token generation) and `attic login` (client-side token storage) operate on the same JWT token format — the difference is purely generation vs. storage, not token type. Tokens are signed with either HS256 (HMAC-SHA256) or RS256 (RSA PKCS1), configured on the server via the `[jwt]` section of `server.toml` or the `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64` / `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` environment variables.

The critical architectural finding for the Nix substituter integration question: **atticd accepts BOTH `Authorization: Bearer <jwt>` AND HTTP Basic Auth (`Authorization: Basic <base64>`)**. When Basic auth is used, the username is **ignored** and the password field is extracted and used as the JWT token. This is explicitly documented in the attic source code with the comment: *"The JWT can be supplied to the server in one of two ways: As a normal Bearer token. As the password in Basic Auth (used by Nix). The username is ignored."*

This means the existing comment in our dotfiles — "Netrc sends Basic auth, but atticd expects Bearer tokens" — is **incorrect**. atticd expects a JWT, and accepts it through either auth scheme. The recommended integration path (used by `attic use`) is to write the JWT as a password in `~/.config/nix/netrc`, which causes Nix to send it via HTTP Basic auth. The server extracts the password and validates it as a JWT.

## 2. Relation to Primary Question

Our Nix substituter integration (for pulling from the cache via `nix.settings.extra-substituters`) can authenticate successfully using either `access-tokens` (which Nix sends as `Bearer`) or the `netrc` file (which sends `Basic`), because atticd's `parse_authorization_header()` function handles both schemes identically. The existing `access-tokens` approach in `shared-cli-configuration.nix` should work. The officially recommended and simpler approach is to use the `netrc` file, as the `attic use` command does.

## 3. Source Evaluation

### Primary Sources

1. **`attic/token/src/util.rs` — `parse_authorization_header()` function**
   - URL: `https://github.com/zhaofengli/attic/blob/main/token/src/util.rs`
   - Credibility: **Primary, definitive.** This is the actual Rust source code implementing the authorization header parser. It uses a regex to match both `Bearer` and `Basic` schemes, extracts the token from either, and in the Basic case strips the username and uses the password as the JWT. This is the single most authoritative source for how atticd parses auth headers.
   - Weight: Highest — canonical implementation.

2. **`attic/token/src/lib.rs` — Token struct, JWT claims, and documentation**
   - URL: `https://github.com/zhaofengli/attic/blob/main/token/src/lib.rs`
   - Credibility: **Primary, definitive.** Contains the full token format specification, including the `CachePermission` struct with its `r` (pull), `w` (push), `d` (delete), `cc` (create-cache), `cr` (configure-cache), `cq` (configure-retention), `cd` (destroy-cache) permission bits. Documents the `https://jwt.attic.rs/v1` custom claim namespace. Explicitly states the dual Bearer/Basic auth support in module-level documentation.
   - Weight: Highest — canonical implementation.

3. **`server/src/access/http.rs` — `apply_auth` middleware function**
   - URL: `https://github.com/zhaofengli/attic/blob/main/server/src/access/http.rs`
   - Credibility: **Primary, definitive.** The actual Axum middleware that runs on every request. Extracts the `Authorization` header, calls `parse_authorization_header()`, validates the JWT against the server's signing key, and stores the result in request state. Silently ignores bad tokens (logs at debug level) — authentication is optional per-request, with individual endpoints calling `auth_cache()` to enforce permissions.
   - Weight: Highest — canonical implementation.

4. **`client/src/api/mod.rs` — `build_http_client()` function**
   - URL: `https://github.com/zhaofengli/attic/blob/main/client/src/api/mod.rs`
   - Credibility: **Primary, definitive.** Shows how the attic client sends tokens: `format!("bearer {}", token)` in the `Authorization` header. The client uses Bearer auth exclusively.
   - Weight: Highest — canonical implementation.

5. **`server/src/adm/command/make_token.rs` — `atticadm make-token` implementation**
   - URL: `https://github.com/zhaofengli/attic/blob/main/server/src/adm/command/make_token.rs`
   - Credibility: **Primary, definitive.** Shows that `atticadm make-token` creates a `Token` struct, calls `token.encode()` with the server's signing key, and prints the resulting JWT string. The server never stores tokens — they are fully self-contained JWTs.
   - Weight: Highest.

6. **`client/src/command/login.rs` — `attic login` implementation**
   - URL: `https://github.com/zhaofengli/attic/blob/main/client/src/command/login.rs`
   - Credibility: **Primary, definitive.** Shows that `attic login` simply stores the provided token string (verbatim) into `~/.config/attic/config.toml` under the server configuration. No token generation or transformation occurs.
   - Weight: Highest.

7. **`client/src/command/use.rs` — `attic use` implementation**
   - URL: `https://github.com/zhaofengli/attic/blob/main/client/src/command/use.rs`
   - Credibility: **Primary, definitive.** Shows the end-to-end setup for Nix integration: adds the substituter to `nix.conf`, adds the trusted public key, and writes the JWT token as a password into `~/.config/nix/netrc` (which Nix sends as HTTP Basic auth).
   - Weight: Highest.

### Secondary Sources

8. **Official Attic documentation — Tutorial and FAQs**
   - URL: `https://docs.attic.rs/tutorial.html`, `https://docs.attic.rs/faqs.html`
   - Credibility: **Secondary, official.** Corroborates the source code findings but at a higher level. States that "Attic performs stateless authentication using signed JWT tokens which contain permissions." Confirms that the recommended token provisioning flow is: admin generates token via `atticadm make-token`, user receives it and runs `attic login`.
   - Weight: High — consistent with primary sources but less detailed.

9. **Nix `access-tokens` research (various)**
   - Notable: Nix PR #12006 (`https://github.com/NixOS/nix/pull/12006`) reveals that `accessHeaderFromToken` returns `"Bearer %s"`. The Nix Discourse thread "access-tokens is underspecified" (`https://discourse.nixos.org/t/access-tokens-is-underspecified/60410`) confirms that `access-tokens` behavior for binary caches is not well documented.
   - Credibility: **Primary for Nix side, but underspecified for binary cache auth.** The `access-tokens` config was designed for source fetching (GitHub/GitLab tokens), and its applicability to binary cache substituters is not clearly documented in Nix.
   - Weight: Medium — useful for understanding Nix behavior but less authoritative for the attic-specific question.

## 4. Conclusions

### Token Format

Attic tokens are standard JWTs with these claims:
- **`sub`**: Username/identifier (required)
- **`exp`**: Expiration timestamp (required)
- **`iss`**: Issuer (optional, configurable via `token-bound-issuer`)
- **`aud`**: Audience (optional, configurable via `token-bound-audiences`)
- **`https://jwt.attic.rs/v1`**: Custom claim containing `AtticAccess` with a `caches` map of cache name patterns to permission objects. Each permission object uses single-letter boolean flags: `r` (pull), `w` (push), `d` (delete), `cc` (create-cache), `cr` (configure-cache), `cq` (configure-retention), `cd` (destroy-cache).

Cache names in the permissions map may contain wildcards (e.g., `alice-*`), matched using `CacheNamePattern::matches()`.

### `atticadm make-token` vs `attic login`

These are **not different token types** — they are different operations on the same token format:
- `atticadm make-token`: Server-side JWT generation. The admin specifies subject, validity period, and cache permissions as CLI flags. The server signs the JWT with its configured key and prints the encoded token string.
- `attic login`: Client-side credential storage. Takes a server name, endpoint URL, and token string, and writes them to `~/.config/attic/config.toml`. Does not generate or transform tokens.

The same JWT string works for both `attic` CLI operations and Nix substituter access.

### Auth Header Handling

The `parse_authorization_header()` function in `token/src/util.rs` uses this regex:
```
^(?i)((?P<bearer>bearer)|(?P<basic>basic))(?-i) (?P<rest>(.*))$
```

It handles two cases:
1. **Bearer**: Uses the token directly from the `rest` capture group
2. **Basic**: Base64-decodes `rest`, splits on `:`, and uses the password portion (after the colon) as the JWT. The username is **discarded**.

### Auth Middleware

The `apply_auth` middleware (in `server/src/access/http.rs`) is applied to all routes. It:
1. Extracts the `Authorization` header
2. Calls `parse_authorization_header()` to extract the JWT
3. Validates the JWT using `Token::from_jwt()` against the server's signing key and optional issuer/audience bounds
4. On validation failure: logs at debug level and continues **without** auth — the request is treated as unauthenticated
5. On success: stores the validated `Token` in `RequestState.auth.token`

Individual endpoints then call `auth_state.auth_cache()` to enforce permissions. Public caches grant implicit pull access to unauthenticated users.

### Nix Integration — Correct Approach

The officially supported approach (used by `attic use`) is:
1. Add the substituter URL and trusted public key to `nix.conf` (or NixOS `nix.settings`)
2. Write the JWT token as a password in `~/.config/nix/netrc`:
   ```
   machine <hostname> password <jwt-token>
   ```
3. Ensure `netrc-file` is set in `nix.conf` (or Nix defaults to `~/.config/nix/netrc`)

This causes Nix to send `Authorization: Basic base64(<any-username>:<jwt>)`, which atticd correctly extracts and validates.

### Nix `access-tokens` — Does It Work?

Based on Nix source analysis (PR #12006), `access-tokens = nas=<jwt>` configures Nix to send `Authorization: Bearer <jwt>` for matching hosts. Atticd **does** accept Bearer tokens, so this approach **should work** in principle. However:
- Nix's `access-tokens` was designed for source fetching (GitHub/GitLab), not binary cache substituters
- Its behavior for binary cache HTTP requests is not well documented
- The attic project explicitly documents and recommends the `netrc` approach

**Recommendation**: Use the `netrc` file approach. It is what `attic use` configures, it is what the attic source code documents, and it is the path of least surprise. Write the JWT as:
```
machine nas password <jwt>
```
in `~/.config/nix/netrc` (or set `netrc-file` in `nix.conf` to a custom path). The `access-tokens` approach in our current config is not broken, but it uses a less-documented Nix mechanism for a purpose it wasn't primarily designed for.

### Our Current Setup Assessment

The NAS server configuration (`services.atticd` in `nas-configuration.nix`) appears correct:
- Listens on `[::]:8280`
- Uses the `attic-jwt-secret` environment file for JWT signing
- Has appropriate `allowed-hosts`

The client configuration in `shared-cli-configuration.nix`:
- `attic login nas http://nas:8280 $TOKEN` — correct
- `attic watch-store 2143nix` — correct for pushing
- `nix.settings.extra-substituters = ["http://nas:8280/2143nix"]` — correct for pulling
- The `access-tokens` approach **should work** given atticd accepts Bearer tokens
- However, the comment stating "Netrc sends Basic auth, but atticd expects Bearer tokens" is **factually wrong** — atticd accepts both. The netrc approach (used by `attic use`) would also work, and is the recommended method.

### Non-Obvious Finding

A subtle security consideration: the `apply_auth` middleware **silently ignores** invalid tokens rather than rejecting the request. Authorization is enforced per-endpoint via `auth_cache()`. This means:
- A request with an expired or malformed token is treated identically to an unauthenticated request
- Public caches will still serve content to such requests
- Private caches will return 401/403 from the endpoint handler, not from the middleware
- This design allows public caches to work without any auth while still accepting auth for private operations

## 5. Bibliography

Zhaofeng Li. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. https://github.com/zhaofengli/attic

- `token/src/util.rs` — Authorization header parser: https://github.com/zhaofengli/attic/blob/main/token/src/util.rs
- `token/src/lib.rs` — Token format, JWT claims, CachePermission struct: https://github.com/zhaofengli/attic/blob/main/token/src/lib.rs
- `server/src/access/http.rs` — Auth middleware (`apply_auth`): https://github.com/zhaofengli/attic/blob/main/server/src/access/http.rs
- `server/src/access/mod.rs` — Access module re-exports: https://github.com/zhaofengli/attic/blob/main/server/src/access/mod.rs
- `server/src/access/tests.rs` — Auth unit tests with example token: https://github.com/zhaofengli/attic/blob/main/server/src/access/tests.rs
- `server/src/adm/command/make_token.rs` — `atticadm make-token` implementation: https://github.com/zhaofengli/attic/blob/main/server/src/adm/command/make_token.rs
- `server/src/lib.rs` — Server initialization and middleware stack: https://github.com/zhaofengli/attic/blob/main/server/src/lib.rs
- `server/src/config.rs` — JWT configuration (signing keys, issuer, audience): https://github.com/zhaofengli/attic/blob/main/server/src/config.rs
- `client/src/api/mod.rs` — Client HTTP client (`build_http_client`): https://github.com/zhaofengli/attic/blob/main/client/src/api/mod.rs
- `client/src/command/login.rs` — `attic login` implementation: https://github.com/zhaofengli/attic/blob/main/client/src/command/login.rs
- `client/src/command/use.rs` — `attic use` implementation: https://github.com/zhaofengli/attic/blob/main/client/src/command/use.rs
- `client/src/nix_netrc.rs` — Nix netrc file management: https://github.com/zhaofengli/attic/blob/main/client/src/nix_netrc.rs
- `client/src/config.rs` — Client configuration (token storage): https://github.com/zhaofengli/attic/blob/main/client/src/config.rs
- `nixos/atticd.nix` — NixOS module for atticd: https://github.com/zhaofengli/attic/blob/main/nixos/atticd.nix

Zhaofeng Li. (2023–2025). *Attic Documentation*. https://docs.attic.rs/
- Tutorial: https://docs.attic.rs/tutorial.html
- User Guide: https://docs.attic.rs/user-guide/index.html
- FAQs: https://docs.attic.rs/faqs.html
- NixOS Deployment: https://docs.attic.rs/admin-guide/deployment/nixos.html

NixOS Foundation. (2003–2025). *Nix* [Source code]. GitHub. https://github.com/NixOS/nix
- `filetransfer.cc` — HTTP file transfer implementation: https://github.com/NixOS/nix/blob/master/src/libstore/filetransfer.cc
- `http-binary-cache-store.cc` — HTTP binary cache store: https://github.com/NixOS/nix/blob/master/src/libstore/http-binary-cache-store.cc
- PR #12006 — `accessHeaderFromToken` default implementation: https://github.com/NixOS/nix/pull/12006

NixOS Discourse. (2025, February 16). *access-tokens is underspecified*. https://discourse.nixos.org/t/access-tokens-is-underspecified/60410
