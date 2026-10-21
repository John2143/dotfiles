# pite — UPS-protected Raspberry Pi (3.7 GB RAM, 238 GB SD)
#
# Roles: k3s agent, Prometheus server (2d retention), Alertmanager,
# Blackbox exporter, nginx status page.
#
# Alerting: ntfy.sh only — ntfy + Home Assistant ruled out per user.
{
  config,
  pkgs,
  lib,
  ...
}: {

  # k3s/flannel forwards pod traffic; this was previously enabled indirectly
  # by the Mullvad module's Tailscale routing mode.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  # Keep plain tailnet access and its UDP port, but retire pite as an exit node.
  services.tailscale = {
    openFirewall = true;
    extraSetFlags = ["--advertise-exit-node=false"];
  };

  # Node identity and shared flags come from modules/k3s-net.nix.
  custom.k3sNet = {
    ipv4 = "192.168.5.9";
    # end0's EUI-64 address is fd00:1::dea6:32ff:fe25:516e. Auto-detection had
    # latched onto a stable-privacy address that later changed (stale InternalIP).
    ipv6Mac = "dc:a6:32:25:51:6e";
    # Reserve 1 core and 1Gi for system daemons — leaves 3 cores / 2.7Gi allocatable for workloads
    systemReserved = "cpu=1,memory=1Gi";
    # Never a MetalLB announcer (1G Pi running Mullvad). Registration-time
    # only: k3s applies --node-label when the node first joins; the running
    # node is labelled with kubectl (argo docs/node-maintenance.md).
    nodeLabels = ["node.kubernetes.io/exclude-from-external-load-balancers=true"];
  };
  # ── Agenix Secrets ─────────────────────────────────────────────
  # ntfy topic URL for Alertmanager notifications.
  age.secrets.ntfy-topic-url = {
    file = ../secrets/ntfy-topic-url.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # Shared with statusd on the droplet: it stores only the SHA-256 of this
  # token, and every report/backfill/snapshot request carries it.
  age.secrets.status-report-token = {
    file = ../secrets/status-report-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # ── Firewall — Prometheus + Alertmanager + Blackbox + nginx ────
  networking.firewall.allowedTCPPorts = [
    9090 # Prometheus
    9093 # Alertmanager (internal only — bound to 127.0.0.1)
    9115 # Blackbox exporter probes
    3030 # nginx status page
    5580 # matter-server (hostNetwork pod)
  ];
  networking.firewall.allowedUDPPorts = [
    5540 # matter-server (hostNetwork pod)
  ];

  # ── Prometheus — SERVER mode, 2d retention ─────────────────────
  services.prometheus = {
    enable = true;
    enableReload = true; # SIGHUP reload — zero downtime on config changes
    retentionTime = "2d";
    globalConfig = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };
    scrapeConfigs = [
      # Home cluster nodes (LAN)
      {
        job_name = "home-nodes";
        static_configs = [
          {
            targets = [
              "closet.local:9100" # closet
              "arch.local:9100" # arch
              "nas.local:9100" # nas
              "office.local:9100" # office
              "big.local:9100" # big
              "localhost:9100" # pite itself — pite.local does not resolve, keep localhost
              "github.local:9100" # github runner VM (github-nixos)
              "secu.local:9100" # secu (Camera NVR) — depends on 5b
              "vpin.local:9100" # vpin (Mullvad exit)
              "mirror.local:9100" # mirror
            ];
          }
        ];
      }
      # SMART health metrics (smartctl_exporter on :9633) — every host with
      # physical disks. Hosts without ata-* disks serve zero SMART series.
      {
        job_name = "smartctl";
        static_configs = [
          {
            targets = [
              "closet.local:9633" # closet
              "arch.local:9633" # arch
              "nas.local:9633" # nas
              "office.local:9633" # office
              "big.local:9633" # big
              "secu.local:9633" # secu — depends on 5b
            ];
          }
        ];
      }
      # etcd members (k3s --etcd-expose-metrics, see modules/k3s-server.nix).
      # etcd binds metrics to each server's IPv4 node IP only, so use literal
      # IPs (*.local may resolve to IPv6). `node` = Kubernetes node name.
      {
        job_name = "etcd";
        static_configs = [
          {
            targets = ["192.168.5.36:2381"];
            labels.node = "closet";
          }
          {
            targets = ["192.168.5.76:2381"];
            labels.node = "arch";
          }
          {
            targets = ["192.168.5.175:2381"];
            labels.node = "nas";
          }
        ];
      }
      # Blackbox probes — public endpoints
      {
        job_name = "blackbox-http";
        metrics_path = "/probe";
        params.module = ["http_2xx"];
        static_configs = [
          {
            targets = [
              "https://john2143.com"
              "https://2143.me/user"
              "https://2143.me"
              "https://i.2143.me"
              "https://files.john2143.com"
              "https://status-origin.2143.me/healthz" # the droplet itself — pages via BlackboxProbeFailed
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
      # Blackbox TCP probes — services + self-monitoring
      {
        job_name = "blackbox-tcp";
        metrics_path = "/probe";
        params.module = ["tcp_connect"];
        static_configs = [
          {
            targets = [
              "192.168.6.16:30033" # TeamSpeak file transfer
              "192.168.5.9:9100" # self (node_exporter)
              # MetalLB service IPs (post-migration 2026-08-04) — per-service status
              "192.168.6.6:443" # traefik (HTTPS)
              "192.168.6.13:25" # stalwart (SMTP)
              "192.168.6.19:1883" # mosquitto
              "192.168.6.20:7233" # temporal-frontend
              "192.168.6.23:8080" # mimir-lb
              "192.168.6.24:3100" # loki-push-lb
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
    ];
    # Remote write to home-cluster Mimir for long-term storage.
    # Uses the MetalLB service IP (192.168.6.23 is mimir-lb).
    remoteWrite = [
      {
        url = "http://192.168.6.23:8080/api/v1/push";
        headers = {"X-Scope-OrgID" = "anonymous";};
      }
    ];
    # Read kube-state-metrics series back from Mimir for the "loadbalancers"
    # alert group. required_matchers scopes remote reads to selectors that
    # carry job="kube-state-metrics"; read_recent is required because these
    # series never exist in local storage.
    remoteRead = [
      {
        name = "mimir-ksm";
        url = "http://192.168.6.23:8080/prometheus/api/v1/read";
        headers = {"X-Scope-OrgID" = "anonymous";};
        read_recent = true;
        required_matchers = {job = "kube-state-metrics";};
        remote_timeout = "30s";
      }
    ];
    ruleFiles = let
      alertRules = pkgs.writeText "alerts.yml" ''
        groups:
          - name: infrastructure
            rules:
              - alert: NodeDown
                expr: up == 0
                for: 5m
                labels: { severity: critical }
                annotations: { summary: "Node {{ $labels.instance }} is down" }
              - alert: DiskFull
                expr: node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1
                for: 5m
                labels: { severity: critical }
                annotations: { summary: "Disk on {{ $labels.instance }} is >90% full" }
              - alert: BlackboxProbeFailed
                expr: probe_success == 0
                for: 2m
                labels: { severity: warning }
                annotations: { summary: "Probe {{ $labels.instance }} failed" }
              - alert: CertExpiring
                expr: probe_ssl_earliest_cert_expiry - time() < 604800
                labels: { severity: critical }
                annotations: { summary: "TLS cert for {{ $labels.instance }} expires within 7 days" }
              - alert: DeadMansSwitch
                expr: vector(1)
                labels: { severity: warning }
                annotations: { summary: "pite Prometheus is alive — this alert should always fire" }
              - alert: HighLoad
                expr: node_load1 / count without(cpu,mode) (node_cpu_seconds_total{mode="idle"}) > 2
                for: 15m
                labels: { severity: warning }
                annotations: { summary: "{{ $labels.instance }} load > 2× CPU count for 15m" }
              - alert: Rebooting
                expr: node_boot_time_seconds > 0 and (time() - node_boot_time_seconds) < 300
                labels: { severity: info }
                annotations: { summary: "{{ $labels.instance }} rebooted within last 5m" }
          - name: loadbalancers
            rules:
              - alert: LoadBalancerNoIP
                expr: 'max by (namespace, service) (kube_service_spec_type{job="kube-state-metrics",type="LoadBalancer"}) unless on (namespace, service) max by (namespace, service) (kube_service_status_load_balancer_ingress{job="kube-state-metrics"})'
                for: 5m
                labels: { severity: critical }
                annotations: { summary: "LoadBalancer {{ $labels.namespace }}/{{ $labels.service }} has no IP: MetalLB refused or lost the allocation, so the VIP is not announced" }
              - alert: LoadBalancerNoReadyEndpoints
                expr: '(max by (namespace, service) (kube_service_spec_type{job="kube-state-metrics",type="LoadBalancer"}) unless on (namespace, service) max by (namespace, service) (label_replace(kube_endpointslice_endpoints{job="kube-state-metrics",ready="true"}, "service", "$1", "endpointslice", "(.+?)(-[a-z0-9]{5})?"))) and on (namespace, service) (max by (namespace, service) (label_replace(kube_endpointslice_endpoints{job="kube-state-metrics"}, "service", "$1", "endpointslice", "(.+?)(-[a-z0-9]{5})?")) or max by (namespace, service) (label_replace(max_over_time(kube_endpointslice_endpoints{job="kube-state-metrics",ready="true"}[1h]), "service", "$1", "endpointslice", "(.+?)(-[a-z0-9]{5})?")))'
                for: 5m
                labels: { severity: critical }
                annotations: { summary: "LoadBalancer {{ $labels.namespace }}/{{ $labels.service }} has no ready endpoints: MetalLB withdrew its VIP" }
      '';
    in [alertRules];
    alertmanagers = [
      {
        static_configs = [{targets = ["127.0.0.1:9093"];}];
      }
    ];
  };

  # Ensure runtime directories exist.
  # NOTE: /run/alertmanager is deliberately NOT listed here — the alertmanager
  # unit runs as a DynamicUser, so that directory must be created and owned by
  # systemd via RuntimeDirectory (see the unit below). A root-owned tmpfiles
  # entry made preStart unable to write config.yml, which stopped the service
  # from ever starting (start-limit-hit) and silenced every ntfy alert.
  systemd.tmpfiles.rules = [
    "d /var/www/status 0755 root root -"
    "d /var/lib/status-page 0755 root root -"
  ];

  # ── Alertmanager — ntfy-only, config generated at runtime ──────
  systemd.services.alertmanager = {
    # ⚠ Do NOT use `sed -i` in this preStart. The nixpkgs prometheus-alertmanager
    # module sandboxes the unit with `SystemCallFilter=@system-service ~@privileged`,
    # and GNU sed's in-place mode needs chown(2)/xattr on its temp file to preserve
    # the original's attributes — those live in @privileged, so seccomp kills sed
    # with SIGSYS ("Bad system call (core dumped)"), preStart fails, and systemd
    # gives up with start-limit-hit. The result is silent: alertmanager never runs
    # and no ntfy notification is ever delivered for any alert.
    # The unquoted heredoc below lets the shell expand $NTFY_URL instead.
    preStart = ''
          # Accept a sourced "KEY=value" secret, or any file containing a URL token.
          NTFY_URL=$(. "$CREDENTIALS_DIRECTORY/ntfy-topic-url" 2>/dev/null && printf '%s' "''${NTFY_TOPIC_URL:-}")
          if [ -z "$NTFY_URL" ]; then
            NTFY_URL=$(${pkgs.gnugrep}/bin/grep -oE 'https://[A-Za-z0-9._~/-]+' "$CREDENTIALS_DIRECTORY/ntfy-topic-url" 2>/dev/null | head -1 || true)
          fi
          case "$NTFY_URL" in
            https://*) : ;;
            *)
              echo "alertmanager: could not resolve a ntfy topic URL from the ntfy-topic-url secret" >&2
              exit 1
              ;;
          esac

          cat > /run/alertmanager/config.yml <<CONFIGEOF
      global:
        resolve_timeout: 5m
      route:
        receiver: ntfy
        group_by: [alertname]
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
        routes:
          - receiver: blackhole
            matchers:
              - alertname="DeadMansSwitch"
      receivers:
        - name: ntfy
          webhook_configs:
            - url: "$NTFY_URL"
              send_resolved: true
        - name: blackhole
      CONFIGEOF
    '';
    serviceConfig = {
      # Owned by the DynamicUser; systemd creates it before preStart runs.
      RuntimeDirectory = "alertmanager";
      # The secret is mode 0400 root:root and this unit is a DynamicUser, so it
      # cannot read the file itself — systemd copies it in as a credential.
      LoadCredential = [ "ntfy-topic-url:${config.age.secrets.ntfy-topic-url.path}" ];
      # storage.path must match this unit's StateDirectory (/var/lib/alertmanager).
      # /var/lib/prometheus/alertmanager does not exist — that was the second
      # failure waiting behind the config-write problem.
      ExecStart = lib.mkForce
        "${pkgs.prometheus-alertmanager}/bin/alertmanager --config.file=/run/alertmanager/config.yml --storage.path=/var/lib/alertmanager --web.listen-address=127.0.0.1:9093";
    };
  };

  services.prometheus.alertmanager = {
    enable = true;
    # Minimal valid config — the preStart above generates the real config
    # with secrets substituted at runtime. This dummy passes the build-time
    # validation check but is replaced at service start.
    configText = ''
      global: { resolve_timeout: 5m }
      route: { receiver: dummy }
      receivers: [{ name: dummy }]
    '';
  };

  # ── Blackbox Exporter ──────────────────────────────────────────
  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = pkgs.writeText "blackbox.yml" ''
      modules:
        http_2xx:
          prober: http
          timeout: 10s
          http:
            valid_status_codes: [200, 301, 302, 403]
            tls_config: { insecure_skip_verify: false }
        tcp_connect:
          prober: tcp
          timeout: 5s
    '';
  };

  # ── Status Page (nginx on :3030) ───────────────────────────────
  services.nginx = {
    enable = true;
    virtualHosts."status" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 3030;
        }
      ];
      root = "/var/www/status";
      extraConfig = ''
        # Auto-refresh every 30s
        add_header Cache-Control "no-cache, must-revalidate";
      '';
    };
  };
  # Status page generator — Python script queries Prometheus + Mimir + kubectl
  systemd.services.status-page = {
    description = "Generate enhanced status page HTML";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = [pkgs.python3 pkgs.kubectl];
    script = ''
      ${pkgs.python3}/bin/python3 ${./status-page/generate.py}
    '';
  };

  systemd.timers.status-page = {
    description = "Regenerate status page every 30s";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:*:0/30";  # every 30 s at :00 and :30 — wall-clock, survives rebuilds
      Persistent = true;
    };
  };

  # ── Report LAN checks to the status droplet ────────────────────
  # statusd probes the websites from outside; these are the checks only pite can
  # make. AccuracySec matters: the old status-page timer above inherits systemd's
  # 1-minute accuracy, so :00/:30 runs coalesce. Same calendar, 1 s accuracy here.
  systemd.services.status-report = {
    description = "Report LAN checks to status-origin.2143.me";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = [pkgs.python3];
    script = "python3 ${./status-page/report.py} --token-file ${config.age.secrets.status-report-token.path}";
  };

  systemd.timers.status-report = {
    description = "Report LAN checks every 30s";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:*:0/30";
      AccuracySec = "1s";
      Persistent = true;
    };
  };

  # Runs once, by hand, after the first deploy: 29 days of history from Mimir.
  # RemainAfterExit keeps `systemctl start` idempotent; rerunning is safe anyway.
  systemd.services.status-report-backfill = {
    description = "One-shot history backfill from Mimir into statusd";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
    };
    path = [pkgs.python3];
    script = "python3 ${./status-page/report.py} --token-file ${config.age.secrets.status-report-token.path} --backfill 29";
  };

  # History durability: the droplet keeps hourly rows forever, this keeps 30 days
  # of daily snapshots. quick_check before the rename, so a truncated download is
  # never mistaken for a backup. Before the droplet's first 03:30 UTC backup
  # /v1/snapshot answers 404 and this unit fails — expected on day one.
  systemd.services.status-snapshot = {
    description = "Pull the newest statusd snapshot";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "status-snapshots";
    };
    path = [pkgs.curl pkgs.sqlite pkgs.coreutils pkgs.findutils];
    script = ''
      TOKEN=$(cat ${config.age.secrets.status-report-token.path})
      DEST=/var/lib/status-snapshots/history-$(date -u +%Y%m%d).db
      curl -fsS --max-time 120 -H "Authorization: Bearer $TOKEN" \
        https://status-origin.2143.me/v1/snapshot -o "$DEST.tmp"
      test "$(sqlite3 "$DEST.tmp" 'pragma quick_check')" = ok
      mv "$DEST.tmp" "$DEST"
      find /var/lib/status-snapshots -name 'history-*.db' -mtime +30 -delete
    '';
  };

  systemd.timers.status-snapshot = {
    description = "Pull the daily snapshot at 03:50 UTC";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 03:50:00 UTC";
      Persistent = true;
    };
  };
}
