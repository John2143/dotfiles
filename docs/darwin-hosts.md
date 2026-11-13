# Darwin hosts (nix-darwin)

Two Macs are declared in `flake.nix`:

| attr | host file | user | purpose |
|---|---|---|---|
| `darwinConfigurations.mac` | `nixos/darwin-configuration.nix` | `jschmidt` | work laptop |
| `darwinConfigurations.macbook` | `nixos/darwin-macbook.nix` + `nixos/home-macbook.nix` | `john` | personal MacBook Pro (M1 Pro) |

## Shared user config

`nixos/home-cli.nix` is platform-neutral: it carries no user paths, and Home
Manager derives `home.username` / `home.homeDirectory` from
`users.users.<name>`. Do not reintroduce `if isDarwin then "jschmidt"` there.

Fish reads `~/.config/fish/host-profile.fish` first (written by Home Manager).
It sets:

- `DOTFILES_PROFILE` — `personal` on macbook; unset on the work Mac.
- `DOTFILES_DARWIN_FLAKE` — `#macbook` or `#mac`.

The Darwin block in `.config/fish/config.fish` runs work-only setup
(`disco.fish`, discovery.com addresses, jdt-language-server) only when
`DOTFILES_PROFILE` is not `personal`.

## Keys and secrets

- Login key: `my-keys` in `flake.nix` (consumed by
  `users.users.<name>.openssh.authorizedKeys.keys`). A new host must also be
  rebuilt into arch/office before it can SSH *out* with that key.
- agenix: per-host age public keys live in `secrets/agenix-rules.nix`
  (`~/.ssh/age` on each host). macbook is granted only
  `llm-runtime-keys` and `llm-admin-keys`; it is not in `allKeys`.
- Re-encrypt after editing rules: `cd secrets && agenix -r -i ~/.ssh/age`.

## Fresh-install gotchas

1. Run the first `darwin-rebuild switch` from **Terminal.app**, not SSH —
   activation uses `launchctl asuser`.
2. `/etc/pam.d/sudo_local` must not exist before the first activation, or
   nix-darwin aborts with "Unexpected files in /etc". Rename it to
   `sudo_local.before-nix-darwin`; nix-darwin recreates it
   (`security.pam.services.sudo_local.touchIdAuth`).
3. `/run` is created from `/etc/synthetic.conf`. If it is missing during
   activation, append `run	private/var/run`, run
   `/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t`, or
   reboot and rerun the switch.
4. New host files must be tracked by git before `nix eval`
   ("Path ... is not tracked by Git"): use `git add -N` for the first
   evaluation.
5. nixbld is gid 350 with this installer; leave `ids.gids.nixbld` unset unless
   `dscl . -read /Groups/nixbld PrimaryGroupID` says otherwise.

## GUI apps and Spotlight

Home Manager's `targets.darwin.linkApps` is **disabled** on macbook. It links
`~/Applications` itself to a directory in `/nix/store`, and Spotlight and
Launchpad never index that volume — no nix GUI app is findable by name.

- Normal GUI apps come from Homebrew casks, which install real bundles into
  `/Applications` (Firefox, Discord, Prism Launcher, krita, obs, vlc, ...).
- `alacritty` and `openrct2` casks are disabled by Homebrew ("does not pass
  the macOS Gatekeeper check"), so they stay nix packages.
  `home.activation.installAppBundles` copies their bundles into
  `~/Applications` as real directories; alacritty's `Contents/MacOS` is a
  relative symlink to `../../../bin` in the store, so the activation replaces
  it with the real binary after copying.
- Copies inherit read-only store permissions; activation chmods `~/Applications`
  writable before replacing anything.
- If a moved bundle is not found by `open -a`, register it with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f <path>`.
