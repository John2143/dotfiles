# Hetzner k3s Common — shared k3s + Cilium + ArgoCD + firewall config
#
# Imported by hetzner-k3s-server.nix (adds PowerDNS + Galera)
# and by hillsboro-server.nix (no DNS/DB needed).
#
# Does NOT import PowerDNS or Galera modules.
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
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable=traefik"
      "--disable=servicelb"
      "--cluster-cidr=10.42.0.0/16"
      "--service-cidr=10.43.0.0/16"
      "--node-external-ip=${lib.head config.networking.interfaces.eth0.ipv4.addresses}.address"
    ];
  };

  # ── Cilium kernel requirements ──
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
  boot.kernelModules = ["xt_socket"];

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
    path = [pkgs.k3s pkgs.curl];
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
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || true
      # Apply ArgoCD ConfigMap (health-check fix for sync-wave ordering + resource tracking)
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/main/argocd/argocd-cm.yaml
      kubectl rollout restart deployment/argocd-server -n argocd || true
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s || true
      # Apply root Application — wires ArgoCD to the GitOps repo
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/2143-59s/main/argocd/root-app.yaml
    '';
  };

  # ── Cilium CNI bootstrap ──
  systemd.services.cilium-bootstrap = {
    description = "Install Cilium CNI into k3s cluster";
    after = ["k3s.service" "argocd-bootstrap.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s pkgs.cilium-cli];
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
      cilium install
    '';
  };

  # ── agenix → Kubernetes Secrets injection ──
  # Decrypts agenix secrets and creates Kubernetes Secrets before ArgoCD syncs.
  # Runs after k3s is ready, before ArgoCD applies the root app.
  # Secrets: rfc2136-credentials, crowdsec-bouncer-key, mongo-creds,
  #   mongo-encryption-key, b2-credentials, seaweedfs-master-key,
  #   rclone-config, healthchecks-url, temporal-postgres-password
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

      # Temporal postgres password
      kubectl create secret generic temporal-postgres-password -n default \
        --from-literal=password="$(head -c 24 /dev/urandom | base64)" \
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

  # ── Split-IP firewall (runtime — reads actual IPs) ──
  systemd.services.split-ip-firewall = {
    description = "Apply split-IP DDoS firewall rules";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      PROTECTED_IP=$(ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+' | head -1)
      RAW_IP=$(ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+' | tail -1)
      [ -z "$RAW_IP" ] && RAW_IP="$PROTECTED_IP"

      # Protected IP: rate-limited HTTP/S only
      iptables -A INPUT -d "$PROTECTED_IP" -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --set
      iptables -A INPUT -d "$PROTECTED_IP" -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --update --seconds 1 --hitcount 50 -j DROP
      iptables -A INPUT -d "$PROTECTED_IP" -p tcp -m multiport --dports 80,443 -j ACCEPT
      iptables -A INPUT -d "$PROTECTED_IP" -j DROP

      # Raw IP: game/TS/DERP ports
      iptables -A INPUT -d "$RAW_IP" -p udp --dport 3478 -j ACCEPT
      iptables -A INPUT -d "$RAW_IP" -p udp --dport 9987 -j ACCEPT
      iptables -A INPUT -d "$RAW_IP" -p tcp -m multiport --dports 80,443,30033 -j ACCEPT
      iptables -A INPUT -d "$RAW_IP" -j DROP
    '';
  };

  networking.firewall.allowedTCPPorts = [6443 80 443 53 3306 4444 4567 4568];
  networking.firewall.allowedUDPPorts = [53 8472];

  environment.systemPackages = with pkgs; [
    k3s
    cilium-cli
    htop
    iotop
    tcpdump
  ];
}
