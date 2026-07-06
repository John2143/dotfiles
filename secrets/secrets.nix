let
  # Per-machine age keys (~/.ssh/age on each host).
  # Generate on a new computer with: ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p
  # Then add the public key here and re-encrypt any secrets that host should read.
  #
  # Re-encrypt all secrets (run from the office host, the admin):
  #   cd ~/dotfiles/secrets && agenix -r -i ~/.ssh/age
  #
  # NOTE: The k3s token committed before this was introduced is in git history.
  # Rotate the k3s cluster token to fully remove exposure.
  office = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office";
  arch = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbTSIq65Gz8pgHX5uLas3Z/paU9SC5KvG1G2lNMfPH7 john@arch";
  closet = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN3VC6q1KhVCI3BRzbTi9Di/pS7I1ASEYoNBwBzU4jgT john@closet";
  pite = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAh9fgjUMvSfYUYteUHeI/JkjxUJLwVAnoLyluU1Uknd john@pite";
  vpin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4YCIowmPxLCTuH2fVxCtK/sKj7Sefr1s+itj0dtVED john@vpin";
  secu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4vMixKG/e9b3ttJy9Xb5ymavp7Gny6dxKrViQl8AUl john@secu";
  #aman = "TODO: cat ~/.ssh/age.pub on aman and paste here";
  #term = "TODO: cat ~/.ssh/age.pub on term and paste here";
  nas = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzgxUuaZUG9Dr5ZTZImKqt3SUSPVD/FLO2wKQfwz98A john@nas";
  # NOTE: mac is a work computer. Only grant it keys that are work-appropriate
  # (LLM API keys, admin tools). Do NOT grant: hass-credentials, ntfy-topic-url,
  # restic passwords, smb credentials, gocryptfs, NAS, or personal secrets.
  mac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOnQAO6xyPOM67ut324LHAm07OQ67bKJ0R9c0aTWA1o jschmidt@DCIL-L562P1Q5NQ-M";
  # generate with `ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p` on each host, then paste here

  # Collect all keys that should be able to re-encrypt / manage secrets.
  allKeys = [office arch mac];
in {
  # Readable only by the office machine (k3s agent token).
  "k3s-local-token.age".publicKeys = [office arch pite nas closet];
  # ArgoCD admin password — initial admin secret from the K3s cluster.
  # Retrieve with: ssh closet kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  "argo-admin-password.age".publicKeys = [office arch closet];
  # Samba credentials for mounting NAS shares (username/password/domain).
  "smb-credentials.age".publicKeys = [arch office closet secu];
  # Per-machine restic repository passwords (each machine can only decrypt its own).
  # Generate: agenix -e restic-password-<host>.age -i ~/.ssh/age
  "restic-password-arch.age".publicKeys = [arch office];
  "restic-password-office.age".publicKeys = [office arch];
  "restic-password-closet.age".publicKeys = [closet office arch];
  "restic-password-secu.age".publicKeys = [secu office arch];
  # Private SSH key for the backup user on the NAS (all backup clients need this).
  # Generate once: ssh-keygen -t ed25519 -f /tmp/backup-key -N "" -C "backup@nas"
  # Then: agenix -e backup-ssh-key.age -i ~/.ssh/age  (paste the private key)
  # Add the public key to nas-configuration.nix backup user's authorizedKeys.
  "backup-ssh-key.age".publicKeys = [office arch closet secu];
  # gocryptfs passphrase for encrypted vault on NAS scratch share.
  # Only workstations that mount the vault need this — the NAS never sees the key.
  "gocryptfs-passphrase.age".publicKeys = [arch office closet];
  # RustFS (minio) credentials for bigjuush/juush.
  # Format: RUSTFS_USER=...\nRUSTFS_PASSWORD=...\nJUUSH_KEY=...
  "rustfs-credentials.age".publicKeys = [office arch nas closet];
  # LEGACY combined LLM keys file. Kept during transition; new code uses the
  # split files below (llm-runtime-keys, llm-admin-keys). Remove once all hosts
  # have rebuilt against the split files.
  "llm-api-keys.age".publicKeys = [office arch];

  # Runtime LLM keys — handed to wrapped third-party binaries (omp, claude).
  # Format:
  #   ANTHROPIC_API_KEY=sk-ant-...
  #   OPENAI_API_KEY=sk-...
  #   DEEPSEEK_API_KEY=sk-...      (https://platform.deepseek.com/api_keys)
  #   OPENROUTER_API_KEY=sk-or-v1-... (https://openrouter.ai/settings/keys)
  #   GEMINI_API_KEY=...            (https://aistudio.google.com/apikey)
  # pite is included so the canary host can decrypt a same-named bait file
  # (overridden via mkForce in nixos/pite-canary.nix to point at the bait .age).
  "llm-runtime-keys.age".publicKeys = [office arch pite mac];

  # Admin LLM keys — only consumed by `llm-unsafe-load-admin-keys` (interactive shell helper),
  # never by a wrapped third-party process. Kept off pite/canary entirely.
  # Format:
  #   ANTHROPIC_ADMIN_KEY=sk-ant-admin-...  (console.anthropic.com/settings/admin-keys)
  #   OPENAI_ADMIN_KEY=sk-admin-...
  #   OPENROUTER_ADMIN_KEY=sk-or-mgmt-...  (https://openrouter.ai/settings/management-keys)
  "llm-admin-keys.age".publicKeys = [office arch mac];

  # Bait runtime keys for the pite canary. Same env-var names as the real
  # runtime file but with canarytokens.org-issued AWS-shaped tokens that ping
  # a webhook on use. See nixos/pite-canary.nix.
  "llm-runtime-keys-bait.age".publicKeys = [pite];

  "hass-credentials.age".publicKeys = [office arch];
  "canary-tokens.age".publicKeys = [office arch pite];

  # Vast.ai credentials — combined API key + SSH private key. Both are
  # protected by the same crypto and consumed by the same set of helpers,
  # so splitting them adds no security; combining them means one file to
  # edit on key rotation. Per-rental host/port info is discovered live
  # via the Vast.ai API; this file only changes when you rotate the
  # account API key or the SSH keypair.
  # Format (env-var, parsed line-by-line by `envsource`):
  #   VAST_API_KEY=<account API key from https://cloud.vast.ai/account/>
  #   VAST_SSH_PRIVATE_KEY_B64=<base64 -w0 of an ed25519 private key>
  #   VAST_HF_TOKEN=<HuggingFace token>   # optional — much faster model
  #                                       # downloads + access to gated models.
  #                                       # Get one: https://huggingface.co/settings/tokens
  # Generate the SSH keypair once:
  #   ssh-keygen -t ed25519 -f /tmp/vast-key -N ""
  #   echo "VAST_SSH_PRIVATE_KEY_B64=$(base64 -w0 /tmp/vast-key)"
  # Then paste /tmp/vast-key.pub into https://cloud.vast.ai/account/keys
  # so every future rental auto-authorizes this key. Full workflow in
  # ../Vast.md.
  "vast-credentials.age".publicKeys = [office arch];

  # Attic JWT RS256 signing secret. Only the NAS needs it at runtime;
  # office+arch are included so admin machines can re-encrypt / re-deploy.
  # Generate: nix-shell -p openssl --run 'openssl genrsa -traditional 4096 | base64 -w0'
  # Then:    echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<output>" | agenix -e attic-jwt-secret.age -i ~/.ssh/age
  "attic-jwt-secret.age".publicKeys = [office arch nas];

  # Attic admin token — lets each machine authenticate to atticd for
  # push/pull. Generated once on the NAS with atticd-atticadm make-token.
  # Encrypt to all NixOS hosts that import shared-cli-configuration.nix.
  "attic-admin-token.age".publicKeys = [office arch closet secu nas pite vpin ]; # aman term];
  # ntfy.sh topic URL for OMP agent notifications. Topic name is not a
  # cryptographic secret (public server, anyone with the name can publish),
  # but keeping it out of the Nix store avoids accidental exposure.
  "ntfy-topic-url.age".publicKeys = [office arch pite];
  # MikroTik SSH key — router (192.168.1.1) + two switches.
  # Upstairs: 192.168.5.3, Downstairs: 192.168.5.2. All use admin@.
  # Decrypted by the mikrotik-connect fish helper (key-based, no sshpass).
  # Format:
  #   MIKROTIK_SSH_PRIVATE_KEY_B64=<base64 -w0 of an ed25519 private key>
  # Generate:
  #   ssh-keygen -t ed25519 -f /tmp/mikrotik-key -N ""
  #   # Import /tmp/mikrotik-key.pub on each MikroTik:
  #   #   /user ssh-keys import public-key-file=mikrotik-key.pub user=admin
  #   echo "MIKROTIK_SSH_PRIVATE_KEY_B64=$(base64 -w0 /tmp/mikrotik-key)" \
  #     | agenix -e secrets/mikrotik-credentials.age -i ~/.ssh/age
  #   rm /tmp/mikrotik-key /tmp/mikrotik-key.pub
  "mikrotik-credentials.age".publicKeys = [office arch];


  # Remote build cluster SSH key — shared across all builders (x86_64 + aarch64).
  # Each client uses this key to SSH into builders as nixbuild.
  # Builders have the public key in nixbuild's authorized_keys.
  # Generate:
  #   ssh-keygen -t ed25519 -f /tmp/build-cluster-key -N "" -C "build-cluster"
  #   cat /tmp/build-cluster-key.pub  → paste into remote-builders.nix
  #   agenix -e build-cluster-key.age -i ~/.ssh/age < /tmp/build-cluster-key
  "build-cluster-key.age".publicKeys = [office arch closet secu nas pite vpin];

  "unifi-credentials.age".publicKeys = [office arch];
  # Reolink camera RTSP credentials — used by secu for 24/7 monitoring grid.
  # All cameras share the same admin password (set in Reolink app).
  # Format:
  #   CAMERA_USER=admin
  #   CAMERA_PASSWORD=<reolink-camera-password>
  # Create:
  #   echo -e "CAMERA_USER=admin\nCAMERA_PASSWORD=yourpassword" | \
  #     agenix -e camera-credentials.age -i ~/.ssh/age
  "camera-credentials.age".publicKeys = [secu office arch];
  # Home Assistant webhook URLs — triggered by apcupsd on power-loss/return.
  # HA webhooks are unauthenticated (the URL itself is the secret).
  # Create 4 webhooks in HA (Settings → Automations → Webhooks), then:
  #   echo -e "CLOSET_ONBATTERY_URL=http://HA_IP:8123/api/webhook/<id>\nCLOSET_OFFBATTERY_URL=..." | \
  #     agenix -e hass-webhooks.age -i ~/.ssh/age
  #
  # Format (4 lines):
  #   CLOSET_ONBATTERY_URL=http://192.168.5.XX:8123/api/webhook/ups_closet_lost_power
  #   CLOSET_OFFBATTERY_URL=http://192.168.5.XX:8123/api/webhook/ups_closet_power_returned
  #   NAS_ONBATTERY_URL=http://192.168.5.XX:8123/api/webhook/ups_nas_lost_power
  #   NAS_OFFBATTERY_URL=http://192.168.5.XX:8123/api/webhook/ups_nas_power_returned
  "hass-webhooks.age".publicKeys = [closet nas office arch];
  # NUT UPS monitor user password — decryptable by every machine with power.ups enabled.
  # The monitor user authenticates upsmon to upsd (localhost in standalone mode).
  # Create: echo -n "nut-monitor-2143nas" | agenix -e nut-ups-password.age -i ~/.ssh/age
  # Then add the .age file to git and list the decrypting hosts below.
  "nut-ups-password.age".publicKeys = [closet nas office arch];
  "reolink-nvr.age".publicKeys = [office arch closet];

  "frigate-plus.age".publicKeys = [arch];
}
