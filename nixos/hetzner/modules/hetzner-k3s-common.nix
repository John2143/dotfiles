# Hetzner k3s Common — shared k3s + Cilium + ArgoCD + firewall config
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
    path = [pkgs.k3s pkgs.curl pkgs.git];
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
      # Apply ArgoCD ConfigMap (health-check fix for sync-wave ordering + resource tracking)
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/master/argocd/argocd-cm.yaml
      kubectl rollout restart deployment/argocd-server -n argocd || true
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s || true
      # Apply root Application — wires ArgoCD to the GitOps repo
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/master/argocd/root-app.yaml
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

      # RFC2136 TSIG key for ExternalDNS
      kubectl create secret generic rfc2136-credentials -n external-dns \
        --from-literal=rfc2136TsigSecret="$(cat ${config.age.secrets."hetzner/powerdns-tsig-key".path})" \
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

  # ── Split-IP firewall — DISABLED for initial deployment ──
  # Must be re-enabled after agenix identity is working and floating IPs verified.
  # systemd.services.split-ip-firewall = {
  #   ...
  # };

  networking.firewall.allowedTCPPorts = [22 6443 80 443 53 30432 4567 4568];
  networking.firewall.allowedUDPPorts = [53 8472];

  environment.systemPackages = with pkgs; [
    k3s
    curl
    htop
    iotop
    tcpdump
  ];
}
