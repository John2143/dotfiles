{
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
in {
  # ── Nix substituter ────────────────────────────────────────────────
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

  # ── Admin token (age-encrypted) ────────────────────────────────────
  age.secrets.attic-admin-token = {
    file = ../../secrets/attic-admin-token.age;
    mode = "0400";
    owner = "john";
    group = "users";
  };

  # ── attic login (oneshot, runs before watch-store) ─────────────────
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

  # ── netrc (nix binary-cache auth) ─────────────────────────────────
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

  # ── watch-store (pushes newly-built paths to cache) ────────────────
  systemd.user.services.attic-watch-store = {
    description = "Attic Nix cache upload daemon";
    requires = [ "attic-login.service" ];
    after = [ "attic-login.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store ${cacheName} --ignore-upstream-cache-filter";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStopSec = 10;
    };
    wantedBy = [ "default.target" ];
  };
}
