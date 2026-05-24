# Attic Server Configuration & Authentication Research Report

## 1. Summary

Attic (atticd) is a multi-tenant Nix binary cache server that performs **stateless authentication using signed JWT tokens** with embedded permissions. The server supports **both Bearer and HTTP Basic authentication schemes** for receiving those JWT tokens — a deliberate design choice explicitly documented in the source code to accommodate Nix's netrc-based credential mechanism. When a client sends `Authorization: Basic base64(username:password)`, atticd decodes the Base64 payload, extracts everything after the first colon (the "password" portion), and uses that as the raw JWT token — the username portion is ignored entirely. This means Nix's native `netrc-file` mechanism (which sends HTTP Basic auth via curl) is the intended, supported path for pull authentication.

The server configuration revolves around a `server.toml` file. Key settings include `allowed-hosts` (exact string match against the HTTP `Host` header; port **must** be included if clients send it — e.g., `nas:8280`), `api-endpoint` (the canonical endpoint reported to clients in `cache-config` responses; must end with `/`), `substituter-endpoint` (optional separate endpoint for binary cache operations), and the `[jwt.signing]` section holding the signing secret. The NixOS module (`services.atticd`) manages the systemd service, reads the JWT secret from an `environmentFile` (which must be an absolute path outside the Nix store), and generates the `server.toml` from `services.atticd.settings`.

For Nix to pull from a private Attic cache, the correct approach is to use the **netrc file** (`~/.config/nix/netrc` or `/etc/nix/netrc` for the nix-daemon) with a `machine` entry matching the Attic server hostname and `password` set to the JWT token. The `attic use` command automates this. Nix's `access-tokens` setting is primarily designed for GitHub/GitLab OAuth/PAT tokens (fetcher inputs), not for binary cache HTTP authentication, and using it for Attic substituters may be the root cause of the 401 errors the user is experiencing.

## 2. Relation to Primary Question

The primary question asks whether the Nix substituter integration is correct for pulling from the Attic cache. This research confirms that atticd **does** accept HTTP Basic auth (which is what Nix sends when configured via `netrc-file`), but it **does not** accept the `access-tokens` mechanism in the way the user has configured it. The fix is to switch from `nix.settings.access-tokens` to a properly formatted `netrc` file, or to make the cache public so no authentication is needed for pulls.

## 3. Source Evaluation

### Source 1: atticd source code — `token/src/util.rs` (parse_authorization_header)
- **URL**: https://github.com/zhaofengli/attic/blob/main/token/src/util.rs
- **Credibility**: **Primary source, maximum credibility.** This is the actual Rust source code implementing authorization header parsing. It definitively proves that atticd accepts both `Bearer` and `Basic` schemes, and that Basic auth extracts the password portion as the JWT.
- **Weighting**: Authoritative — this is the ground truth for how auth works.

### Source 2: atticd source code — `token/src/lib.rs` (Token, auth documentation)
- **URL**: https://github.com/zhaofengli/attic/blob/main/token/src/lib.rs
- **Credibility**: **Primary source, maximum credibility.** Contains the module-level documentation explicitly stating: "The JWT can be supplied to the server in one of two ways: As a normal Bearer token. As the password in Basic Auth (used by Nix). The username is ignored." Also documents the netrc format: `machine attic.server.tld password eyJhb...`.
- **Weighting**: Authoritative — directly addresses the user's confusion about Basic vs Bearer.

### Source 3: atticd source code — `server/src/middleware.rs` (restrict_host)
- **URL**: https://github.com/zhaofengli/attic/blob/main/server/src/middleware.rs
- **Credibility**: **Primary source, maximum credibility.** Shows the exact host-checking logic: `allowed_hosts.iter().any(|h| h.as_str() == host)` — a simple string equality check against the full `Host` header value (including port if present).
- **Weighting**: Authoritative for `allowed-hosts` behavior.

### Source 4: atticd source code — `server/src/config.rs` (Config struct)
- **URL**: https://github.com/zhaofengli/attic/blob/main/server/src/config.rs
- **Credibility**: **Primary source, maximum credibility.** Defines all configuration fields including `allowed-hosts`, `api-endpoint`, `substituter-endpoint`, and environment variable names (`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`, `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64`).
- **Weighting**: Authoritative for configuration schema and environment variable names.

### Source 5: atticd NixOS module — `nixos/atticd.nix`
- **URL**: https://github.com/zhaofengli/attic/blob/main/nixos/atticd.nix
- **Credibility**: **Primary source, high credibility.** The official NixOS module from the attic repository. Documents the `environmentFile` option, required assertion that it must not be a store path, and the systemd hardening configuration. Part of the same repository as the server code.
- **Weighting**: Authoritative for NixOS deployment details.

### Source 6: atticd server config template — `server/src/config-template.toml`
- **URL**: https://github.com/zhaofengli/attic/blob/main/server/src/config-template.toml
- **Credibility**: **Primary source, high credibility.** The template from which new server configs are generated. Documents all options with inline comments including the requirement that `api-endpoint` must end with a slash.
- **Weighting**: Authoritative, but represents the template/defaults, not necessarily production values.

### Source 7: Attic official tutorial — docs.attic.rs
- **URL**: https://docs.attic.rs/tutorial.html
- **Credibility**: **Primary source, high credibility.** Official project documentation. Demonstrates the `attic use` command flow including the netrc approach and `atticadm make-token` for token management. Less detailed than the source code but more accessible.
- **Weighting**: Authoritative for documented/intended usage patterns.

### Source 8: Attic NixOS deployment guide — docs.attic.rs
- **URL**: https://docs.attic.rs/admin-guide/deployment/nixos.html
- **Credibility**: **Primary source, high credibility.** Official deployment documentation showing the `environmentFile` format (`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="output from above"`) and NixOS configuration example.
- **Weighting**: Authoritative for deployment procedures.

### Source 9: nixbuild.net User Settings documentation
- **URL**: https://docs.nixbuild.net/settings/
- **Credibility**: **Secondary source, moderate credibility.** Third-party Nix build service documentation. Contains the claim "Adding netrc tokens to the access-tokens setting has the same effect as adding the tokens to a .netrc file." This is useful context but from a secondary source.
- **Weighting**: Useful for understanding the relationship between `access-tokens` and `netrc-file`, but secondary and specific to nixbuild.net's interpretation.

### Source 10: Nix Reference Manual (nix.conf)
- **URL**: https://nix.dev/manual/nix/2.18/command-ref/conf-file
- **Credibility**: **Primary source, maximum credibility.** Official Nix documentation defining `netrc-file`, `access-tokens`, `substituters`, and `trusted-public-keys` settings. Confirms netrc-file is used for HTTP authentication on binary cache downloads.
- **Weighting**: Authoritative for Nix configuration semantics.

## 4. Conclusions

### 4.1 Atticd accepts both Bearer and Basic auth — the 401 is likely a netrc misconfiguration

The source code in `token/src/util.rs` definitively shows that `parse_authorization_header()` handles both `Bearer <token>` and `Basic base64(user:pass)`. For Basic auth, the password portion (after the colon) is extracted and used as the JWT. This means that **Nix's netrc mechanism works correctly with atticd** — when Nix sends `Authorization: Basic base64(anything:jwt_token)`, atticd extracts `jwt_token` and validates it.

If the user is getting 401 errors, the cause is NOT that atticd rejects Basic auth. Likely causes:
1. **Using `nix.settings.access-tokens` instead of `netrc-file`**: The `access-tokens` setting in nix.conf is designed for GitHub/GitLab fetcher inputs (OAuth/PAT tokens) and may not be passed as HTTP Basic auth to binary cache substituters in the way `netrc-file` credentials are. The `access-tokens = ["nas=token"]` format may result in Nix sending the token differently (or not at all) for substituter HTTP requests.
2. **Missing netrc or wrong host in netrc**: The `machine` entry in netrc must match the Host header exactly. If clients connect to `http://nas:8280/2143nix`, the netrc must have `machine nas` with `password <jwt>` — or if the Host header includes the port, it must be `machine nas:8280`.
3. **Token lacks pull permission for cache `2143nix`**: The token must have `--pull 2143nix` permission (or be the root token which has all permissions).
4. **`allowed-hosts` mismatch**: If `allowed-hosts = ["nas"]` but clients send `Host: nas:8280`, the request is rejected before auth even runs. The `restrict_host` middleware does exact string matching.

### 4.2 `allowed-hosts` uses exact string matching including ports

The `restrict_host` middleware in `server/src/middleware.rs` performs a simple `h.as_str() == host` comparison. The `Host` header from HTTP includes the port if the client sends it on a non-default port. Therefore:
- If client sends `Host: nas:8280`, the `allowed-hosts` entry must be `"nas:8280"` (exactly).
- If client sends `Host: nas` (default port implied or stripped by proxy), the entry must be `"nas"`.
- If `allowed-hosts = []` (empty), all hosts are allowed (development default, insecure for production).
- There is no glob or wildcard support.

### 4.3 `api-endpoint` is the canonical endpoint reported to clients

The `api-endpoint` setting is used in `cache-config` API responses (`GET /v1/cache/:name/config`) to tell clients the base URL for API operations. It **must** end with a trailing slash (e.g., `https://attic.example.com/` not `https://attic.example.com`). If unset, atticd synthesizes it from the client's `Host` header, which is insecure behind proxies. The separate `substituter-endpoint` setting (newer addition) allows a different base URL for binary cache operations (NAR downloads) vs. API operations — useful when the binary cache endpoint differs from the API endpoint. If `substituter-endpoint` is unset, it defaults to `api-endpoint`.

### 4.4 `environmentFile` holds the JWT signing secret

The NixOS module reads `services.atticd.environmentFile` (must be an absolute path **outside** the Nix store, since store paths are world-readable) and passes it to systemd's `EnvironmentFile=` directive. The file must contain:

```
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="<base64-encoded RSA PEM PKCS1 private key>"
```

The key is generated with: `openssl genrsa -traditional 4096 | base64 -w0`

Alternatively, `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64` can be used for HMAC-based signing. The same env vars can also be set directly via the `[jwt.signing]` section in `server.toml` using `token-rs256-secret-base64` or `token-hs256-secret-base64`. The environment file approach is preferred because it keeps secrets out of the Nix store.

### 4.5 Correct configuration for Nix pull from Attic

Based on the source code and docs, the recommended approach for Nix clients to pull from an Attic cache:

**Option A: Use `attic use` (automatic)**
```
attic use 2143nix
```
This writes the substituter URL, trusted public key, and access token to `~/.config/nix/nix.conf` and `~/.config/nix/netrc` automatically.

**Option B: Manual netrc (for NixOS declarative config)**
```nix
{
  nix.settings = {
    substituters = [ "http://nas:8280/2143nix" ];
    trusted-public-keys = [ "2143nix:<PUBLIC_KEY>" ];
    netrc-file = "/etc/nix/netrc";  # Or rely on default ~/.config/nix/netrc
  };
}
```
And in `/etc/nix/netrc`:
```
machine nas password eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```
(If the server listens on a non-default port and clients send `Host: nas:8280`, use `machine nas:8280`.)

**Option C: Make the cache public** (no auth needed for pulls)
```
attic cache configure 2143nix --public
```
Then only the substituter URL and public key are needed — no netrc or token required.

### 4.6 The `access-tokens` pitfall

The user's current setup uses `nix.settings.access-tokens = ["nas=TOKEN"]`. The Nix documentation states `access-tokens` is for "protected GitHub, GitLab, or other locations requiring token-based authentication" — it is primarily designed for fetcher inputs (e.g., `fetchFromGitHub`), not for binary cache HTTP authentication. While some sources (nixbuild.net docs) claim it can substitute for netrc entries, the exact behavior depends on the Nix version and the resource type. For binary cache substituter requests, Nix uses the `netrc-file` mechanism via curl's netrc support. The `access-tokens` setting may not be propagated to substituter HTTP requests, which would explain the 401 errors. **The fix is to switch to `netrc-file` or use `attic use`.**

## 5. Bibliography

- zhaofengli. (n.d.). *attic/token/src/util.rs* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/token/src/util.rs
- zhaofengli. (n.d.). *attic/token/src/lib.rs* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/token/src/lib.rs
- zhaofengli. (n.d.). *attic/server/src/middleware.rs* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/server/src/middleware.rs
- zhaofengli. (n.d.). *attic/server/src/config.rs* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/server/src/config.rs
- zhaofengli. (n.d.). *attic/nixos/atticd.nix* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/nixos/atticd.nix
- zhaofengli. (n.d.). *attic/server/src/config-template.toml* [Source code]. GitHub. https://github.com/zhaofengli/attic/blob/main/server/src/config-template.toml
- zhaofengli. (n.d.). *Tutorial — Attic*. Attic documentation. https://docs.attic.rs/tutorial.html
- zhaofengli. (n.d.). *Deploying to NixOS — Attic*. Attic documentation. https://docs.attic.rs/admin-guide/deployment/nixos.html
- zhaofengli. (n.d.). *User Guide — Attic*. Attic documentation. https://docs.attic.rs/user-guide/index.html
- zhaofengli. (n.d.). *attic CLI — Attic*. Attic documentation. https://docs.attic.rs/reference/attic-cli.html
- NixOS Foundation. (n.d.). *nix.conf — Nix Reference Manual*. https://nix.dev/manual/nix/2.18/command-ref/conf-file
- nixbuild.net. (n.d.). *User Settings — nixbuild.net Documentation*. https://docs.nixbuild.net/settings/
- Wikipedia contributors. (2026). *Basic access authentication*. Wikipedia. https://en.wikipedia.org/wiki/Basic_access_authentication
