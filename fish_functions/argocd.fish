# DESCRIPTION: ArgoCD CLI with auto-authentication via age-encrypted admin password
set -l creds_file /run/agenix/argo-admin-password
if not test -f $creds_file
  echo "ArgoCD admin password not found at $creds_file" >&2
  return 1
end
set -l password (cat $creds_file)
set -lx ARGOCD_SERVER argocd.ts.2143.me
set -lx ARGOCD_AUTH_TOKEN (
  curl -sk https://argocd.ts.2143.me/api/v1/session \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"'$password'"}' | jq -r '.token // empty'
)
if test -z "$ARGOCD_AUTH_TOKEN"
  echo "Failed to obtain ArgoCD auth token" >&2
  return 1
end
command argocd --grpc-web $argv
