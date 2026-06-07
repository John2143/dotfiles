"""Shared helpers for multi-cloud resource provisioning."""

from typing import Optional
import subprocess
import os
import tempfile
import json


def get_ssh_public_key(key_name: str) -> str:
    """Read the public key from the agenix-decrypted cloud-ssh-key.

    In production, this key is stored encrypted via agenix at
    cluster/secrets/cloud-ssh-key.age. For now, fall back to
    $HOME/.ssh/id_ed25519.pub if the agenix key isn't available.
    """
    age_key_path = os.path.expanduser(
        "~/repos/dotfiles/nixos/cluster/secrets/cloud-ssh-key.age"
    )
    if os.path.exists(age_key_path):
        # Decrypt with agenix (uses cwd-aware decrypt_age_file)
        private_key = decrypt_age_file(age_key_path)
        # Write decrypted key to tempfile, derive public key
        with tempfile.NamedTemporaryFile(mode="w", suffix=".pem", delete=False) as f:
            f.write(private_key + "\n")
            tmp_path = f.name
        os.chmod(tmp_path, 0o600)
        pubkey = subprocess.run(
            ["ssh-keygen", "-y", "-f", tmp_path],
            capture_output=True, text=True,
        ).stdout.strip()
        os.unlink(tmp_path)
        if pubkey:
            return pubkey

    # Fallback: use personal key for initial provisioning
    ssh_path = os.path.expanduser("~/.ssh/id_ed25519.pub")
    if os.path.exists(ssh_path):
        with open(ssh_path) as f:
            return f.read().strip()

    raise RuntimeError(f"No SSH public key found. Generate k3s-cloud key first.")


def decrypt_age_file(path: str) -> str:
    """Decrypt an agenix-encrypted file, return contents."""
    age_key = os.path.expanduser("~/.ssh/age")
    secrets_dir = os.path.dirname(os.path.abspath(path))
    rel_path = os.path.basename(path)
    result = subprocess.run(
        ["agenix", "-d", rel_path, "-i", age_key],
        capture_output=True, text=True,
        cwd=secrets_dir,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to decrypt {path}: {result.stderr}")
    return result.stdout.strip()

def get_cloud_ssh_key_path() -> str:
    """Decrypt the k3s-cloud SSH key to a temp file, return its path.

    The caller is responsible for cleaning up the temp file after use.
    Pulumi will run this once at the start of provisioning.
    """
    age_key_path = os.path.expanduser(
        "~/repos/dotfiles/nixos/cluster/secrets/cloud-ssh-key.age"
    )
    if not os.path.exists(age_key_path):
        raise RuntimeError(f"Cloud SSH key not found at {age_key_path}")

    private_key = decrypt_age_file(age_key_path)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".pem", prefix="k3s-cloud-", delete=False
    ) as f:
        f.write(private_key + "\n")
        tmp_path = f.name

    os.chmod(tmp_path, 0o600)
    return tmp_path

def ssh_exec(host: str, command: str, user: str = "root", timeout: int = 120) -> str:
    """Execute a command on a remote host via SSH."""
    result = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=accept-new",
         "-o", "ConnectTimeout=10",
         f"{user}@{host}", command],
        capture_output=True, text=True, timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"SSH to {host} failed (exit {result.returncode}):\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout


def kubectl_apply(host: str, yaml_str: str, user: str = "root") -> str:
    """Apply a Kubernetes manifest via SSH to a remote node."""
    return ssh_exec(
        host,
        f"kubectl apply -f - <<'EOF'\n{yaml_str}\nEOF",
        user=user,
        timeout=30,
    )


def render_fip_configmap(fip_registry: dict, zones: dict) -> str:
    """Render the FIP registry + zones as a Kubernetes ConfigMap YAML."""
    fips_json = json.dumps(fip_registry, indent=2)
    zones_json = json.dumps(zones, indent=2)

    # Indent JSON payloads for YAML block scalar
    fips_block = "    " + "\n    ".join(fips_json.split("\n"))
    zones_block = "    " + "\n    ".join(zones_json.split("\n"))

    return f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: fip-registry
  namespace: k8gb
data:
  fips.json: |
{fips_block}
  zones.json: |
{zones_block}
"""