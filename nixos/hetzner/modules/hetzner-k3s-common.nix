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
      "--node-label=node.longhorn.io/create-default-disk=true"
    ];
  };
  # k3s uses Type=notify but sometimes the startup takes too long and
  # systemd kills it with "Failed with result 'protocol'". Override to simple.
  systemd.services.k3s.serviceConfig.Type = lib.mkForce "simple";


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
      # Install cert-manager CRDs (needed before ArgoCD syncs wave 0)
      kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.crds.yaml 2>&1 || true
      # Install istio CRDs (needed before ArgoCD syncs wave 3)
      kubectl apply -f https://raw.githubusercontent.com/istio/istio/1.27.0/manifests/charts/base/crds/crd-all.gen.yaml 2>&1 || true
      # Install k8gb CRDs (needed before ArgoCD syncs wave 2)
      kubectl apply -f https://raw.githubusercontent.com/k8gb-io/k8gb/v0.14.0/chart/k8gb/templates/crds.yaml 2>&1 || true
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
      # Install cert-manager (Helm) — TLS certificate automation
      helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
      helm repo update 2>/dev/null || true
      helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
        --set crds.enabled=false \
        --wait --timeout 120s 2>&1 || true
    '';
  };



  # ── agenix → Kubernetes Secrets injection ──
  # Decrypts agenix secrets and creates Kubernetes Secrets before ArgoCD syncs.
  # Runs after k3s is ready, before ArgoCD applies the root app.
  # Secrets created: rfc2136-credentials, crowdsec-bouncer-key, mongo-creds,
  #   b2-credentials, seaweedfs-master-key, rclone-config, healthchecks-url,
  #   pdns-postgres-password, temporal-postgres-password
  # NOTE: mongo-encryption-key removed — mongo:7 Community Edition doesn't support
  #   encryption-at-rest (--enableEncryption is Enterprise-only) 
  # NOTE: These secrets MUST NOT exist as placeholders in the GitOps repo.
  #   ArgoCD selfHeal WILL overwrite injected values even with IgnoreExtraneous.
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
      kubectl create secret generic healthchecks-url -n monitoring \
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

  # ── CNPG password sync ──
  # CNPG initdb creates roles with random passwords. The agenix secrets
  # (pdns-postgres-password) are injected as k8s Secrets by k8s-secrets-bootstrap,
  # but never synced into PostgreSQL. This oneshot fixes the mismatch.
  systemd.services.cnpg-password-fix = {
    description = "Sync CNPG PostgreSQL role passwords with agenix secrets";
    after = ["k8s-secrets-bootstrap.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

      # Wait for CNPG pod to exist and be Running
      CNPG_POD=""
      for i in $(seq 1 60); do
        CNPG_POD=$(kubectl get pod -n default -l cnpg.io/cluster=temporal-postgres \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$CNPG_POD" ]; then
          PHASE=$(kubectl get pod "$CNPG_POD" -n default \
            -o jsonpath='{.status.phase}' 2>/dev/null)
          if [ "$PHASE" = "Running" ]; then
            echo "CNPG pod $CNPG_POD is Running"
            break
          fi
        fi
        echo "Waiting for CNPG pod... ($i/60)"
        sleep 5
      done

      if [ -n "$CNPG_POD" ]; then
        PDNS_PASS=$(tr -d '\n' < "${config.age.secrets."hetzner/postgres-pdns-password".path}")
        kubectl exec -i "$CNPG_POD" -n default -- psql -U postgres \
          -c "ALTER ROLE pdns PASSWORD '$PDNS_PASS';" 2>&1
        echo "Synced pdns PostgreSQL role password with agenix secret"
      else
        echo "WARNING: CNPG pod not found after 300s, skipping password sync"
      fi
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
  # Endpoint: home-pi via headscale.9s.pics:8280 (port-forwarded, works pre-Tailscale)
  # Cache: 2143nix (signing key below)

  age.secrets.attic-admin-token = {
    file = ../secrets/hetzner/attic-token.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Add Attic as a substituter (higher priority than cache.nixos.org for our paths)
  nix.settings.substituters = lib.mkBefore [
    "http://headscale.9s.pics:8280/2143nix"
  ];
  nix.settings.trusted-public-keys = lib.mkBefore [
    "2143nix:LvE5APLbagyNODEJJ4BHKV4le1vcC6JgNklqdyMPUl8="
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
        printf 'machine headscale.9s.pics password %s\n' \
          "$(for f in /run/agenix.d/*/attic-admin-token /run/agenix/attic-admin-token; do [ -f \"\$f\" ] && cat \"\$f\" && break; done)" \
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
        attic login home-pi --set-default http://headscale.9s.pics:8280 "$(for f in /run/agenix.d/*/attic-admin-token /run/agenix/attic-admin-token; do [ -f \"\$f\" ] && cat \"\$f\" && break; done)"
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
