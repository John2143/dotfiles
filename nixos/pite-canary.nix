{
  config,
  pkgs,
  lib,
  ...
}: {

  # On pite, /run/agenix/llm-runtime-keys decrypts to BAIT values rather than
  # real keys. Same path, same env-var names — but the AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY entries inside are canarytokens.org honeytokens
  # that ping a webhook the moment any code exfiltrates them.
  #
  # Real runtime keys live at the same path on office/arch (defined in
  # nixos/shared-cli-configuration.nix). This declaration only changes which
  # source file gets decrypted into that path on pite.
  # age.secrets.llm-runtime-keys.file = lib.mkForce ../secrets/llm-runtime-keys-bait.age;

  # # Canary timers/services commented out — bait file (llm-runtime-keys-bait.age)
  # # was never created and the feature was never operational.
  # systemd.services.canary-poke = {
  #   description = "Source bait LLM keys and enumerate env to trip exfil payloads";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     User = "john";
  #     Group = "users";
  #     Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin HOME=/home/john";
  #   };
  #   script = ''
  #     if [ -f /run/agenix/llm-runtime-keys ]; then
  #       set -a
  #       . /run/agenix/llm-runtime-keys
  #       set +a
  #       ${pkgs.coreutils}/bin/printenv | ${pkgs.coreutils}/bin/grep -q AWS || true
  #     fi
  #   '';
  # };
  # systemd.timers.canary-poke = {
  #   description = "Hourly canary activity";
  #   wantedBy = ["timers.target"];
  #   timerConfig = {
  #     OnBootSec = "5min";
  #     OnUnitActiveSec = "1h";
  #     Persistent = true;
  #     Unit = "canary-poke.service";
  #   };
  # };
}
