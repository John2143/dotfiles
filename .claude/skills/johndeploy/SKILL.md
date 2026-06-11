---
description: Run the full johndeploy provisioning loop — tofu apply, deploy NixOS+k3s, verify, fix, commit, destroy
argument-hint: ''
allowed-tools: Read, Search, Find, Write, Edit, Bash, Task, Ask
tool-hints: |
  Use tofu-wrap in terraform/ for apply/destroy (wraps agenix credential sourcing).
  Use deploy_all.py for unattended deployment, deploy_one() or manual SSH for recovery.
  Time infra operations with `time tofu-wrap apply`. This produces a `real XmYs` line.
  Clean stale known_hosts with `ssh-keygen -R <ip>` before first SSH to recreated VMs.
  Use `agenix -d <secret.age> -i ~/.ssh/age` in `dotfiles/nixos/cluster/secrets/` for creds.
  Always run from `2143-59s/terraform/` for tofu and deploy commands.
  capture_output=True is needed in subprocess.run — do not assume `subprocess.check_output`.
---

## Usage

**Invocation:** `/skill:johndeploy`

Runs the full provisioning loop end-to-end with no arguments: provision cloud infra via OpenTofu, deploy NixOS + k3s via deploy_all.py (or manual recovery), verify each node, fix any issues found, write a metrics document, commit findings to git, and tear everything down.
State is tracked in `~/.claude/skills/johndeploy/.johndeploy-state.json` — a loop counter prevents more than 5 runs without manual reset.


### Phase 0 — Pre-Flight Checks

**Goal:** Validate that running another loop makes sense. May abort if conditions aren't met.

1. **Check cwd:** `cd ~/repos/2143-59s/terraform` must exist. If not, report and abort.

2. **Load loop state:** Read `~/.claude/skills/johndeploy/.johndeploy-state.json` (create with `{"run_count": 0, "last_run": null, "last_commit": null}` if missing).

3. **Max loops guard:** If `run_count >= 5`, print:
   ```
   ⛔ johndeploy: reached max 5 loops. Reset state to re-enable:
      echo '{"run_count": 0, "last_run": null, "last_commit": null}' > ~/.claude/skills/johndeploy/.johndeploy-state.json
   ```
   Then abort — do not proceed.

4. **Gap evaluation (has anything changed?):** Check if deploy scripts changed since last run:
   ```bash
   last_commit=$(cat ~/.claude/skills/johndeploy/.johndeploy-state.json | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_commit',''))")
   if [ -n "$last_commit" ]; then
     git log --oneline "$last_commit..HEAD" -- terraform/deploy.py terraform/deploy_all.py terraform/post_deploy.py 2>/dev/null
   fi
   ```
   If no commits touch those files since `last_commit` AND this is not the first run:
   ```
   ⚠️  No changes to deploy scripts since last run (commit $last_commit).
   Proceeding to collect fresh timing metrics.
   ```

5. **Increment counter and save time:** Update the state:
   ```python
   state["run_count"] += 1
   state["last_run"] = "YYYY-MM-DD HH:MM"
   ```
   Write back to `.johndeploy-state.json`.

## Mode: Full Loop

This is the main mode. Run when you want to test the full provisioning pipeline and collect timing metrics. Every phase is sequential — do not skip phases.

### Phase 1 — Provision

**Goal:** Create all cloud resources (droplets, servers, floating IPs, SSH keys).

1. `cd ~/repos/2143-59s/terraform`
2. Run: `time ./tofu-wrap apply -auto-approve 2>&1`
3. From the output, extract:
   - `tofu_apply_seconds` — parse the `real` line (the `time` command output). If `real 0m43.788s`, that's 44s.
   - `cluster_names` — from `output "cluster_names"` in the tofu output
   - For each cluster: `server_ip`, `fip` from the outputs section
4. Store in a temp dictionary keyed by cluster name:
   ```python
   {
     "do-nyc-k3s": {"server_ip": "...", "fip": "..."},
     "hetzner-ashburn-k3s": {"server_ip": "...", "fip": "..."},
     ...
   }
   ```
5. If apply fails with a resource error, retry once after 10s. If it fails again, report and abort.

**Known issue:** Hetzner servers take 30-60s after creation for SSH to become available. Store `tofu_provision_time` for the metrics doc.

### Phase 2 — Clean Known Hosts and Pre-Warm SSH

**Goal:** Ensure SSH works to all nodes before running deploy.

1. For each node IP, remove old host keys: `ssh-keygen -R <ip> 2>/dev/null`
2. For each node IP, pre-warm: `ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 root@<ip> "hostname"` (accepts the new host key)
3. If any node is unreachable after 5 retries (10s apart), wait 60s and retry (Hetzner nodes are slow to boot)
4. Decrypt the SSH key:
   ```bash
   cd ~/repos/dotfiles/nixos/cluster/secrets
   KEY=$(agenix -d cloud-ssh-key.age -i ~/.ssh/age)
   ```

### Phase 3 — Deploy

**Goal:** Run the deployment pipeline on all 3 nodes.

1. `cd ~/repos/2143-59s/terraform`
2. Run: `python3 deploy_all.py --workers 1 2>&1`
3. Capture the entire output — it contains the timing metrics table at the end.
4. Extract timing data: the metrics table appears as a section starting with `Deployment Timing Metrics`. Parse rows and durations.

**Recovery (if deploy fails on specific nodes):**

The most common failure point is DO's nixos-infect Phase 2 where `tailscaled-autoconnect` references `/run/agenix/hetzner/headscale-preauth-key` which doesn't exist on DO. This causes `nixos-rebuild switch-to-configuration` exit code 4 but the system is actually installed and bootable. To recover:

1. Verify SSH to the failed node works
2. Copy age key: `scp ~/.ssh/age root@<ip>:/etc/ssh/age-identity`
3. Activate agenix: `ssh root@<ip> "/run/current-system/activate"`
4. Restart k3s: `ssh root@<ip> "systemctl restart k3s"`
5. Connect tailscale: read the preauth key from `/run/agenix/hetzner/headscale-preauth-key` (if it exists) and run `tailscale up --reset --login-server=http://headscale.9s.pics:6767 --authkey='<key>' --accept-routes`
6. Wait 5s, verify: `ssh root@<ip> "kubectl get nodes -o wide | tail -2"`

Hetzner nixos-anywhere rarely fails. If it does, the error output contains enough context to fix (usually a disk layout or networking issue). Read the terraform/modules/ disko config and the flake config for the failing host.

### Phase 4 — Verify and Diagnose

**Goal:** Verify all nodes are functional and diagnose any failures.

For each node, SSH in and collect:

```bash
hostname
kubectl get nodes -o wide 2>&1 | tail -3
tailscale status 2>&1 | head -3
cat /etc/hostname
k3s --version 2>&1 | head -1
```

Build a status dict like:
```python
{
  "do-nyc-k3s": {"k3s_ready": True, "tailscale_ip": "100.64.0.39", "version": "v1.35.4+k3s1"},
  "hetzner-ashburn-k3s": {"k3s_ready": True, "tailscale_ip": "100.64.0.37", "version": "v1.35.4+k3s1"},
}
```

If any node fails k3s check, diagnose:
- `journalctl -u k3s --no-pager -n 50` — k3s service logs
- `systemctl status k3s` — service status
- `ls /run/agenix/` — check if secrets decrypted
- `cat /etc/systemd/system/k3s.service.env 2>/dev/null || true` — k3s env

### Phase 5 — Fix and Document

**Goal:** Fix any issues found in deploy scripts or NixOS config, and write timing metrics.

**Fixing code:**

If a bug is found (e.g., DO's missing tailscale preauth path, tailscale timeout too short):
1. Fix the deploy script in `~/repos/2143-59s/terraform/`
2. Fix any NixOS config in `~/repos/dotfiles/nixos/cluster/`
3. Test the fix if feasible (re-run the relevant deploy_one for the affected node)

**Writing metrics doc:**

Write `METRICS-YYYYMMDD.md` to the skill directory (`~/.claude/skills/johndeploy/`):

```markdown
# johndeploy: YYYY-MM-DD

## Timing

| Stage | DO nyc1 | Hetzner ashburn | Hetzner hillsboro |
|-------|---------|-----------------|-------------------|
| tofu apply | Ns | — | — |
| SSH ready | Ns | Ns | Ns |
| nixos-infect/nixos-anywhere | Nm | Nm | Nm |
| nixos-rebuild | Nm | — | — |
| Post-deploy | Ns | Ns | Ns |
| **k3s Ready** | Nm | Nm | Nm |
| **Total wall** | Nm (N nodes) | | |

## Results
- do-nyc-k3s: ✅ k3s v1.35.4, TS 100.64.0.x
- hetzner-ashburn-k3s: ✅ k3s ...
- hetzner-hillsboro-k3s: ✅ k3s ...

## Issues Found
1. ... (description, root cause, fix applied)

## Fixes Applied
- File X: what changed and why
- File Y: what changed and why
```

If no issues were found, write "No issues found" instead of the Issues/Fixes sections.

### Phase 6 — Commit

**Goal:** Commit all changes to both repos with structured messages.

1. `cd ~/repos/2143-59s`
2. `git add -A`
3. `git status` — verify only intended files are staged
4. Commit body should include:
   ```
   johndeploy: YYYY-MM-DD — loop results

   Timing:
   - tofu apply: Xs
   - DO deploy: Xm (nixos-infect)
   - Hetzner ashburn: Xm (nixos-anywhere)
   - Hetzner hillsboro: Xm (nixos-anywhere)
   - Total wall: Xm

   Results: N/N nodes k3s Ready
   Tailscale: N/N connected
   Metrics: saved to ~/.claude/skills/johndeploy/METRICS-YYYYMMDD.md
   ```
5. `git commit -m "..."` with the full message
6. `git push`

If NixOS config changes were made in dotfiles:
1. `cd ~/repos/dotfiles`
2. `git add -A && git commit -m "johndeploy: fix ..." && git push`
3. Also update the state file with that commit hash.

**Save commit hash to state file:**
```bash
cd ~/repos/2143-59s
last_commit=$(git rev-parse HEAD)
python3 -c "
import json
state = json.load(open('$HOME/.claude/skills/johndeploy/.johndeploy-state.json'))
state['last_commit'] = '$last_commit'
json.dump(state, open('$HOME/.claude/skills/johndeploy/.johndeploy-state.json', 'w'))
"
```

### Phase 7 — Destroy

**Goal:** Tear down all cloud resources to save cost.

1. `cd ~/repos/2143-59s/terraform`
2. Run: `time ./tofu-wrap destroy -auto-approve 2>&1`
3. Extract destroy timing from `real` line
4. Verify `Destroy complete! Resources: 10 destroyed.` appears in output
5. Append destroy timing to the metrics doc

### Phase 8 — Report

**Goal:** Present a concise summary of what happened.

Print to the conversation:
```
=== johndeploy YYYY-MM-DD complete ===
Provision: Xs | Deploy: Ym | Test: fix N issues | Destroy: Xs
Total wall: Zm across N nodes
k3s: N/N Ready | Tailscale: N/N connected
Issues: N fixed (see METRICS-YYYYMMDD.md)
Commits: commit-hash (2143-59s), commit-hash (dotfiles)
```

**Loop complete.** After this report, stop. Do not start another loop automatically. If the user wants another iteration, they will invoke the skill again (at which point Phase 0's max-loops guard or gap evaluation may stop it). This is the end of the full loop — all resources destroyed, all findings committed and documented.

## Mode: Review Past Run

Use when the user wants to see what happened in a previous loop. This is read-only — never modify files or run infra commands.

1. Check `~/.claude/skills/johndeploy/` for `METRICS-*.md` files, sorted by date (newest first)
2. If user specified a date, read that file; if not, read the most recent one
3. Show the file content as a formatted report
4. Also show the git log for the corresponding date:
   ```bash
   cd ~/repos/2143-59s
   git log --oneline --since="YYYY-MM-DD" --until="YYYY-MM-DD+1day"
   ```
5. Report: metrics table, results, issues found, fixes applied

No files modified, no commands run beyond read/git log.
