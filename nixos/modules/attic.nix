{
  pkgs,
  lib,
  ...
}: let
  cacheName = "2143nix";
  server = "nas";
  endpoint = "http://nas:8280";
in {
  # ── Nix substituter ────────────────────────────────────────────────
  nix.settings.substituters = lib.mkForce [
    "${endpoint}/${cacheName}"
  ];
  nix.settings.trusted-public-keys = [
    "2143nix:Ysam0ozURtK+1tkP62M6lzbfoi8BVeL6s7ZWJlB6UxE="
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
    };
    wantedBy = [ "default.target" ];
  };

  # ── netrc (nix binary-cache auth) ─────────────────────────────────
  nix.settings.netrc-file = "/run/agenix/attic-netrc";

  system.activationScripts.atticNetrc = {
    deps = [ "agenix" ];
    text = ''
      printf 'machine %s password %s\nmachine localhost password %s\n' \
        ${lib.escapeShellArg server} \
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
    };
    wantedBy = [ "default.target" ];
  };
}
