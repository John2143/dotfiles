# Longhorn Disaster Recovery Guide

Date: 2026-06-11
Trigger: arch node disk failure (`DiskFilesystemChanged — diskUUID doesn't match`)
Impact: Lost `unifi-mongodb-data-lh` and `unifi-config-lh` PVCs

## TL;DR

1. Scale down pods, set ArgoCD to manual
2. Restore PVC from backup via **Longhorn UI** (NOT kubectl — NFSv4 mount fails on k3s nodes)
3. Create static PV bound to restored Longhorn volume
4. Create PVC with `volumeName` pointing to static PV
5. Remove `kubernetes.io/pvc-protection` finalizer if PVC gets stuck
6. Scale up pods
7. Re-enable ArgoCD (expect OutOfSync on PVCs — harmless)

## Backup Volumes vs Current PVCs

All backups live at `nfs://192.168.5.175:/` on the NAS. The backupstore path is `/tank/longhorn-backups/backupstore/`.

To find which backup volume corresponds to which PVC:
- Backup volume UUIDs match the original PVC UID
- Current PVC UIDs can be found with `kubectl get pvc -n default -o json`
- Match the first part of the backup volume name (e.g., `pvc-de6e9470`) to PVC UID
- The KubernetesStatus label on backups is often empty — don't rely on it

## Known Volume Mappings

| Backup Volume | PVC Name | Size | Notes |
|---|---|---|---|
| `pvc-de6e9470` | unifi-mongodb-data-lh (old) | 5Gi | Only June 3 backup had real data; later backups were empty |
| `pvc-2c60403d` | unifi-config-lh (old) | 5Gi | UniFi config (system.properties, keystore, firmware) |
| `pvc-374214a1` | home-assistant-config-lh | 10Gi | |
| `pvc-4cbdffb5` | rustfs-data | 644Gi | |
| `pvc-f06012f1` | teamspeak-all-lh | 10Gi | |
| `pvc-0dbbdc7c` | pihole-config-lh | 5.4Gi | |
| `pvc-388f27f8` | pihole-dnsmasq-lh | 1.1Gi | |
| `pvc-91dc8c6f` | grocy-config-lh | 5.4Gi | |
| `pvc-d6926bd9` | headscale-data-lh | 1.1Gi | |
| `pvc-a71a966d` | matter-server-data-lh | 5Gi | |
| `pvc-1bcf3b05` | openrct2-data-lh | ? | |

## Restore Procedure (Detailed)

### 1. Prepare
```bash
# Scale down affected pods
kubectl scale deploy <app> -n default --replicas=0
kubectl scale deploy <app>-mongodb -n default --replicas=0

# Set ArgoCD to manual
kubectl patch app <app> -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

### 2. Restore via Longhorn UI (REQUIRED)

Kubectl-based restores (`fromBackup` on Volume) FAIL because k3s nodes can't mount NFSv4. The Longhorn UI uses the instance-manager's internal NFS client.

1. Open https://192.168.5.175/longhorn
2. Backup → select the backup volume → select backup snapshot → Restore
3. Set name and 2 replicas

### 3. Create Static PV

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <pv-name>
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: driver.longhorn.io
    volumeHandle: <longhorn-volume-name>
    fsType: ext4
```

### 4. Create PVC Bound to PV

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <original-pvc-name>
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  volumeName: <pv-name>
  resources:
    requests:
      storage: 5Gi
```

### 5. Handle PVC Protection Finalizer

If the old PVC gets stuck Terminating:
```bash
kubectl patch pvc <name> -n default \
  -p '{"metadata":{"finalizers":null}}' --type=merge
```

### 6. Scale Up
```bash
kubectl scale deploy <app>-mongodb -n default --replicas=1
kubectl scale deploy <app> -n default --replicas=1
```

### 7. Re-enable ArgoCD
```bash
kubectl patch app <app> -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

Expect PVCs to show OutOfSync — the `volumeName` and `storageClassName` fields are immutable and differ from git spec. This is harmless.

## UniFi Specifics

### PVCs
- `unifi-mongodb-data-lh` — MongoDB data (WiredTiger files at root)
- `unifi-config-lh` — UniFi config (`data/system.properties`, `data/keystore`, etc.)

### Admin Account
- Collection: `unifi.admin`
- Password hash: SHA-512 crypt (`$6$...`)
- Can be reset via mongosh:
```javascript
db = db.getSiblingDB('unifi');
db.admin.updateOne(
  {name: 'unifi_john'},
  {$set: {x_shadow: '<sha512-hash>'}}
);
```
- Generate hash: `mkpasswd -m sha-512 'password'`

### Setup Wizard
If UniFi shows setup wizard after restore, check `system.properties`:
- `is_default=true` → setup wizard
- `is_default=false` → login page
- Also check `uuid=` line matches controller identity

### NFS Mount Issue
Longhorn instance-managers on k3s nodes can't mount NFSv4. Relevant because backups live on NFS.
- NFSv4 mount fails with "Protocol not supported" or "access denied"
- NFSv3 requires `rpc.statd` (not installed on k3s nodes)
- Longhorn **UI** restores work because the UI triggers restore through the instance-manager's internal client
- Kubectl `fromBackup` restores try to mount on the node directly → fail

## Root Cause of This Outage

arch node's Longhorn disk at `/mnt/longhorn` failed with:
```
DiskFilesystemChanged — diskUUID doesn't match the one on the disk
```
This caused `allowScheduling: false` and `storageAvailable: 0`. Both UniFi PVCs were recreated by ArgoCD as empty volumes on June 9. The June 9 backup was taken AFTER data loss (empty database). The last good backup was June 3.

## Lessons

1. **Always verify backup contents** before assuming a backup is good — the June 9 backup existed but contained an empty database
2. **Test restore to a temp volume first** before swapping the live PVC
3. **Check multiple backup snapshots** — the most recent isn't always valid
4. **Longhorn UI is the only reliable restore path** on this cluster
5. **Keep this file updated** when PVC mappings change
## Pocket-ID Specifics

### PVC
- `pocket-id-data-pocket-id-0` in namespace `pocket-id`
- Old backup volume: `pvc-d24df7d5-0cca-4564-a3c5-a394b02d6936` (5.4Gi)
- StatefulSet: `pocket-id` in namespace `pocket-id`

## Manual Backup Trigger

The `nightly-backup` recurring job runs at 3am for volumes labeled `recurring-job-group.longhorn.io/default: enabled`. Restored volumes should already have this label from the Longhorn UI restore.

To trigger an immediate backup:
```bash
VOL=unifi-mongo-check
SNAP="manual-$(date +%s)-$VOL"

kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: $SNAP
  namespace: longhorn-system
spec:
  volume: $VOL
---
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: $SNAP
  namespace: longhorn-system
spec:
  snapshotName: $SNAP
EOF
```

## Restored Volumes (Post-Recovery)

| Longhorn Volume | PVC | Namespace | Backup Volume (source) |
|---|---|---|---|
| `unifi-mongo-check` | unifi-mongodb-data-lh | default | `pvc-de6e9470` (June 3 backup) |
| `unifi-config-real` | unifi-config-lh | default | `pvc-2c60403d` (June 3 backup) |
| `pocket-id-restored` | pocket-id-data-pocket-id-0 | pocket-id | `pvc-d24df7d5` |
