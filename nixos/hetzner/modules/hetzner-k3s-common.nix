# Hetzner k3s Common — shared k3s + Flannel + ArgoCD + firewall config
#
# All 3 server nodes are identical — drop-in replaceable.
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
      # Install istio CRDs (needed before ArgoCD syncs wave 3)
      kubectl apply -f https://raw.githubusercontent.com/istio/istio/1.27.0/manifests/charts/base/files/crd-all.gen.yaml 2>&1 || true
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
      # Install Traefik — ingress controller with hostNetwork + ACME
      # hostNetwork is required because hostPort doesn't work through Flannel CNI.
      # Direct kubectl deploy (not Helm) — HelmChart controller is unreliable.
      kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply -f - <<'TRAEFIKEOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traefik-ingress-controller
rules:
- apiGroups: [""]
  resources: [services, endpoints, secrets, nodes]
  verbs: [get, list, watch]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: [ingresses, ingresses/status, ingressclasses]
  verbs: [get, list, watch]
- apiGroups: ["discovery.k8s.io"]
  resources: [endpointslices]
  verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traefik-ingress-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
- kind: ServiceAccount
  name: default
  namespace: traefik
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
spec:
  controller: traefik.io/ingress-controller
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: traefik
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      hostNetwork: true
      containers:
      - name: traefik
        image: docker.io/traefik:v3.3.1
        args:
        - --entrypoints.web.address=:80
        - --entrypoints.websecure.address=:443
        - --providers.kubernetesingress
        - --log.level=INFO
        ports:
        - containerPort: 80
          name: web
        - containerPort: 443
          name: websecure
        volumeMounts:
        - name: data
          mountPath: /data
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: data
        emptyDir: {}
      - name: tmp
        emptyDir: {}
TRAEFIKEOF
      kubectl -n traefik wait --for=condition=available deployment/traefik --timeout=120s 2>&1 || true
      # Install Longhorn (Helm) — distributed block storage
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo update 2>/dev/null || true
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace \
        --set persistence.defaultClass=true \
        --set defaultSettings.createDefaultDiskLabeledNodes=true \
        --set defaultSettings.defaultDataPath=/var/lib/longhorn \
        --wait --timeout 120s 2>&1 || true
      kubectl apply --server-side --force-conflicts -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.1.yaml
      kubectl wait --for=condition=available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s || true
      # Install cert-manager (Helm) — TLS certificate automation via HTTP01
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo update 2>/dev/null || true
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
        --set crds.enabled=false \
        --wait --timeout 120s 2>&1 || true
      # Patch only the controller with hostNetwork (cainjector + webhook use default pod networking)
      kubectl patch deployment -n cert-manager cert-manager -p '{"spec":{"template":{"spec":{"hostNetwork":true}}}}' 2>/dev/null || true
      # Install cert-manager CRDs separately (Helm set crds.enabled=false)
      # cert-manager 1.16 uses the old `class` field, not `ingressClassName`
      kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml 2>&1 || true
    '';
  };



  # ── agenix → Kubernetes Secrets injection ──
  # Decrypts agenix secrets and creates Kubernetes Secrets before ArgoCD syncs.
  # Runs after k3s is ready, before ArgoCD applies the root app.
  # Secrets created: crowdsec-bouncer-key, mongo-creds,
  #   b2-credentials, seaweedfs-master-key, rclone-config, healthchecks-url,
  #   temporal-postgres-password
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
      for ns in crowdsec seaweedfs backup monitoring; do
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
      done


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


      # Temporal PostgreSQL password (generated, used by CNPG Cluster CR)
      kubectl create secret generic temporal-postgres-password -n default \
        --from-literal=password="$(head -c 32 /dev/urandom | base64 | tr -d '\n')" \
        --dry-run=client -o yaml | kubectl apply -f -

    '';
  };



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
