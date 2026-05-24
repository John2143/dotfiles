# Report: Attic Client CLI Usage

## 1. Summary

The `attic` binary cache client provides five main commands: `login`, `use`, `push`, `watch-store`, and `cache`. There is **no `attic pull` command** — cache reading is handled entirely through Nix's built-in HTTP binary cache substituter mechanism, which `attic use` configures automatically.

**`attic login <name> <endpoint> [token]`** stores server credentials (name, endpoint URL, and JWT token) in `~/.config/attic/config.toml` with `0600` permissions. The token can be stored inline (`token = "eyJ..."`) or via a file path (`token-file = "/run/secrets/token"`), though the CLI only writes the inline form. This configuration is used by all subsequent `attic` commands to authenticate against the server.

**`attic use <cache>`** is the critical command for pull-side integration. It performs three actions: (1) adds the cache's `substituter` URL and `trusted-public-keys` to `~/.config/nix/nix.conf`, (2) creates/updates `~/.config/nix/netrc` with `machine <host> password <JWT>` for authentication, and (3) sets `netrc-file` in nix.conf to point to the netrc. After `attic use`, Nix can transparently pull from the cache without further attic client involvement.

**`attic push <cache> [paths]`** computes the closure of the specified store paths and uploads them to the cache. It skips paths already present upstream (default: `cache.nixos.org`) unless `--ignore-upstream-cache-filter` is passed. **`attic watch-store <cache>`** is a long-running daemon that monitors `/nix/store` for new paths via inotify and pushes them automatically. It is push-only; it does not pull from the cache.

**Authentication** uses signed JWT tokens passed to the server in one of two ways: as `Authorization: Bearer <JWT>` (used by the attic client) or as `Authorization: Basic base64(anything:<JWT>)` (used by Nix via netrc). The atticd server's `parse_authorization_header` function in `token/src/util.rs` handles **both** formats — it extracts the JWT from Bearer tokens directly, and from Basic auth by base64-decoding and taking the password portion after the colon, ignoring the username. This dual acceptance is explicitly documented in the token crate's module docs: "The JWT can be supplied to the server in one of two ways: As a normal Bearer token. As the password in Basic Auth (used by Nix)."

## 2. Relation to Primary Question

The primary question is whether our NixOS dotfiles setup correctly integrates attic as a Nix substituter for pulling, not just pushing. The key finding is that `nix.settings.access-tokens` (currently used in `shared-cli-configuration.nix` via the `!include /run/agenix/attic-access-tokens` mechanism) is **not the correct configuration directive for binary cache authentication**. Binary cache auth requires a netrc file (`machine nas password <JWT>`) and the `netrc-file` or default netrc path. While atticd accepts the JWT from both Bearer and Basic auth headers (so the auth scheme mismatch itself is not the root cause), the `access-tokens` Nix setting is designed for fetcher authentication (GitHub/GitLab), not binary cache substituters — Nix's HTTP binary cache store reads credentials from the configured netrc file, not from `access-tokens`.

## 3. Source Evaluation

### Primary Sources (Source Code)

**Source 1:** `https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/lib.rs`
- **Credibility:** Primary. Official source code in the zhaofengli/attic repository. Defines the token module, JWT claims format, and documents the dual Bearer/Basic auth acceptance in its module-level doc comment. Author is verified (Zhaofeng Li, the project creator). Recency: main branch, actively maintained.
- **Weight:** Highest. This is the canonical specification for how authentication works — it is the implementation, not documentation about the implementation.

**Source 2:** `https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/util.rs`
- **Credibility:** Primary. Contains the `parse_authorization_header` function that regex-matches both `Bearer` and `Basic` Authorization header formats and extracts the JWT accordingly. Verified author, actively maintained.
- **Weight:** Highest. Definitive for understanding the auth mechanism.

**Source 3:** `https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/config.rs`
- **Credibility:** Primary. Shows the `~/.config/attic/config.toml` format, credential storage (`ServerTokenConfig::Raw` and `ServerTokenConfig::File`), and file permission handling (0600). Verified author.
- **Weight:** Highest. Definitive for understanding credential storage.

**Source 4:** `https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/login.rs`
- **Credibility:** Primary. Shows the `attic login` command implementation — writes server name, endpoint, and token to the attic config. Verified author.
- **Weight:** Highest.

**Source 5:** `https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/use.rs`
- **Credibility:** Primary. Shows the `attic use` command implementation — calls `NixConfig::add_substituter`, `NixConfig::add_trusted_public_key`, creates netrc entry via `NixNetrc::add_token`, and sets `netrc-file` in nix.conf. Verified author.
- **Weight:** Highest. Definitive for understanding how Nix is configured for pulling.

**Source 6:** `https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_config.rs`
- **Credibility:** Primary. Shows that `attic use` writes to `~/.config/nix/nix.conf` with structured parsing, modifying `substituters`, `trusted-public-keys`, and `netrc-file` directives. Verified author.
- **Weight:** Highest. Confirms that `netrc-file` (not `access-tokens`) is the mechanism used.

**Source 7:** `https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_netrc.rs`
- **Credibility:** Primary. Shows the netrc file format: `machine <host> password <JWT>`. The netrc is stored at `~/.config/nix/netrc` with 0600 permissions. Verified author.
- **Weight:** Highest.

**Source 8:** `https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/access/http.rs`
- **Credibility:** Primary. Shows the `apply_auth` middleware that extracts the token from the Authorization header and populates `AuthState::token`. The token is then used by endpoint handlers for permission checks. Verified author.
- **Weight:** Highest.

### Primary Sources (Official Documentation)

**Source 9:** `https://docs.attic.rs/tutorial.html`
- **Credibility:** Primary. Official project documentation. Describes the full workflow: login, cache creation, push, `attic use`, and pull via `nix-store`. Authored by the project maintainer. Recency: 2025-09-24.
- **Weight:** High. Authoritative documentation, though source code is more definitive for implementation details.

**Source 10:** `https://docs.attic.rs/reference/attic-cli.html`
- **Credibility:** Primary. Official CLI reference with all subcommand syntax and options. Authored by maintainer.
- **Weight:** High.

**Source 11:** `https://docs.attic.rs/user-guide/index.html`
- **Credibility:** Primary. Official user guide showing login, cache enabling, manual NixOS declarative configuration, and pushing. Authored by maintainer.
- **Weight:** High.

**Source 12:** `https://docs.attic.rs/reference/atticadm-cli.html`
- **Credibility:** Primary. Documents the `atticadm make-token` command for generating scoped JWT tokens with pull/push/create/configure/destroy permissions. Authored by maintainer.
- **Weight:** High.

**Source 13:** `https://docs.attic.rs/faqs.html`
- **Credibility:** Primary. Confirms: "Authentication is done via signed JWTs containing the allowed permissions. Each instance of atticd --mode api-server is stateless." Authored by maintainer.
- **Weight:** High.

### Secondary Sources (Nix Documentation)

**Source 14:** `https://nix.dev/manual/nix/2.22/command-ref/conf-file.html` (specifically the `access-tokens` and `netrc-file` settings)
- **Credibility:** Primary for Nix, secondary for Attic. Official Nix documentation. The `access-tokens` section describes GitHub/GitLab/fetcher token auth. The `netrc-file` section describes HTTP authentication for downloads. Verified NixOS Foundation authorship. Recency: Nix 2.22.
- **Weight:** High for understanding what Nix settings do, but not directly authoritative on Attic behavior.

### Secondary Sources (Community)

**Source 15:** `https://www.justus.pw/wiki/Attic_on_Nix_Darwin`
- **Credibility:** Secondary. Community wiki. Notes that `attic` creates netrc information in `~/.config/attic/config.toml` and extracting it with sed. Unverified author. Useful corroboration but not authoritative.
- **Weight:** Low. Used only for corroboration of the netrc mechanism.

## 4. Conclusions

### 4.1 How Each `attic` Command Works

1. **`attic login <name> <endpoint> [token]`**: Writes to `~/.config/attic/config.toml` (TOML format, 0600 perms). Stores server name, endpoint URL, and token (inline as `token = "eyJ..."`). If the server already exists, it overwrites. If `--set-default` or it's the only server, sets it as default. **Does not configure Nix for pulling.**

2. **`attic use <cache>`**: Fetches cache configuration from server (substituter endpoint, public key). Writes to `~/.config/nix/nix.conf`: adds `substituters`, `trusted-public-keys`, and `netrc-file`. Creates/updates `~/.config/nix/netrc`: adds `machine <host> password <JWT>`. After this, Nix can pull from the cache without further attic involvement. **This is the command that enables pulling.**

3. **`attic push <cache> [paths]`**: Computes closures of specified paths, checks which are already in the cache, and uploads new ones using the attic API (`/_api/v1/get-missing-paths` then `/_api/v1/upload-path`). Skips paths signed by upstream caches (default: `cache.nixos.org-1`) unless `--ignore-upstream-cache-filter` is passed.

4. **`attic watch-store <cache>`**: Long-running daemon. Uses inotify to detect new paths in `/nix/store` and pushes them via the same mechanism as `attic push`. **Push-only** — does not perform any pulling. Typically run as a systemd service.

5. **There is no `attic pull` command.** Pulling is handled by Nix's HTTP binary cache substituter after `attic use` configures it.

6. **`attic cache create/configure/destroy/info`**: Cache lifecycle management via the attic API (`/_api/v1/cache-config/:cache`). `cache info` displays the substituter endpoint URL and public key, which are needed for manual NixOS declarative configuration.

### 4.2 Authentication Mechanism (Detailed)

The token is a signed JWT (HS256 or RS256) with claims in the `https://jwt.attic.rs/v1` namespace:

```json
{
  "sub": "john",
  "exp": 1740000000,
  "https://jwt.attic.rs/v1": {
    "caches": {
      "2143nix": { "r": 1, "w": 1, "d": 1, "cc": 1, "cr": 1, "cq": 1 }
    }
  }
}
```

The token reaches the server in one of two ways:

- **Attic client → Bearer auth:** `Authorization: Bearer eyJhbG...` (used by `attic push`, `attic watch-store`, `attic use`, etc.)
- **Nix substituter → Basic auth:** `Authorization: Basic base64(nas:eyJhbG...)` (generated by curl from the netrc file)

The server's `parse_authorization_header` function handles both:

```
rust
// For Bearer: extracts the JWT directly
// For Basic: base64-decodes, splits on ':', takes the password portion (JWT)
```

Critically, **Nix does not use `access-tokens` for binary cache authentication**. The `access-tokens` setting (`nix.settings.access-tokens` / `nix.extraOptions`) is designed for fetcher authentication (e.g., `fetchGit` to private GitHub repos). Binary cache auth uses the netrc mechanism (`netrc-file` setting or default `~/.config/nix/netrc`).

### 4.3 Analysis of Our Current Configuration

Our `shared-cli-configuration.nix` currently:

```nix
# Line 19-22: Adds the cache as a substituter (correct for pulling)
nix.settings.extra-substituters = [
  "http://nas:8280/2143nix"    # ← correct URL for the binary cache endpoint
];

# Lines 396-401: Attempts to configure auth via access-tokens (INCORRECT mechanism)
nix.extraOptions = ''
  !include /run/agenix/attic-access-tokens
'';

# Lines 403-413: Generates the access-tokens file
# printf 'access-tokens = nas=%s\n' "$(cat /run/agenix/attic-admin-token)"

# Lines 378-391: atic login systemd oneshot (correct for CLIENT pushing)
# ExecStart = attic login nas http://nas:8280 "$(cat /run/agenix/attic-admin-token)"

# Lines 417-427: attic watch-store systemd daemon (correct for pushing)
# ExecStart = attic watch-store 2143nix
```

**Problems identified:**

1. **No `trusted-public-keys` configured.** Nix requires the cache's public key to verify signatures on downloaded store paths. Without it, Nix will refuse to substitute from the cache even if authentication works. The public key can be obtained via `attic cache info 2143nix` and should be added as `nix.settings.extra-trusted-public-keys` or via `attic use` (which does it automatically).

2. **`access-tokens` setting is ineffective for binary cache auth.** Nix's HTTP binary cache store does not read from `access-tokens`; it reads from the netrc file. The `access-tokens = nas=<TOKEN>` line in `/run/agenix/attic-access-tokens` is wasted — Nix sends unauthenticated requests to the cache, resulting in 401 errors if the cache is private, or successful but anonymous pulls if the cache is public.

3. **No netrc file configured for Nix.** The attic client's `attic login` stores credentials in `~/.config/attic/config.toml` (for attic client use), but Nix cannot read that format. Nix needs `~/.config/nix/netrc` (or a custom path via `netrc-file`) with `machine nas password <JWT>`.

### 4.4 Recommended Fix

**Option A: Use `attic use` (imperative, simplest)**

After `atic login` succeeds, run `attic use 2143nix`. This automatically configures:
- `substituters` with `http://nas:8280/2143nix`
- `trusted-public-keys` with the cache's public key
- `~/.config/nix/netrc` with `machine nas password <JWT>`
- `netrc-file` pointing to the netrc

This can be added as an `ExecStartPost` in the `attic-login` systemd service, or as a separate oneshot that runs after login.

**Option B: Declarative NixOS configuration (preferred for reproducibility)**

```nix
# In shared-cli-configuration.nix, replace the access-tokens mechanism with:

# 1. Keep the substituter (already correct)
nix.settings.extra-substituters = [
  "http://nas:8280/2143nix"
];

# 2. Add the trusted public key (get from `attic cache info 2143nix`)
nix.settings.extra-trusted-public-keys = [
  "2143nix:<PUBLIC_KEY_FROM_CACHE_INFO>"
];

# 3. Create a netrc file from the agenix secret
nix.settings.netrc-file = "/run/agenix/attic-netrc";

system.activationScripts.atticNetrc = {
  text = ''
    printf 'machine nas password %s\n' "$(cat /run/agenix/attic-admin-token)" \
      > /run/agenix/attic-netrc
    chmod 0400 /run/agenix/attic-netrc
  '';
};

# 4. Remove or replace the access-tokens include
# (nix.extraOptions with !include /run/agenix/attic-access-tokens)
```

**Critical caveat:** The `netrc-file` path must be an **absolute path** and `~` is not resolved. The agenix ramfs path `/run/agenix/attic-netrc` satisfies this requirement. However, Nix reads `netrc-file` at daemon start time and may not re-read it. On NixOS, the nix-daemon would need a restart after the activation script runs. Alternatively, write the netrc to a persistent location like `/etc/nix/netrc` (agenix-decrypted at boot) and set `netrc-file = "/etc/nix/netrc"`.

**Note on `access-tokens` vs `netrc-file` in Nix source:** The `access-tokens` setting in Nix is processed by the fetcher subsystem (`libstore/download.cc` in the Nix C++ codebase) for `fetchGit`, `fetchurl`, etc. The HTTP binary cache store (`libstore/http-binary-cache-store.cc`) uses the `netrc-file` mechanism independently. These are separate code paths — configuring one does not affect the other.

**Note on the attic `token-file` config option:** While the `attic login` CLI command only stores tokens inline in `~/.config/attic/config.toml`, the config file format supports `token-file` as an alternative to `token`:

```toml
[servers.nas]
endpoint = "http://nas:8280"
token-file = "/run/agenix/attic-admin-token"
```

This would allow `attic` commands to read the token directly from the agenix mount, avoiding the need to store it in the attic config at all. However, `attic login` does not currently write this format — it would need to be managed manually or via a config template.

## 5. Bibliography

Zhaofeng Li. (n.d.). *Attic token module source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/lib.rs

Zhaofeng Li. (n.d.). *Attic token utility source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/util.rs

Zhaofeng Li. (n.d.). *Attic client configuration source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/config.rs

Zhaofeng Li. (n.d.). *Attic login command source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/login.rs

Zhaofeng Li. (n.d.). *Attic use command source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/use.rs

Zhaofeng Li. (n.d.). *Attic Nix configuration module source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_config.rs

Zhaofeng Li. (n.d.). *Attic Nix netrc module source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_netrc.rs

Zhaofeng Li. (n.d.). *Attic server HTTP access control source code*. GitHub. https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/access/http.rs

Zhaofeng Li. (2025, September 24). *Tutorial — Attic*. Attic Documentation. https://docs.attic.rs/tutorial.html

Zhaofeng Li. (n.d.). *attic CLI reference — Attic*. Attic Documentation. https://docs.attic.rs/reference/attic-cli.html

Zhaofeng Li. (n.d.). *User Guide — Attic*. Attic Documentation. https://docs.attic.rs/user-guide/index.html

Zhaofeng Li. (n.d.). *atticadm CLI reference — Attic*. Attic Documentation. https://docs.attic.rs/reference/atticadm-cli.html

Zhaofeng Li. (n.d.). *FAQs — Attic*. Attic Documentation. https://docs.attic.rs/faqs.html

NixOS Foundation. (n.d.). *nix.conf — Nix Reference Manual (v2.22)*. Nix Documentation. https://nix.dev/manual/nix/2.22/command-ref/conf-file.html

justus.pw. (n.d.). *Attic on Nix Darwin*. https://www.justus.pw/wiki/Attic_on_Nix_Darwin

Zhaofeng Li. (n.d.). *Attic — Multi-tenant Nix Binary Cache*. GitHub. https://github.com/zhaofengli/attic
