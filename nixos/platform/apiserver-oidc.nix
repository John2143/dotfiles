# Pocket ID (au.2143.me) as an identity source for the platform API, next to
# the k3s client certificates. Friends sign in with kubelogin (public client
# cloud-kube, PKCE) and reach the API over the cloud tailnet; RBAC in
# cloud-argo binds the prefixed groups: oidc:platform-admins -> cluster-admin,
# oidc:tenant-<name> -> edit in that tenant's namespaces.
#
# Structured authentication config (GA since Kubernetes 1.34) instead of the
# --oidc-* flags; the API server reloads this file when it changes.
# Username is preferred_username, not email: an email username is rejected
# unless email_verified is true, which Pocket ID only sends for verified
# addresses.
{pkgs, ...}: let
  authn = (pkgs.formats.yaml {}).generate "authentication-config.yaml" {
    apiVersion = "apiserver.config.k8s.io/v1";
    kind = "AuthenticationConfiguration";
    jwt = [
      {
        issuer = {
          url = "https://au.2143.me";
          # Pocket ID client cloud-kube (public; the ID is not a secret).
          audiences = ["098b557c-c4f5-4c7d-89af-cf97ef653114"];
        };
        claimMappings = {
          username = {
            claim = "preferred_username";
            prefix = "oidc:";
          };
          groups = {
            claim = "groups";
            prefix = "oidc:";
          };
        };
      }
    ];
  };
in {
  environment.etc."rancher/k3s/authentication-config.yaml".source = authn;
  services.k3s.extraFlags = ["--kube-apiserver-arg=authentication-config=/etc/rancher/k3s/authentication-config.yaml"];
}
