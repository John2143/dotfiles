{
  config,
  pkgs,
  lib,
  ...
}: let
  cacheName = "2143nix";
  # Resolve via Tailscale MagicDNS ("nas" -> 100.64.0.14), NOT mDNS
  # "nas.local": mDNS is flaky over WiFi, yields AAAA-only records on
  # arch, and the NAS itself cannot resolve its own .local name, so its
  # own builds could never read from its own cache. MagicDNS resolves on
  # every host — including the NAS, via its /etc/hosts 127.0.0.2 nas.
  server = "nas";
  endpoint = "http://nas:8280";

  cfg = config.attic.pushHook;

  # ── post-build-hook (pushes newly-built paths to cache) ────────────
  # Runs as root, once per completed derivation. Replaces the
  # `attic watch-store` daemon, which exited on its own after ~20-45 s on
  # the CI runner and uploaded almost nothing (15 paths in 8 h).
  pushHook = pkgs.writeShellScript "attic-post-build-hook" ''
    # Never fails or stalls the build: an unreachable NAS must not mark a
    # derivation as failed, nor add a timeout to every build on a laptop
    # that is off the tailnet. The cache is private, so reachability is
    # probed with a bare TCP connect — an HTTP probe would 401 and look
    # like an outage.
    export XDG_CONFIG_HOME=/etc
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    timeout 3 ${pkgs.bash}/bin/bash -c "exec 3<>/dev/tcp/${server}/8280" 2>/dev/null || exit 0
    printf '%s\n' $OUT_PATHS \
      | timeout 300 ${pkgs.attic-client}/bin/attic push ${cacheName} --stdin >/dev/null 2>&1 || true
  '';

  # ── cache semantics (measured 2026-11-10) ──────────────────────────
  # Attic is not a plain binary cache: it serves /_api/v1 and exposes no PUT
  # endpoint, so `nix copy --to ${endpoint}/${cacheName}` fails with HTTP 405.
  # Upload with `attic push ${cacheName} <paths>` (closure by default,
  # --no-closure to restrict), which is what the hook above does per derivation.
  #
  # Do not probe presence with `nix path-info --store <url> <path>`: it answers
  # "path ... is not valid" for anything it cannot resolve, which reads as
  # "missing" whether the path is absent or the query failed. Ask the narinfo
  # endpoint instead — `curl -sS --netrc-file /run/agenix/attic-netrc -o
  # /dev/null -w '%{http_code}' <url>/<hash>.narinfo` -> 200 present, 404 absent.
  #
  # The cache declares cache.nixos.org as an upstream key, so paths available
  # upstream are deliberately not stored: a 404 at attic for e.g. the kernel is
  # expected and costs nothing, since cache.nixos.org serves it. Entries are
  # retained for 90 days (Retention Period 7776000) unless pushed again, so a
  # path last built long ago can legitimately be gone.
in {
  options.attic.pushHook.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Upload paths built on this host to the Attic cache from Nix's post-build-hook.";
  };

  config = {
    # ── Nix substituter ──────────────────────────────────────────────
    # Our Attic cache is primary (first in list = highest priority).
    # cache.nixos.org is a fallback so we can still build when the
    # NAS is unreachable or cache entries are missing.
    nix.settings.substituters = lib.mkForce [
      "${endpoint}/${cacheName}"
      "https://cache.nixos.org"
    ];
    nix.settings.trusted-public-keys = [
      "2143nix:zqt4fb8dINfCsQPqWQcggPm2eqk9RpotNh1u8QKRQVA="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # ── Admin token (age-encrypted) ──────────────────────────────────
    age.secrets.attic-admin-token = {
      file = ../../secrets/attic-admin-token.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

    # ── Push hook ────────────────────────────────────────────────────
    # The CI runner's job process runs as `github-runner` (home
    # /var/empty), so it cannot keep a per-user attic config; this shared
    # file is what both it and the root hook read.
    environment.etc."attic/config.toml".text = ''
      default-server = "${server}"
      [servers.${server}]
      endpoint = "${endpoint}"
      token-file = "${config.age.secrets.attic-admin-token.path}"
    '';

    nix.settings.post-build-hook = lib.mkIf cfg.enable (toString pushHook);

    # ── attic login (oneshot, for interactive `attic push` in a shell) ─
    systemd.user.services.attic-login = {
      description = "Attic cache login";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "attic-login" ''
          exec ${pkgs.attic-client}/bin/attic login ${server} ${endpoint} "$(cat /run/agenix/attic-admin-token)"
        '';
        RemainAfterExit = true;
        TimeoutStopSec = 10;
      };
      wantedBy = [ "default.target" ];
    };

    # ── netrc (nix binary-cache auth) ───────────────────────────────
    nix.settings.netrc-file = "/run/agenix/attic-netrc";

    system.activationScripts.atticNetrc = {
      deps = [ "agenix" ];
      text = ''
        printf 'machine %s password %s\nmachine nas.local password %s\nmachine localhost password %s\n' \
          ${lib.escapeShellArg server} \
          "$(cat /run/agenix/attic-admin-token)" \
          "$(cat /run/agenix/attic-admin-token)" \
          "$(cat /run/agenix/attic-admin-token)" \
          > /run/agenix/attic-netrc
        chmod 0444 /run/agenix/attic-netrc
      '';
    };
  };
}
