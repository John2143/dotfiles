{
  config,
  pkgs,
  lib,
  ...
}: {

  #TODO: Not finished

  # On pite, /run/agenix/llm-runtime-keys decrypts to BAIT values rather than
  # real keys. Same path, same env-var names — but the AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY entries inside are canarytokens.org honeytokens
  # that ping a webhook the moment any code exfiltrates them.
  #
  # Real runtime keys live at the same path on office/arch (defined in
  # nixos/shared-cli-configuration.nix). This declaration only changes which
  # source file gets decrypted into that path on pite.
  age.secrets.llm-runtime-keys.file = lib.mkForce ../secrets/llm-runtime-keys-bait.age;

  # Periodic activity: invoke wrapped third-party binaries with the bait keys
  # in env. Goal is to trigger any payload that scrapes env vars at startup,
  # even if the user doesn't interactively run claude/omp on the canary host.
  # `--version` exits quickly but still runs the binary's init code.
  systemd.services.canary-poke = {
    description = "Invoke wrapped LLM CLIs with bait keys to trip exfil payloads";
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Group = "users";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin HOME=/home/john";
    };
    script = ''
      ${pkgs.coreutils}/bin/timeout 30 /run/current-system/sw/bin/claude --version || true
      ${pkgs.coreutils}/bin/timeout 30 /run/current-system/sw/bin/omp --version || true
    '';
  };

  systemd.timers.canary-poke = {
    description = "Hourly canary activity";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      Persistent = true;
      Unit = "canary-poke.service";
    };
  };
}
