{pkgs, ...}: let
  pin = names: key: {
    hostNames = names;
    publicKey = "ssh-ed25519 ${key}";
  };
in {
  # fleet-patch runs agentless with StrictHostKeyChecking=yes: an unknown or changed
  # host key is a hard failure. Keys collected 2026-10-30, cross-checked LAN vs tailnet.
  programs.ssh.knownHosts = {
    big = pin ["big" "192.168.5.68"] "AAAAC3NzaC1lZDI1NTE5AAAAIDTQYNKdAp9+7zT/R5kC8QlzowHqrNss6iQNOi7xnGhF";
    pite = pin ["pite" "192.168.5.9"] "AAAAC3NzaC1lZDI1NTE5AAAAID1rtTicPGEiIp+A6/cYEJLK6LBdAyPl+ks2IZmkO9Xr";
    github = pin ["github" "192.168.5.108"] "AAAAC3NzaC1lZDI1NTE5AAAAIAl8MEtiXc7gINAJioWGAKExtBn6oMsAfMnG45WGD1vA";
    steam = pin ["steam" "192.168.5.122"] "AAAAC3NzaC1lZDI1NTE5AAAAIEBiCzwwquvaj3Uc+ubd5mtab/GgxpfbUHzkCyfxeWJN";
    mirror = pin ["mirror" "192.168.5.123"] "AAAAC3NzaC1lZDI1NTE5AAAAIDNhW7W6JJH5ZF24KkaAKZT5zcaxAnq74BQJNDYtjOYE";
    vpin = pin ["vpin" "192.168.5.118"] "AAAAC3NzaC1lZDI1NTE5AAAAIKWjl1w13Nce4AQ2oEl/QjyBImVROff3mafjLNhL5uEq";
    secu = pin ["secu" "192.168.5.140"] "AAAAC3NzaC1lZDI1NTE5AAAAIMu+LVq4TXVmHfWQm0ilbcBKFuk/Gc5PatuvZwKT4UEQ";
    arch = pin ["arch" "192.168.5.76"] "AAAAC3NzaC1lZDI1NTE5AAAAIBZx+UeGOlNlL08WTwYps1TkGZkedaEmUuZ3Iy4O5gK2";
    closet = pin ["closet" "192.168.5.36"] "AAAAC3NzaC1lZDI1NTE5AAAAIDo8+Ir6w4D3PKauYj+GYPb4CMRh8oSwqslhiyzJqIEN";
    nas = pin ["nas" "192.168.5.175"] "AAAAC3NzaC1lZDI1NTE5AAAAIMvQyGzoOh27IaKrCVPamoObXNdk0RweJ6IBx9kN0kQJ";
    bigp = pin ["bigp" "192.168.5.19"] "AAAAC3NzaC1lZDI1NTE5AAAAIM4mwRPSzY5t7ysDC/E6CEBjyYBpK8bNYN/re61Z7Hbi";
    unifi-os = pin ["unifi-os" "192.168.5.30"] "AAAAC3NzaC1lZDI1NTE5AAAAIN00L1wDmCH1slyib2hW9YA3KNJAGd+kov3fCAgmqII6";
  };

  systemd.services.fleet-patch = {
    description = "Fleet patch: bump nixpkgs, switch every NixOS host, report";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    # The switch on office runs inside this unit; it must not restart or stop it.
    restartIfChanged = false;
    onFailure = ["notify-failure@fleet-patch.service"];
    path = with pkgs; [bash coreutils git nix openssh curl util-linux gnused gnugrep];
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Environment = "HOME=/home/john";
      # ExecStart, not `script`: NixOS wraps `script` in `set -e`, which would abort
      # mid-fleet on the first failed command substitution with no report.
      ExecStart = "${pkgs.bash}/bin/bash ${../../scripts/fleet-patch.sh}";
      TimeoutStartSec = "6h";
      Nice = 10;
    };
  };

  systemd.timers.fleet-patch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-* 04:00:00";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };

  # Generic "unit failed" push. Used by fleet-patch and renovate.
  systemd.services."notify-failure@" = {
    description = "ntfy alert for failed unit %i";
    path = [pkgs.curl];
    scriptArgs = "%i";
    serviceConfig = {
      Type = "oneshot";
      User = "john";
    };
    script = ''
      set -a; . /run/agenix/ntfy-topic-url; set +a
      curl -fsS -m 20 -H "Title: $1 failed on office" -H "Priority: high" -H "Tags: rotating_light" \
        -d "journalctl -u $1 -n 200 on office" "$NTFY_TOPIC_URL"
    '';
  };
}
