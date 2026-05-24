# Nix Binary Cache Authentication: Attic Substituter Integration

## 1. Summary

Attic's `attic use` command configures Nix to pull from an Attic binary cache by writing three things to `~/.config/nix/nix.conf`: the `substituters` URL, the cache's `trusted-public-keys` entry, and a `netrc-file` path pointing to `~/.config/nix/netrc`. The actual JWT token is stored in the netrc file as `machine <host> password <jwt_token>` (with no `login` field).

When Nix makes HTTP requests to a binary cache, it delegates to curl, which reads the netrc file. Because the netrc entry has a `password` but no `login`, curl sends an `Authorization: Basic` header where the Base64-decoded payload is `:<jwt_token>` — an empty username, a colon, and the JWT as the password. This is the standard netrc behavior: without a `login`, curl uses an empty username.

Critically, Attic's server (`atticd`) accepts **both** Bearer and Basic authentication. The `parse_authorization_header` function in the `attic_token` crate (source: `token/src/util.rs`) handles both formats: for Bearer tokens it extracts the JWT directly; for Basic auth it Base64-decodes the payload, splits on the colon, and extracts the JWT from the password portion (ignoring the username entirely). This is explicitly documented in `token/src/lib.rs`: "The JWT can be supplied to the server in one of two ways: As a normal Bearer token. As the password in Basic Auth (used by Nix)."

The `nix.settings.access-tokens` setting is **not** designed for binary cache authentication. It is exclusively for Git forge fetchers (GitHub, GitLab, and similar) — the `getAccessToken()` function lives in `src/libfetchers/github.cc` and is used by the VCS fetchers to authenticate flake inputs and `fetchGit`/`fetchurl` calls to private repositories. For GitHub, it sends `Authorization: Bearer <token>`; for GitLab, it supports PAT and OAuth2 formats. It does not inject headers into binary cache HTTP requests made via `HttpBinaryCacheStore`/`FileTransfer`.

Other Nix binary caches follow the same netrc pattern. Cachix's FAQ documents using `curl --netrc-file ~/.config/nix/netrc` for cache authentication. nixbuild.net explicitly distinguishes between `access-tokens` (for s3:// and cachix:// token types used during builds) and `netrc` (for URL fetches during builds), but does not use `access-tokens` as a binary cache substituter auth mechanism.

## 2. Relation to Primary Question

The primary question asks whether the current NixOS dotfiles setup is correct for pulling from the Attic binary cache. This sub-topic definitively answers that the current setup is **incorrect**: the configuration uses `access-tokens = nas=<jwt>` (injected via an agenix `!include`), but `access-tokens` does not apply to binary cache HTTP requests. The correct approach is to use `netrc-file` pointing to a netrc file with `machine nas password <jwt_token>`, which is exactly what `attic use` automates. Atticd accepts the resulting `Authorization: Basic` header natively — no Bearer token workaround is needed.

## 3. Source Evaluation

### Source 1: Attic token crate — `parse_authorization_header`
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/util.rs
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/lib.rs
- **Credibility:** **Primary, official, verified author.** This is the actual source code of the `attic_token` Rust crate in the official Attic repository (zhaofengli/attic). The `parse_authorization_header` function definitively shows both Bearer and Basic auth are accepted, and the `lib.rs` module docstring explicitly states the netrc format to use. This is the highest-quality evidence available.

### Source 2: Attic client — `nix_config.rs` and `nix_netrc.rs`
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_config.rs
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_netrc.rs
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/use.rs
- **Credibility:** **Primary, official, verified author.** These files implement the `attic use` command. They show exactly what gets written to nix.conf (substituter, trusted-public-keys, netrc-file) and netrc (machine + password). No `access-tokens` usage at all.

### Source 3: Attic server — `http.rs` middleware
- **URL:** https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/access/http.rs
- **Credibility:** **Primary, official, verified author.** Shows how the server extracts the Authorization header and passes it to `parse_authorization_header`. Confirms the token ends up in `AuthState` for permission checks.

### Source 4: Nix source — `filetransfer.cc`
- **URL:** https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/filetransfer.cc
- **Credibility:** **Primary, official.** The Nix file transfer implementation. Uses curl under the hood; curl reads netrc files natively to construct Authorization headers. No reference to `access-tokens` in this code path.

### Source 5: Nix manual — `nix.conf` reference
- **URL:** https://nix.dev/manual/nix/2.30/command-ref/conf-file.html
- **Credibility:** **Primary, official, current.** Documents `access-tokens` as: "Access tokens used to access protected GitHub, GitLab, or other locations requiring token-based authentication." Documents `netrc-file` as: "If set to an absolute path to a netrc file, Nix will use the HTTP authentication credentials in this file when trying to download from a remote host through HTTP or HTTPS." The distinction is clear but subtle.

### Source 6: Cachix FAQ
- **URL:** https://docs.cachix.org/faq
- **Credibility:** **Primary, official.** Shows that Cachix uses `--netrc-file ~/.config/nix/netrc` for cache authentication tokens, consistent with the netrc pattern.

### Source 7: nixbuild.net documentation
- **URL:** https://docs.nixbuild.net/settings/
- **Credibility:** **Primary, official.** Explicitly distinguishes `access-tokens` (for s3:// and cachix:// token types used during build execution) from `netrc` tokens (for URL fetches). Reinforces that `access-tokens` is not the mechanism for binary cache substituter auth.

### Source 8: Attic tutorial and user guide
- **URL:** https://docs.attic.rs/tutorial.html
- **URL:** https://docs.attic.rs/user-guide/index.html
- **Credibility:** **Primary, official.** Documents the `attic use` command output and the declarative NixOS configuration pattern (substituters + trusted-public-keys only, notably without auth — implying netrc is handled separately).

### Source 9: Curl netrc behavior — curl GitHub issue
- **URL:** https://github.com/curl/curl/issues/15767
- **Credibility:** **Primary, verified.** Confirms that a netrc entry with `password` but no `login` results in `Authorization: Basic OmZha2U=` (decodes to `:fake` — empty username, colon, password). This is exactly what happens when Attic's netrc entry is used by Nix→curl.

## 4. Conclusions

### Root Cause of the Auth Mismatch

The user's current NixOS configuration (in `omp-config.nix`, lines 393–413) uses `access-tokens = nas=<jwt_token>` injected via agenix. This **does not work** for binary cache requests because:

1. `access-tokens` is implemented in `src/libfetchers/github.cc` and applies only to Git forge fetchers (GitHub/GitLab).
2. Binary cache HTTP requests go through `HttpBinaryCacheStore` → `FileTransfer` → curl, which reads `netrc-file` for authentication — not `access-tokens`.
3. The comment in the config saying "Netrc sends Basic auth, but atticd expects Bearer tokens" is **incorrect**. Atticd accepts both formats, and the Basic auth path is specifically designed for Nix compatibility.

### Correct Configuration

The correct approach (matching what `attic use` automates declaratively) is:

```nix
{
  nix.settings = {
    extra-substituters = [ "http://nas:8280/2143nix" ];
    extra-trusted-public-keys = [ "2143nix:<PUBLIC_KEY>" ];
    netrc-file = "/run/agenix/attic-netrc";
  };

  system.activationScripts.atticNetrc = {
    text = ''
      printf 'machine nas password %s\n' "$(cat /run/agenix/attic-admin-token)" \
        > /run/agenix/attic-netrc
      chmod 0400 /run/agenix/attic-netrc
    '';
  };
}
```

Or, equivalently, run `attic use nas:2143nix` once per machine (after `attic login nas http://nas:8280 <token>`), which writes to `~/.config/nix/nix.conf` and `~/.config/nix/netrc` automatically.

### Key Technical Details

| Mechanism | Sends | Used For | Works for Attic? |
|---|---|---|---|
| `access-tokens` | `Authorization: Bearer <token>` | Git fetchers (GitHub/GitLab) | No — not applied to binary cache requests |
| `netrc-file` (`password` only) | `Authorization: Basic base64(:<token>)` | Binary cache (curl) | **Yes** — atticd accepts this |
| `netrc-file` (`login` + `password`) | `Authorization: Basic base64(<login>:<password>)` | Binary cache (curl) | **Yes** — atticd extracts password portion |
| Direct Bearer header | `Authorization: Bearer <token>` | attic client, curl | **Yes** — atticd accepts this |

### Why the Confusion Exists

The Nix manual's description of `access-tokens` mentions "or other locations requiring token-based authentication," which could be misread as including binary caches. However, the implementation is strictly scoped to fetchers. The `netrc-file` documentation mentions "HTTP authentication credentials" without specifying the format, and the connection to basic-vs-bearer is not obvious from the manual alone.

### Attic's Design is Correct

Attic's architecture intentionally accepts both auth formats. The JWT-as-Basic-password approach is not a hack — it is the documented, tested integration path. The `token/src/lib.rs` module docstring explicitly states: "To add the token to Nix, use the following format in `~/.config/nix/netrc`: `machine attic.server.tld password eyJhb...`"

## 5. Bibliography

1. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `token/src/util.rs` — `parse_authorization_header` function. https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/util.rs

2. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `token/src/lib.rs` — module documentation describing netrc format. https://raw.githubusercontent.com/zhaofengli/attic/main/token/src/lib.rs

3. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `client/src/nix_config.rs` — Nix config file manipulation. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_config.rs

4. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `client/src/nix_netrc.rs` — Netrc file manipulation. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/nix_netrc.rs

5. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `client/src/command/use.rs` — `attic use` command implementation. https://raw.githubusercontent.com/zhaofengli/attic/main/client/src/command/use.rs

6. Zhao, F. L. (2023–2025). *Attic: Multi-tenant Nix Binary Cache* [Source code]. GitHub. `server/src/access/http.rs` — Server-side auth middleware. https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/access/http.rs

7. NixOS Foundation. (2025). *Nix source code — filetransfer.cc*. GitHub. https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/filetransfer.cc

8. NixOS Foundation. (2025). *nix.conf — Nix 2.30.5 Reference Manual*. https://nix.dev/manual/nix/2.30/command-ref/conf-file.html

9. Cachix. (2025). *Frequently Asked Questions — Cachix Documentation*. https://docs.cachix.org/faq

10. nixbuild.net. (2025). *User Settings — nixbuild.net Documentation*. https://docs.nixbuild.net/settings/

11. Zhao, F. L. (2023–2025). *Attic Tutorial*. https://docs.attic.rs/tutorial.html

12. Zhao, F. L. (2023–2025). *Attic User Guide*. https://docs.attic.rs/user-guide/index.html

13. Stenberg, D. (2024). *curl CLI v8.11.1 fails to offer HTTP Basic auth specified in .netrc when invoked with --netrc-optional* [GitHub Issue #15767]. curl/curl. https://github.com/curl/curl/issues/15767

14. NixOS Foundation. (2025). *Nix source code — http-binary-cache-store.cc*. GitHub. https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/http-binary-cache-store.cc
