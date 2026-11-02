{config, pkgs, ...}: {
  users.users.renovate = {
    isSystemUser = true;
    group = "renovate";
    home = "/var/lib/renovate";
  };
  users.groups.renovate = {};

  age.secrets.renovate-github-token = {
    file = ../../secrets/renovate-github-token.age;
    owner = "renovate";
    mode = "0400";
  };

  systemd.services.renovate = {
    description = "Self-hosted Renovate for 2143-Labs/argo";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    onFailure = ["notify-failure@renovate.service"];
    path = with pkgs; [bash coreutils git renovate];
    environment = {
      HOME = "/var/lib/renovate";
      RENOVATE_PLATFORM = "github";
      RENOVATE_REPOSITORIES = "2143-Labs/argo";
      RENOVATE_ONBOARDING = "false";
      RENOVATE_BASE_DIR = "/var/lib/renovate/work";
      LOG_LEVEL = "info";
    };
    script = ''
      RENOVATE_TOKEN="$(cat ${config.age.secrets.renovate-github-token.path})"
      export RENOVATE_TOKEN
      exec renovate
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "renovate";
      Group = "renovate";
      StateDirectory = "renovate";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      TimeoutStartSec = "1h";
    };
  };

  systemd.timers.renovate = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:00:00";
      Persistent = true;
    };
  };
}
