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
  # ── Agenix Secrets ─────────────────────────────────────────────
  # ntfy topic URL for Alertmanager notifications.
  age.secrets.ntfy-topic-url = {
    file = ../secrets/ntfy-topic-url.age;
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
              "192.168.5.36:9100" # closet
              "192.168.5.76:9100" # arch
              "192.168.5.175:9100" # nas
              "192.168.5.209:9100" # office
              "localhost:9100"
            ];
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
              "john2143.com:9987" # TeamSpeak
              "192.168.5.9:9100" # self (node_exporter)
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
    # pite's k3s agent resolves mimir.observability.svc via cluster DNS.
    remoteWrite = [
      {
        url = "http://mimir.observability.svc:8080/api/v1/push";
        headers = {"X-Scope-OrgID" = "anonymous";};
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
      '';
    in [alertRules];
    alertmanagers = [
      {
        static_configs = [{targets = ["127.0.0.1:9093"];}];
      }
    ];
  };

  # Ensure runtime directories exist
  systemd.tmpfiles.rules = [
    "d /run/alertmanager 0755 root root -"
    "d /var/www/status 0755 root root -"
  ];

  # ── Alertmanager — ntfy-only, config generated at runtime ──────
  systemd.services.prometheus-alertmanager = {
    preStart = ''
          NTFY_URL=$(cat /run/agenix/ntfy-topic-url 2>/dev/null || echo "https://ntfy.sh/2143-site-outages")

          cat > /run/alertmanager/config.yml <<'CONFIGEOF'
      global:
        resolve_timeout: 5m
      route:
        receiver: ntfy
        group_by: [alertname]
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
      receivers:
        - name: ntfy
          webhook_configs:
            - url: "NTFY_PLACEHOLDER"
              send_resolved: true
      CONFIGEOF

          ${pkgs.gnused}/bin/sed -i "s|NTFY_PLACEHOLDER|$NTFY_URL|g" /run/alertmanager/config.yml
    '';
    serviceConfig = {
      ExecStart = lib.mkForce [
        ""
        "${pkgs.prometheus-alertmanager}/bin/alertmanager \
          --config.file=/run/alertmanager/config.yml \
          --storage.path=/var/lib/prometheus/alertmanager \
          --web.listen-address=127.0.0.1:9093"
      ];
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

  # ── NixOS Version Metrics (textfile collector) ─────────────────
  systemd.services.nixos-metrics = {
    description = "Write NixOS version to node_exporter textfile";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [pkgs.jq pkgs.coreutils];
    script = ''
      VERSION=$(nixos-version 2>/dev/null | awk '{print $1}')
      REVISION=$(nixos-version --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.nixpkgsRevision // "unknown"')
      mkdir -p /var/lib/node_exporter/textfile
      cat > /var/lib/node_exporter/textfile/nixos.prom <<PROMEOF
      nixos_info{version="$VERSION", revision="$REVISION", hostname="$(hostname)"} 1
      PROMEOF
    '';
  };
  systemd.timers.nixos-metrics = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # Ensure the textfile directory exists for node_exporter
  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=/var/lib/node_exporter/textfile"
  ];
  # ── Blackbox Exporter ──────────────────────────────────────────
  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = pkgs.writeText "blackbox.yml" ''
      modules:
        http_2xx:
          prober: http
          timeout: 10s
          http:
            valid_status_codes: [200, 301, 302]
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

  # Status page generator — queries pite's Prometheus, renders HTML
  systemd.services.status-page = {
    description = "Generate status page HTML";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = [pkgs.jq pkgs.curl];
    script = ''
      OUT="/var/www/status/index.html"

      # Current alerts
      ALERTS=$(${pkgs.curl}/bin/curl -s localhost:9090/api/v1/alerts | \
        ${pkgs.jq}/bin/jq -r '
          .data.alerts[] | select(.status=="firing") |
          "<tr><td class=\"\(.labels.severity)\">\(.labels.alertname)</td><td>\(.annotations.summary // "N/A")</td></tr>"
        ' 2>/dev/null)

      # Target health
      TARGETS_UP=$(${pkgs.curl}/bin/curl -s localhost:9090/api/v1/targets | \
        ${pkgs.jq}/bin/jq '[.data.activeTargets[] | select(.health=="up")] | length')
      TARGETS_DOWN=$(${pkgs.curl}/bin/curl -s localhost:9090/api/v1/targets | \
        ${pkgs.jq}/bin/jq '[.data.activeTargets[] | select(.health=="down")] | length')

      DOWN_HTML=""
      [ "$TARGETS_DOWN" -gt 0 ] && DOWN_HTML=" / <span class='red'>$TARGETS_DOWN down</span>"

      ALERTS_HTML=""
      [ -n "$ALERTS" ] && ALERTS_HTML="<h2>Active Alerts</h2><table>$ALERTS</table>"

      cat > "$OUT" <<EOF
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <title>2143 Status</title>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="30">
        <style>
          body { font-family: system-ui, sans-serif; max-width: 720px; margin: 2em auto; padding: 1em; }
          .green { color: #155724; background: #d4edda; padding: 2px 8px; border-radius: 4px; }
          .red { color: #721c24; background: #f8d7da; padding: 2px 8px; border-radius: 4px; }
          table { border-collapse: collapse; width: 100%; }
          td, th { padding: 6px; border-bottom: 1px solid #ddd; }
          .critical { color: #721c24; font-weight: bold; }
          .warning { color: #856404; }
          .info { color: #0c5460; }
          a { color: #0056b3; }
        </style>
      </head>
      <body>
        <h1>2143 Status</h1>
        <p>Updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")</p>
        <p>Targets: <span class="green">$TARGETS_UP up</span>$DOWN_HTML</p>
        $ALERTS_HTML
        $( [ -z "$ALERTS" ] && echo "<p>No active alerts.</p>" )
        <p style="margin-top:2em;font-size:small">
          <a href="https://grafana.ts.2143.me">Grafana &rarr;</a> —
          <a href="http://pite.local:9090">Prometheus &rarr;</a>
        </p>
      </body>
      </html>
      EOF
    '';
  };

  systemd.timers.status-page = {
    description = "Regenerate status page every 30s";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnUnitActiveSec = "30s";
      OnBootSec = "10s";
      Persistent = true;
    };
  };
}
