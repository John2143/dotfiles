# Linkerd Federation Pattern - Manual Service Mirrors

## Overview

Federated multicluster Linkerd WITHOUT requiring API access between clusters.
Only gateway port (4143) and trust anchor sharing required.

## Adding a New Federated Cluster

1. **Exchange trust anchors** (one-time per cluster pair)
2. **Expose gateway publicly** on port 4143
3. **Create Link resource** on local cluster pointing to remote gateway
4. **Manually create mirror services** for each remote service to import

## Manual Mirror Service Template

For each remote service you want to access locally:

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: <service-name>-<cluster-name>
  namespace: <namespace>
  labels:
    mirror.linkerd.io/cluster-name: <cluster-name>
    mirror.linkerd.io/mirrored-service: "true"
  annotations:
    mirror.linkerd.io/remote-svc-fq-name: <service-name>.<namespace>.svc.cluster.local
    mirror.linkerd.io/remote-gateway-identity: linkerd-gateway.linkerd-multicluster.serviceaccount.identity.linkerd.cluster.local
spec:
  type: ClusterIP
  ports:
  - name: <port-name>
    port: <service-port>
    protocol: TCP
    targetPort: <service-port>
---
apiVersion: v1
kind: Endpoints
metadata:
  name: <service-name>-<cluster-name>
  namespace: <namespace>
  labels:
    mirror.linkerd.io/cluster-name: <cluster-name>
    mirror.linkerd.io/mirrored-service: "true"
  annotations:
    mirror.linkerd.io/remote-svc-fq-name: <service-name>.<namespace>.svc.cluster.local
    mirror.linkerd.io/remote-gateway-identity: linkerd-gateway.linkerd-multicluster.serviceaccount.identity.linkerd.cluster.local
subsets:
- addresses:
  - ip: <gateway-ip>  # Must be IP address (resolve hostname first)
  ports:
  - name: <port-name>
    port: 4143  # Always gateway port, not service port
    protocol: TCP
```

Replace:
- `<service-name>` — original service name in remote cluster
- `<cluster-name>` — remote cluster identifier (from Link resource)
- `<namespace>` — namespace where service lives
- `<port-name>` — port name from original service
- `<service-port>` — port number from original service
- `<gateway-ip>` — IP address of remote gateway (resolve hostname to IP: `host gateway.example.com`)

**Important:** Kubernetes Endpoints API requires an IP address in the `ip` field, NOT a hostname. Resolve the gateway hostname to IP before creating the Endpoints object.

## Example: Accessing friend-cluster's postgres

Friend exposes gateway at `gateway.friend.example.com:4143`.
Friend's postgres service is `postgres.default.svc.cluster.local:5432`.

On your cluster:
1. Resolve `gateway.friend.example.com` → `203.0.113.42`
2. Create mirror service `postgres-friend` with Endpoints pointing to `203.0.113.42:4143`
3. Applications connect to `postgres-friend.default.svc.cluster.local:5432`
4. Linkerd routes through gateway with mTLS

## Working Example

See `~/repos/argo/workloads/linkerd-mirrors/temporal-homelab.yaml` for a complete working example mirroring Temporal from homelab cluster.

## Rollback

```bash
kubectl delete svc <service-name>-<cluster-name> -n <namespace>
kubectl delete endpoints <service-name>-<cluster-name> -n <namespace>
```

## Verification

After creating manual mirrors, verify connectivity:

```bash
# DNS resolution
kubectl run test-dns --rm -i --restart=Never --image=busybox -- nslookup <service-name>-<cluster-name>.<namespace>.svc.cluster.local

# TCP connectivity
kubectl run test-tcp --rm -i --restart=Never --image=busybox -- sh -c 'timeout 5 nc -zv <service-name>-<cluster-name>.<namespace>.svc.cluster.local <port>'

# Service and Endpoints exist
kubectl get svc,endpoints <service-name>-<cluster-name> -n <namespace> -o wide
```

Expected: DNS resolves, TCP connection succeeds, Endpoints points to gateway IP:4143.
