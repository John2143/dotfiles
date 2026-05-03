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
  security = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILO6ntnqr4ERZLUdL2MOMeC++HPIsigce4d42h8UogA2 john@security";
  secu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4vMixKG/e9b3ttJy9Xb5ymavp7Gny6dxKrViQl8AUl john@secu";
  nas = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzgxUuaZUG9Dr5ZTZImKqt3SUSPVD/FLO2wKQfwz98A john@nas";
  # generate with `ssh-keygen -f ~/.ssh/age; cat ~/.ssh/age.pub -p` on each host, then paste here

  # Collect all keys that should be able to re-encrypt / manage secrets.
  allKeys = [office arch];
in {
  # Readable only by the office machine (k3s agent token).
  "k3s-local-token.age".publicKeys = [office arch pite];
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
  # pite is included so the canary host can decrypt a same-named bait file
  # (overridden via mkForce in nixos/pite-canary.nix to point at the bait .age).
  "llm-runtime-keys.age".publicKeys = [office arch pite];

  # Admin LLM keys — only consumed by `llm-load-keys` (interactive shell helper),
  # never by a wrapped third-party process. Kept off pite/canary entirely.
  # Format:
  #   ANTHROPIC_ADMIN_KEY=sk-ant-admin-...  (console.anthropic.com/settings/admin-keys)
  #   OPENAI_ADMIN_KEY=sk-admin-...
  "llm-admin-keys.age".publicKeys = [office arch];

  # Bait runtime keys for the pite canary. Same env-var names as the real
  # runtime file but with canarytokens.org-issued AWS-shaped tokens that ping
  # a webhook on use. See nixos/pite-canary.nix.
  "llm-runtime-keys-bait.age".publicKeys = [pite];

  "hass-credentials.age".publicKeys = [arch];
  "canary-tokens.age".publicKeys = [office arch pite];

  # Vast.ai rented-GPU connection info, sourced by the vast-* fish
  # functions in home-cli.nix. Edited via `agenix -e` each time a new
  # instance is rented — no nix rebuild needed.
  # Format (envsource will read each line):
  #   VAST_HOST=1.2.3.4
  #   VAST_SSH_PORT=12345
  #   VAST_SSH_USER=root
  #   VAST_VLLM_PORT=8000          # remote port vLLM listens on
  #   VAST_LOCAL_PORT=8001         # local port the tunnel binds (must match models.yml)
  #   VAST_MODEL=deepseek-ai/DeepSeek-V4-Flash
  #   VAST_SERVED_MODEL_NAME=deepseek-v4-flash   # optional; matches models.yml id
  #   VAST_MAX_MODEL_LEN=1000000   # optional; defaults to 1000000
  #   VAST_GPU_MEM_UTIL=0.95       # optional; defaults to 0.95
  #   VAST_HF_TOKEN=hf_...         # optional; for gated models
  #   VAST_TOOL_CALL_PARSER=       # optional; e.g. qwen3_xml
  #   VAST_REASONING_PARSER=       # optional; e.g. qwen3
  #   VAST_EXTRA_ARGS=             # optional; extra `vllm serve` flags
  #   VAST_SSH_PRIVATE_KEY_B64=<base64 -w0 of an ed25519 private key>
  # Generate the key once: `ssh-keygen -t ed25519 -f /tmp/vast-key -N ""`
  # then paste its public half into the Vast.ai instance launch form and
  # set VAST_SSH_PRIVATE_KEY_B64=$(base64 -w0 /tmp/vast-key).
  "vast-connection.age".publicKeys = [office arch];
}
