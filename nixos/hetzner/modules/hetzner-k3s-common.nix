# Hetzner k3s Common — shared k3s + Flannel + ArgoCD + firewall config
#
# Imported by hetzner-k3s-server.nix (adds PowerDNS + PostgreSQL schema on top).
# All 3 server nodes are identical — drop-in replaceable.
#
# Does NOT import PowerDNS or PostgreSQL schema modules (those are in k3s-server).
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./longhorn-host.nix
    ./tailscale.nix
    ./hetzner-split-ip-firewall.nix
  ];

  # agenix secret: k3s cluster token
  age.secrets."hetzner/k3s-token" = {
    file = ../secrets/hetzner/k3s-token.age;
    owner = "root";
    group = "root";
  };

  # k3s — single-node cluster, SQLite backend
  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.age.secrets."hetzner/k3s-token".path;
    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--cluster-cidr=10.42.0.0/16"
      "--service-cidr=10.43.0.0/16"
    ];
  };


  # ── DDoS kernel hardening ──
  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
    "net.ipv4.tcp_max_syn_backlog" = 4096;
    "net.core.somaxconn" = 4096;
  };

  # ── ArgoCD bootstrap ──
  systemd.services.argocd-bootstrap = {
    description = "Install ArgoCD into k3s cluster";
    after = ["k3s.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s pkgs.curl pkgs.git pkgs.kubernetes-helm];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      for i in $(seq 1 30); do
        kubectl get nodes &>/dev/null && break
        sleep 2
      done
      # Install CRDs first (--server-side avoids annotation size limits)
      kubectl apply --server-side --force-conflicts \
        -k https://github.com/argoproj/argo-cd/manifests/crds?ref=stable
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      # Create redis secret with non-empty password (empty password breaks redis config parsing)
      REDIS_PASS=$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | head -c 24)
      kubectl create secret generic argocd-redis -n argocd \
        --from-literal=auth="$REDIS_PASS" \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || true
      # Apply ArgoCD ConfigMap — health check + resource tracking (inline, not from repo)
      kubectl apply -f - <<'CMEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  application.resourceTrackingMethod: annotation+label
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Healthy"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        local h = obj.status.health.status
        if h == "Degraded" then
          hs.status = "Degraded"
          if obj.status.health.message ~= nil then
            hs.message = obj.status.health.message
          end
        end
      end
    end
    return hs
CMEOF
      kubectl rollout restart deployment/argocd-server -n argocd || true
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s || true
      # Apply root Application — wires ArgoCD to the GitOps repo
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/master/argocd/root-app.yaml
      # Install Traefik (Helm) — ingress controller, chart v34 (v35+ has template errors)
      helm repo add traefik https://helm.traefik.io/traefik 2>/dev/null || true
      helm repo update 2>/dev/null || true
      helm upgrade --install traefik traefik/traefik --namespace traefik --create-namespace \
        --version 34.0.0 \
        --set providers.kubernetesIngress.enabled=true \
        --set service.type=ClusterIP \
        --wait --timeout 120s 2>&1 || true
      # Install Longhorn (Helm) — distributed block storage
      helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
      helm repo update 2>/dev/null || true
      helm upgrade --install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace \
        --set persistence.defaultClass=true \
        --set defaultSettings.createDefaultDiskLabeledNodes=true \
        --set defaultSettings.defaultDataPath=/var/lib/longhorn \
        --wait --timeout 120s 2>&1 || true
      # Install ExternalDNS (Helm) — DNS record sync via RFC2136
      helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
      helm repo update 2>/dev/null || true
      kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
      helm upgrade --install external-dns external-dns/external-dns --namespace external-dns \
        --set provider=rfc2136 \
        --wait --timeout 120s 2>&1 || true
      # Patch deployment with RFC2136 args — Helm chart may not pass them correctly
      # (chart v1.21.1+ changed rfc2136 value keys; this ensures args are always set)
      kubectl patch deploy external-dns -n external-dns --type=json -p "[
        {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--rfc2136-host=$(hostname).9s.pics\"},
        {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--rfc2136-port=53\"},
        {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--rfc2136-zone=9s.pics\"},
        {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--rfc2136-tsig-keyname=externaldns\"},
        {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--rfc2136-tsig-secret-alg=hmac-sha256\"}
      ]" 2>&1 || true
      kubectl apply --server-side --force-conflicts -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.1.yaml
      kubectl wait --for=condition=available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s || true
      # cert-manager is now deployed by ArgoCD (Helm chart in wave 0)
    '';
  };



  # ── agenix → Kubernetes Secrets injection ──
  # Decrypts agenix secrets and creates Kubernetes Secrets before ArgoCD syncs.
  # Runs after k3s is ready, before ArgoCD applies the root app.
  # Secrets: rfc2136-credentials, crowdsec-bouncer-key, mongo-creds,
  #   mongo-encryption-key, b2-credentials, seaweedfs-master-key,
  #   rclone-config, healthchecks-url, pdns-postgres-password
  systemd.services.k8s-secrets-bootstrap = {
    description = "Inject agenix secrets into Kubernetes Secrets";
    after = ["k3s.service" "argocd-bootstrap.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      for i in $(seq 1 30); do
        kubectl get nodes &>/dev/null && break
        sleep 2
      done

      # Create namespaces (needed for secrets, ArgoCD wave -2 creates them later)
      for ns in external-dns crowdsec seaweedfs backup monitoring; do
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
      done

      # RFC2136 TSIG key for ExternalDNS
      kubectl create secret generic rfc2136-credentials -n external-dns \
        --from-literal=tsig-key="$(cat ${config.age.secrets."hetzner/powerdns-tsig-key".path})" \
        --dry-run=client -o yaml | kubectl apply -f -

      # CrowdSec bouncer key
      kubectl create secret generic crowdsec-bouncer-key -n crowdsec \
        --from-literal=key="$(head -c 32 /dev/urandom | base64)" \
        --dry-run=client -o yaml | kubectl apply -f -

      # MongoDB credentials
      kubectl create secret generic mongo-creds -n default \
        --from-literal=password="$(cat ${config.age.secrets."hetzner/mongodb-encryption-key".path} | head -c 32)" \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl create secret generic mongo-encryption-key -n default \
        --from-file=encryption.key=${config.age.secrets."hetzner/mongodb-encryption-key".path} \
        --dry-run=client -o yaml | kubectl apply -f -

      # B2 credentials for CNPG and Longhorn backups
      kubectl create secret generic b2-credentials -n default \
        --from-literal=S3_ACCESS_KEY=PLACEHOLDER_B2_KEY \
        --from-literal=S3_SECRET_KEY=PLACEHOLDER_B2_SECRET \
        --dry-run=client -o yaml | kubectl apply -f -

      # SeaweedFS master encryption key
      kubectl create secret generic seaweedfs-master-key -n seaweedfs \
        --from-literal=master.key="$(cat ${config.age.secrets."hetzner/seaweedfs-master-key".path})" \
        --dry-run=client -o yaml | kubectl apply -f -

      # rclone config for backups
      kubectl create secret generic rclone-config -n backup \
        --from-literal=rclone.conf="[b2-crypt]\ntype=crypt\nremote=b2:9s-pics-backups\npassword=$(cat ${config.age.secrets."hetzner/rclone-b2-password".path})" \
        --dry-run=client -o yaml | kubectl apply -f -

      # Healthchecks.io URL (manual — set by user)
      kubectl create secret generic healthchecks-url -n backup \
        --from-literal=HC_URL=https://hc-ping.com/PLACEHOLDER_UUID \
        --dry-run=client -o yaml | kubectl apply -f -

      # PowerDNS PostgreSQL password for CloudNativePG
      kubectl create secret generic pdns-postgres-password -n default \
        --from-literal=password="$(cat ${config.age.secrets."hetzner/postgres-pdns-password".path})" \
        --dry-run=client -o yaml | kubectl apply -f -
      # Temporal PostgreSQL password (generated, used by CNPG Cluster CR)
      kubectl create secret generic temporal-postgres-password -n default \
        --from-literal=password="$(head -c 32 /dev/urandom | base64 | tr -d '\n')" \
        --dry-run=client -o yaml | kubectl apply -f -
    '';
  };


  # Additional age secrets needed by k8s-secrets-bootstrap
  # (powerdns-tsig-key is declared in hetzner-powerdns.nix)
  age.secrets."hetzner/mongodb-encryption-key" = {
    file = ../secrets/hetzner/mongodb-encryption-key.age;
    owner = "root";
    group = "root";
  };
  age.secrets."hetzner/seaweedfs-master-key" = {
    file = ../secrets/hetzner/seaweedfs-master-key.age;
    owner = "root";
    group = "root";
  };
  age.secrets."hetzner/rclone-b2-password" = {
    file = ../secrets/hetzner/rclone-b2-password.age;
    owner = "root";
    group = "root";
  };

  # ── Base firewall — split-IP firewall (imported above) handles per-IP rules ──
  # Keep only SSH + VXLAN here as fallback; everything else via iptables chains.
  networking.firewall.allowedTCPPorts = [
    22    # SSH
  ];
  networking.firewall.allowedUDPPorts = [
    8472  # flannel VXLAN (k3s)
  ];

  # ── Attic binary cache client (pushes to home-pi over Tailscale) ──
  # Endpoint: home-pi Tailscale IP 100.64.0.2:8280
  # Cache: 2143nix (signing key below)

  age.secrets.attic-admin-token = {
    file = ../secrets/hetzner/attic-token.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Add Attic as a substituter (higher priority than cache.nixos.org for our paths)
  nix.settings.substituters = lib.mkBefore [
    "http://100.64.0.2:8280/2143nix"
  ];
  nix.settings.trusted-public-keys = lib.mkBefore [
    "2143nix:Ysam0ozURtK+1tkP62M6lzbfoi8BVeL6s7ZWJlB6UxE="
  ];
  nix.settings.netrc-file = "/run/attic-netrc";

  # Write netrc for nix to authenticate with Attic
  systemd.services.attic-netrc = {
    description = "Generate Attic netrc for nix";
    after = ["agenix.service"];
    wants = ["agenix.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "attic-netrc" ''
        mkdir -p /run
        printf 'machine 100.64.0.2 password %s\n' \
          "$(cat ${config.age.secrets.attic-admin-token.path})" \
          > /run/attic-netrc
        chmod 0444 /run/attic-netrc
      '';
    };
    wantedBy = ["multi-user.target"];
  };

  # Login to Attic server (oneshot, runs once after network is up)
  systemd.services.attic-login = {
    description = "Attic cache login";
    after = ["network-online.target" "tailscaled.service" "attic-netrc.service"];
    wants = ["network-online.target" "tailscaled.service" "attic-netrc.service"];
    path = [pkgs.attic-client];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "attic-login" ''
        attic login home-pi http://100.64.0.2:8280 "$(cat ${config.age.secrets.attic-admin-token.path})"
      '';
    };
  };

  # Watch store: push newly-built paths to Attic on home-pi
  systemd.services.attic-watch-store = {
    description = "Push built paths to Attic cache on home-pi";
    requires = ["attic-login.service"];
    after = ["attic-login.service" "network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.attic-client];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store 2143nix --ignore-upstream-cache-filter";
      Restart = "on-failure";
      RestartSec = 30;
    };
    wantedBy = ["multi-user.target"];
  };

  environment.systemPackages = with pkgs; [
    k3s
    curl
    htop
    iotop
    tcpdump
    attic-client
  ];
}
