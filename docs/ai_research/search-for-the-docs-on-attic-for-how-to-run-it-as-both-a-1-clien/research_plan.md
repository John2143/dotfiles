# Research Plan: search-for-the-docs-on-attic-for-how-to-run-it-as-both-a-1-clien

## Primary Question
How is Attic (the self-hosted Nix binary cache) configured as both server and client, and is our NixOS dotfiles setup correct — particularly the Nix substituter integration so that `nix` commands (not just `attic watch-store`) can pull from the cache?

## Context
It seems we got stuck in a loop in the previous run. I believe there is a better way to integrate attic into our binary cache as a client like on office/arch. I think our setup on nas is correct.

Our setup:
- **NAS** runs `atticd` at `http://nas:8280`, serving cache `2143nix`, with JWT auth (server-side `attic-jwt-secret.age`)
- **Clients** (office, arch, closet, etc.) have `attic-admin-token.age` decrypted via agenix
- Clients run `attic login nas http://nas:8280 $TOKEN` (systemd oneshot) and `attic watch-store 2143nix` (systemd daemon) — this handles **pushing** to the cache
- `nix.settings.extra-substituters = ["http://nas:8280/2143nix"]` adds it as a binary cache for **pulling**
- But Nix's `access-tokens` setting appears to send HTTP Basic auth, while atticd expects Bearer tokens → resulting in 401 when Nix tries to pull

## Sub-Topics

### Sub-Topic 1: Attic server configuration and auth
- **Slug**: attic-server-auth
- **Perspective**: none
- **Report path**: reports/attic-server-auth_report.md

### Sub-Topic 2: Attic client CLI usage (attic-client login, watch-store, push, pull)
- **Slug**: attic-client-usage
- **Perspective**: none
- **Report path**: reports/attic-client-usage_report.md

### Sub-Topic 3: Nix binary cache integration — how Nix talks to attic as a substituter
- **Slug**: nix-attic-substituter
- **Perspective**: none
- **Report path**: reports/nix-attic-substituter_report.md

### Sub-Topic 4: Attic authentication tokens — Bearer vs Basic, Nix access-tokens compatibility
- **Slug**: attic-auth-mechanism
- **Perspective**: none
- **Report path**: reports/attic-auth-mechanism_report.md
