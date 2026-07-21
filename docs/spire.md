# SPIFFE/SPIRE → Linkerd Migration

## Status: SPIRE SDK Removed ✅
**Migration Date**: 2026-07-19  
**Current Architecture**: Linkerd transparent mTLS (no SPIRE SDK in application code)

### What Changed
- **SPIRE SDK removed** from all application code (john2143.com, frigate_genai)
- **Linkerd proxy sidecars** now handle mTLS transparently
- Applications connect via **plain TCP/gRPC**, Linkerd wraps with mTLS
- **No application code changes** needed for mTLS - fully transparent

### Migration Outcomes
✅ **Solved**: Transparent mTLS without SDK boilerplate  
✅ **Solved**: Cross-cluster mTLS (Home→DO via Linkerd multicluster gateway)  
✅ **Solved**: Declarative ACL policies via ServerAuthorization resources  
⚠️ **Partial**: DO→Home multicluster blocked (requires public gateway exposure on port 4143)  
⏳ **Deferred**: Pocket ID federated OIDC (awaits SPIRE JWKS integration with Linkerd)  
⏳ **Deferred**: GitHub Actions mTLS (needs SPIRE admin API or OIDC federation)  

### Federation Model
**Gateway-to-gateway without API access**:
- Friends' clusters don't need kubeconfig or Kubernetes API credentials
- Each cluster exposes Linkerd gateway on port 4143 (LoadBalancer/NodePort/Tailscale)
- Service export via `mirror.linkerd.io/exported: "true"` label
- ACL control via ServerAuthorization policies per federated ServiceAccount
- Trust anchor sharing enables cross-cluster mTLS
- Operational independence: friend cluster outage doesn't affect your control plane

**Example ACL for federated cluster**:
```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: ServerAuthorization
metadata:
  name: temporal-grpc-five-nines
  namespace: default
spec:
  server:
    name: temporal-grpc
  client:
    meshTLS:
      serviceAccounts:
        - name: john2143-com
          namespace: default
          cluster: five-nines  # Federated cluster identity
```

---

## Original SPIRE Vision (Historical Context)

## Current Implementation: Linkerd + Multicluster

### Architecture
```
Home Cluster (k3s)                    DO Cluster (DOKS)
┌─────────────────────┐              ┌─────────────────────┐
│ john2143-worker     │              │ john2143-com        │
│ ┌─────────────────┐ │              │ ┌─────────────────┐ │
│ │ App (plain TCP) │ │              │ │ App (plain TCP) │ │
│ │       ↓         │ │              │ │       ↓         │ │
│ │ linkerd-proxy   │ │◄────mTLS────►│ │ linkerd-proxy   │ │
│ └─────────────────┘ │   gateway    │ └─────────────────┘ │
└─────────────────────┘              └─────────────────────┘
         │                                     │
         ↓                                     ↓
   Temporal (home)                      MongoDB (DO)
```

### How It Works
1. **Application makes plain TCP connection** to service (e.g., `temporal-grpc.john2143.com:7233`)
2. **Linkerd proxy intercepts** the connection at the network layer
3. **Proxy performs mTLS handshake** with remote proxy/gateway
4. **Traffic flows encrypted** end-to-end without application awareness
5. **ServerAuthorization policies** enforce which ServiceAccounts can access which services

### Cross-Cluster Federation
**Working**: Home → DO (MongoDB access via `do-john2143-mongo` service mirror)  
**Blocked**: DO → Home (requires home gateway on port 4143 exposed publicly)

**How multicluster works**:
1. Expose Linkerd gateway on each cluster (port 4143)
2. Create Link resource with remote gateway address + trust anchor
3. Label services for export: `mirror.linkerd.io/exported: "true"`
4. Service mirrors auto-create as `<cluster-name>-<service-name>`
5. Applications use mirrored service names (e.g., `do-john2143-mongo:27017`)

### Declarative ACLs
Create Server + ServerAuthorization resources to define access policies:

```yaml
# Define the service
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata:
  name: temporal-grpc
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: temporal
  port: 7233
  proxyProtocol: gRPC
---
# Allow specific workloads
apiVersion: policy.linkerd.io/v1beta3
kind: ServerAuthorization
metadata:
  name: temporal-grpc-clients
  namespace: default
spec:
  server:
    name: temporal-grpc
  client:
    meshTLS:
      serviceAccounts:
        - name: john2143-worker
          namespace: default
        - name: john2143-com
          namespace: default
```

**Result**: Only john2143-worker and john2143-com can connect to Temporal. All other workloads are denied by default.

### Benefits Over SPIRE SDK Approach
✅ **Zero application code**: No SDK imports, no certificate management code  
✅ **Language agnostic**: Works with any TCP/gRPC application (TypeScript, Python, Go, Rust, etc.)  
✅ **Transparent**: Existing connection code (`temporal-grpc.john2143.com:7233`) works unchanged  
✅ **Declarative ACLs**: Kubernetes-native policy resources instead of SPIRE entries  
✅ **Operational simplicity**: No Workload API sockets, no certificate rotation logic  
✅ **Service mesh benefits**: Automatic retries, timeouts, observability, traffic splitting  

### Remaining Work
- [ ] Expose home Linkerd gateway for DO→Home multicluster (port 4143 forwarding)
- [ ] Integrate Pocket ID federated OIDC for Temporal API key auth (replaces token-supplier)
- [ ] Set up GitHub Actions mTLS via OIDC federation or SPIRE admin API
- [ ] Add five-nines cluster to multicluster mesh
- [ ] Deploy ServerAuthorization policies for all sensitive services

---


## SPIFFE SPIRE
I want a root spire serving 3 clusters:

    internal spire: home cluster
    internal spire: digitalocean cluster
    internal spire: five-nines


My tailnet has services on `*.ts.2143.me`

I want to have a generally unified input to my services. For instance, the temporal service:

It will have an internal vpn route of https://temporal.ts.2143.me.
It will have an external route, through oauth-proxy, to https://temporal.john2143.com/

It should also have two routes we can use for grpc:
internal route (no auth): temporal.ts.2143.me:7233
external route (mtls): temporal-grpc.john2143.com:7233

Ideally, I would like to use our single pocket-id instance for all auth. It
allow users to login with pocket-id, granting them roles. For services, I want to define
"Federated client credentials", which allow authenticating OIDC clients without managing long-lived secrets. They leverage JWT tokens issued by third-party authorities for client assertions, e.g. workload identity tokens. Docs 

https://pocket-id.org/docs/guides/oidc-client-authentication


I have setups like
 Issuer: https://spiffe.john2143.com
 Subject: spiffe://kube.john2143.com/cluster/do-john2143/ns/default/sa/john2143-com
 Audience: https://au.2143.me
 JWKS Url: https://spiffe.john2143.com/keys


But... I was told this was doing nothing right now. And my services aren't using it. Is that true?

I have two services I want to fully debug with:
  1. john2143.com
  2. frigate_genai

These are two apps with their own challenges.

Lets start with what they have in common:

Both want to connect on gRPC to temporal. For example, here is the setup we currently have for john2143.com:

│     Environment:                                                                                                                          │
│       RUN_MODE:                      server                                                                                               │
│       NODE_TLS_REJECT_UNAUTHORIZED:  0                                                                                                    │
│       S3_ENDPOINT_URL:               https://imagehost-files.nyc3.digitaloceanspaces.com                                                  │
│       S3_ACCESS_KEY:                 <set to the key 'S3_ACCESS_KEY' in secret 'minio-credentials'>  Optional: false                      │
│       S3_SECRET_KEY:                 <set to the key 'S3_SECRET_KEY' in secret 'minio-credentials'>  Optional: false                      │
│       MINIO_ENDPOINT_URL:            https://files.john2143.com                                                                           │
│       MINIO_ACCESS_KEY:              <set to the key 'MINIO_ACCESS_KEY' in secret 'minio-credentials'>  Optional: false                   │
│       MINIO_SECRET_KEY:              <set to the key 'MINIO_SECRET_KEY' in secret 'minio-credentials'>  Optional: false                   │
│       SPIFFE_ENDPOINT_SOCKET:        unix:///spiffe-workload-api/spire-agent.sock                                                         │
│       BUCKET:                        imagehost-files                                                                                      │
│       AUTH_CALLBACK_BASE:            https://2143.me                                                                                      │
│       POCKETID_ISSUER:               https://au.2143.me                                                                                   │
│       POCKETID_ADMIN_GROUP:          admin                                                                                                │
│       POCKETID_CLIENT_ID:            <set to the key 'POCKETID_CLIENT_ID' in secret 'oauth-creds'>      Optional: false                   │
│       POCKETID_CLIENT_SECRET:        <set to the key 'POCKETID_CLIENT_SECRET' in secret 'oauth-creds'>  Optional: false                   │
│       DISCORD_CLIENT_ID:             <set to the key 'DISCORD_CLIENT_ID' in secret 'oauth-creds'>       Optional: false                   │
│       DISCORD_CLIENT_SECRET:         <set to the key 'DISCORD_CLIENT_SECRET' in secret 'oauth-creds'>   Optional: false                   │
│       TEMPORAL_ADDRESS:              temporal-grpc.john2143.com:7233                                                                      │
│       TEMPORAL_TLS:                  true                                                                                                 │
│       TEMPORAL_TLS_CA_PATH:          /etc/temporal-certs/ca.crt                                                                           │
│       TEMPORAL_TLS_SERVER_NAME:      temporal-grpc.john2143.com



You can see it has many  temporal GRPC routes defined, and it is trying to connect remotely to temporal-grpc.john2143.com:7233. This is the external route, which is mTLS.
Similarly, all of the frigate_genai services should try to connect to temporal-grpc.john2143.com:7233 as well. This is the external route, which is mTLS.


I'm not sure how either of these are configured right now, or if they are allowed to do this.

I wish that pods automatically received a spiffe identity, and that they could use that identity to authenticate to temporal without extra boilerplate code for SPIFFE/SPIRE.
We should be able to  define ACLs somewhere to say what workloads can connect to what other workloads.

In general, each new service gets 1 or 2 routes: if we're on the home cluster, we get *.john2143.com by creating an HTTPRoute easily. Like something.john2143.com . If this service should be secured, then we must also add oauth proxy in front of it, and ensure we have an au.2143.me group for it.
Now, if we are an external cluster trying to connect to our local cluster, then as long as we have a working DNS entry and valid keys, we should be able to access that app remotely. For example, if we have a service on the digitalocean cluster, it should be able to connect to temporal-grpc.john2143.com:7233 as long as it has a valid spiffe identity and the ACLs allow it. And this shouldn't require any  extra code on the application developer side: If they have a valid ACL, then they should be able to call that  endpoint with their pod. SPIRE is on each pod to create workload identities.


Is this sensible? what do we need to do to get here?


... also ...

We are free to drop SPIRE btw. I just want something safe and reliable that is fully open source and has every feature and is well supported. I will not  be paying. This is our setup.

We have the home cluster which has a LOT of pods, and only some of them require mTLS ingress (temporal, some databases, not much else)
We have the digital ocean cluster which has a LOT of pods, and some of them connect to temporal.
We also have a third cluster, five-nines, with even more pods, and far more separated kube clusters on hetereogeneus clouds.
Right now, we have internal and external routes separated, but in general, machines use mtls and users us oauth.

All of these should be their own independent clusters. I dont want an outage in one to affect the other. But I want to be able to write ACLs to federate the identities.
For instance, I want to be able to say "five-nines john2143-com can reach homelab temporal service" but not "five-nines exit-node can reach homelab database".
I want to have a minimalist setup that is declarative, easy to manage, and doesn't require a lot of overhead. Secuirty is priority #1 overall, as these are PUBLIC services.
I want all of them to be able to identify eachother, while leaving this extensible later. If my friend has their own cluster, I want to be able to grant them mTLS.
And finally, I also want this to work with some other tools like github actions to automate deployments and CI/CD pipelines, while ensuring that the security policies are enforced and that it can use our APIs/caches over mTLS.

