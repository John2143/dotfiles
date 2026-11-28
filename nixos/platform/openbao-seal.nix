# OpenBao static unseal key for the platform cluster (cloud-argo
# platform/openbao). Decrypted on every node to a real file, not the usual
# /run/agenix symlink: the OpenBao pod mounts /run/openbao-seal as a hostPath
# directory, and a symlink into /run/agenix.d/<generation> would point at
# nothing inside the container. Group 64100 is fixed because the pod names it
# numerically (supplementalGroups); root owns the file and the pod only reads.
#
# This keeps the key out of Kubernetes entirely: no Secret, nothing in etcd or
# in the etcd snapshots in B2. Rotation adds a v2 file next to it and uses the
# seal's previous_key; never re-encrypt v1 in place.
{...}: {
  users.groups.openbao-seal.gid = 64100;

  age.secrets.platform-openbao-unseal = {
    file = ../../secrets/platform-openbao-unseal.age;
    path = "/run/openbao-seal/unseal-v1";
    symlink = false;
    mode = "0440";
    owner = "root";
    group = "openbao-seal";
  };
}
