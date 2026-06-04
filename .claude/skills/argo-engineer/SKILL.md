---
description: Diagnose, modify, and manage ArgoCD GitOps deployments through declarative local changes
argument-hint: (none — describe what you want to do in your prompt)
allowed-tools: Read, Search, Find, Write, Edit, Bash, Task, WebSearch
tool-hints: |
  All k8s mutations are done through local files only — see Safety Constraints below.
  Verify k8s context before any action with `hostname` and `kubectl config get-contexts`.
  Remote diagnostics via `ssh closet.local kubectl ...` (home cluster). Ask before switching kubectl context.
  argocd CLI: read-only if configured. Check with `argocd context list`.
  When unsure about the target Argo environment, STOP and ASK. Never guess.
  Tool-hints are quick reference; full safety rules are in the Safety Constraints section.
---
## First-Run Bootstrap

When the skill is first loaded in a session, immediately snapshot the environment.

**Do NOT change kubectl context automatically.** Run these commands to learn what context we're in, then tell the user what you found and ask before switching.

```
# System context
hostname
pwd

# Kubernetes context
kubectl config get-contexts
kubectl config current-context
ls ~/.kube/  # available kubeconfig files

# Git context
git remote -v
git status

# ArgoCD CLI (if configured)
argocd context list

# SSH connectivity check (home cluster only — skip if obviously wrong repo)
ssh -o ConnectTimeout=2 -o BatchMode=yes closet.local 'hostname' 2>/dev/null || echo "closet.local unreachable"
```

After collecting this data, present a structured summary:
- **Current host** and **working directory**
- **Current k8s context** and whether it matches the likely target repo
- **Git remote** and **dirty/clean state**
- **SSH access to closet.local** (reachable / unreachable)

Then, if the current k8s context does NOT match the expected context for the detected repo:
- "The current context is `X`, but repo `~/repos/argo/` expects `closet-as-developer`. May I switch to the correct context?"
- Wait for user approval before running `kubectl config use-context ...`

If no repo can be confidently detected from cwd, ask the user:
- "I can't auto-detect the target Argo repo from the current directory. Which one should I operate on?"

If kubectl is unreachable or no k8s context is configured, note this and proceed with local file inspection only — document assumptions about cluster state.

## Usage

**Invocation:** `/skill:argo-engineer`

This skill takes no formal arguments. Describe what you want to do in your prompt — diagnostics, environment review, local file modifications, commits, or anything else related to ArgoCD operations.

This skill never runs direct Kubernetes mutations (`kubectl apply`, `kubectl delete`, etc.). All changes must be made declaratively through local Argo manifest files — edit the YAML, commit, and push for ArgoCD to sync.

**Examples:**
- `/skill:argo-engineer` — Let the agent auto-detect what you need or ask
- `/skill:argo-engineer check the sync status of all applications`
- `/skill:argo-engineer add a new deployment for my-app to the home cluster`
- `/skill:argo-engineer what's the current state of the DigitalOcean cluster?`

---

## Mode: ArgoCD Operations

### Phase 1 — Identify the target environment

Determine which ArgoCD repo and Kubernetes cluster this task targets.

**Step 1: Detect the repo from the current working directory.**
- If cwd is inside or below `~/repos/argo/` → **Home cluster** (k3s on closet/arch/nas)
- If cwd is inside or below `~/repos/2143-k8s/` → **DigitalOcean cluster** (DOKS)
- If cwd is inside or below `~/repos/2143-59s/` → **Hetzner cluster** (Hetzner k3s)
- If cwd is a parent directory (e.g., `~/repos/`) or outside all known repos, ask the user which target.

**Step 2: Verify Kubernetes context matches.**
```
hostname
kubectl config get-contexts
kubectl config current-context
```

Cross-reference:

| K8s Context | Expected Argo Repo | Cluster |
|-------------|-------------------|---------|
| `2143prod` | `~/repos/2143-k8s/` | DigitalOcean DOKS |
| `closet-as-developer` | `~/repos/argo/` | Home k3s |
| `closet-as-viewer` | `~/repos/argo/` | Home k3s (read-only) |

**Step 3: Read the repository structure for context.**
- Read the README.md at the repo root.
- Check `git remote -v` to confirm which repo we're in.
- For home cluster: read `apps/` and `workloads/` to understand the deployment layout.
- For DO cluster: read `argocd/README.md` and check `argocd/apps/`.
- For Hetzner cluster: read `argocd/root-app.yaml` and check wave ordering.

**Step 4: If any mismatch or uncertainty — STOP AND ASK.**
If the k8s context does not match the expected repo, if the cwd is ambiguous, or if you cannot confidently identify the target environment, stop and ask the user:
- "I'm seeing X but expected Y. Which cluster/repo should I target?"

### Phase 2 — Understand what to do

Parse the user's prompt. Common task categories:

| Category | What to do | Example prompt |
|----------|-----------|---------------|
| **Diagnose** | Read-only cluster inspection, sync status, pod health | "check the home cluster sync status" |
| **Explore** | Read and summarize Argo setup, Application definitions | "what apps are deployed on DO?" |
| **Modify** | Edit local YAML manifests | "add an ingress to the grocy workload" |
| **Commit** | Stage, commit, and push changes | "commit those changes" |
| **Create** | New Application definition or workload | "create a new Argo app for my-api" |

Confirm your understanding with the user before making any changes:
- For diagnostics: "I'll check sync status by reading Argo Applications and running `kubectl get pods -A` via [ssh closet / local kubectl]. Continue?"
- For modifications: "I'll edit `workloads/grocy/ingress.yaml` in `~/repos/argo/` to add the new hostname. Continue?"

### Phase 3 — Execute

#### A. Diagnostics

Read-only inspection. Pick the right method based on the target cluster:

**DigitalOcean (2143prod):**
```
kubectl config use-context 2143prod
kubectl get pods -A
kubectl get applications -n argocd
kubectl get applications -n argocd -o wide
kubectl describe application <name> -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100
```

Use local files for additional context:
```
read apps/ (Argo Application definitions)
read workloads/<service>/ (actual manifests)
```

**Home cluster (k3s):**
SSH to a control-plane node for kubectl access:
```
ssh closet.local kubectl get nodes
ssh closet.local kubectl get pods -A
ssh closet.local kubectl get applications -n argocd
ssh closet.local kubectl describe application <name> -n argocd
ssh closet.local 'kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100'
ssh nas sudo k3s kubectl get pods -A
```

Use local files for additional context (read `apps/` and `workloads/`).

**argocd CLI (if configured):**
```
argocd context list
argocd context use <name>
argocd app list
argocd app get <app-name>
argocd app sync <app-name> --dry-run
argocd app diff <app-name>
```

If argocd CLI has no configured context, inform the user and fall back to kubectl + local file inspection.

**Task subagents:** For broad diagnostics spanning many apps/namespaces, use Task subagents to fan out parallel operations (e.g., checking status of every workload simultaneously).

**If kubectl is unreachable:** If no k8s context is available, no kubectl config exists, or connections fail:
- Work entirely from local files — Application YAMLs represent the **desired state** the cluster should converge to
- Check `git log --oneline -10` in the repo to understand what was last deployed
- Read any available documentation, READMEs, or Argo manifests
- If SSH to cluster nodes is possible (`closet.local`, `nas`), try remote kubectl as a fallback
- **Explicitly document your assumptions**: "No k8s context available — proceeding based on local files only. Last commit was <X>. Cluster state may differ from local files."
- Do NOT guess cluster state beyond what local files and git history tell you

#### B. Modify (local Argo manifest files)

When changing local manifests, always work within the identified Argo repo:

1. **Read the current file** to understand existing structure:
   ```
   read workloads/<service>/deployment.yaml
   ```

2. **Make the change** using `edit` or `write` on the local YAML file.

3. **Verify the change** — read the file back:
   ```
   read workloads/<service>/deployment.yaml
   ```

4. **Run `git diff`** to confirm exactly what changed.

5. **Tell the user:** "Changed `workloads/grocy/ingress.yaml`. Commit and push for ArgoCD to sync."

**What to NEVER do when modifying:**
- NEVER run `kubectl apply -f <file>` or `kubectl apply -k <dir>`
- NEVER run `argocd app set ...` or any argocd mutation command
- NEVER edit files in a repo without first confirming which repo you're in
- NEVER modify files without understanding what they do — read first

#### C. Commit

When the user asks to commit:

0. **Check for dirty git state first.** Run `git status`. If there are uncommitted changes unrelated to the current task, tell the user and STOP — do not commit without explicit direction on how to handle them.
1. Run `git status` and `git diff` to review all changes.
2. Verify the changes are in the correct repo.
3. Generate a descriptive commit message.
4. Use `git add <files>` and `git commit -m "message"`.
5. Inform: "Committed. Push with `git push` to trigger ArgoCD sync. **Pushing to the Argo repo deploys instantly** — this is a fully declarative setup where the Git repo state equals the deployment state. Confirm with the user before pushing."

Sample commit messages:
- `feat(argo): add ingress for grocy service`
- `fix(workloads): update teamspeak PVC name to match Longhorn`
- `chore(argocd): update ArgoCD server image to v2.14`

#### D. Create (new Application or workload)

When creating new manifests:

0. **Read existing files in the target directory first** to understand the repo's conventions. Read at least 1-2 existing examples before creating anything new.
1. **Study existing examples** in the same Argo repo to match conventions.
   - Home cluster: `apps/<name>.yaml` → Application YAML, `workloads/<name>/` → manifests
   - DO cluster: `base/` for base manifests, `overlays/prod/` for overlays, kustomize-aware
   - Hetzner cluster: wave-based ordering, add to the correct `argocd/wave-N/`
2. **If the repo has a specific pattern, follow it.** Don't invent a different structure.
3. **Write the new file** using `write`.
4. **Inform user** of what was created and suggest commit + push.

### Phase 4 — Verify

After any modification:

1. Re-read changed files to confirm correctness.
2. Run `git diff --stat` to see the scope of changes.
3. If changes were pushed, suggest checking sync:
   ```
   kubectl get applications -n argocd -w
   ```

### Safety Constraints

These rules are **mandatory** and must never be violated:

1. **NEVER** run `kubectl apply`, `kubectl delete`, `kubectl replace`, `kubectl create`, `kubectl patch`, or any imperative k8s mutation command.
2. **NEVER** run `argocd app sync`, `argocd app set`, `argocd app create`, `argocd app delete`, or any argocd mutation command.
3. **NEVER** assume which cluster you are connected to. Always run `kubectl config get-contexts` before any kubectl command.
4. **NEVER** make changes without first reading and understanding the current state.
5. **ALWAYS** verify the Argo repo and k8s context before any modification.
6. **ALWAYS** stop and ask the user when:
   - Unsure which Argo environment to target
   - The k8s context doesn't match the expected environment
   - Making changes that affect multiple clusters or namespaces
   - Something looks unexpected or different from convention
7. **If no README exists** for a repo, you may suggest creating one but don't create it without asking.
8. **Remote SSH** to cluster nodes is allowed for read-only diagnostics only. Never run `kubectl apply` over SSH.
9. **All k8s mutations** flow through this exact path: local file edit → git commit → git push → ArgoCD auto-sync.
10. **Do NOT change kubectl context automatically** — always tell the user what context switch is needed and ask for approval first.
11. **If there is dirty git state** (uncommitted changes unrelated to the current task), tell the user and STOP. Do not proceed with commits or modifications without explicit direction.

---

## Environment Reference

### Home Cluster (`~/repos/argo/`)

Kubernetes: k3s HA (embedded etcd) on closet/arch/nas with kube-vip VIP at `192.168.5.10`.
Access via SSH to control-plane nodes (no direct kubectl from the workstation unless context switch).

```
K8s Contexts:   closet-as-developer, closet-as-viewer
SSH Nodes:      closet.local, nas (sudo k3s kubectl)
Structure:
  apps/         — ArgoCD Application YAMLs (one per service)
  workloads/    — Kubernetes manifests organized by service
  roles/        — RBAC configuration
  scripts/      — Utility scripts
  main.yaml     — Root Application (App-of-Apps)
```

Key commands:
```
ssh closet.local kubectl get applications -n argocd
ssh closet.local kubectl get pods -A
ssh nas sudo k3s kubectl get nodes
```

### DigitalOcean Cluster (`~/repos/2143-k8s/`)

Kubernetes: DOKS (DigitalOcean managed Kubernetes).
Access via direct kubectl with `2143prod` context.

```
K8s Context:    2143prod
Structure:
  argocd/
    apps/        — ArgoCD Applications (prod.yaml, root.yaml)
    bootstrap/   — ArgoCD installation manifests
    projects/    — AppProject definitions
    repos/       — Repository access credentials
    README.md    — Documentation
  base/          — Base Kubernetes manifests
  overlays/      — Environment overlays (prod, dev)
```

Key commands:
```
kubectl config use-context 2143prod
kubectl get applications -n argocd
kubectl get pods -A
```

The Application of Apps pattern: `root.yaml` → `argocd.yaml` (self-bootstrap) + `prod.yaml` (production workloads from `overlays/prod/`).

### Hetzner Cluster (`~/repos/2143-59s/`)

Kubernetes: k3s on Hetzner Cloud.
Access via Tailscale or specific kubeconfig (ask user if not auto-detected).

```
Structure:
  argocd/
    root-app.yaml   — Root Application
    wave--2/        — Namespaces
    wave--1/        — Secrets
    wave-0/         — cilium, cert-manager
    wave-1/         — longhorn, traefik
    wave-2/         — k8gb, externaldns
    wave-3/         — istio, crowdsec
    wave-4/         — seaweedfs
    wave-5/         — temporal, cloudnativepg, mongodb
    wave-6/         — apps
    wave-7/         — monitoring
    wave-8/         — backups
    argocd-cm.yaml  — ArgoCD ConfigMap
  clusters/         — Cluster configuration
```

Waves enforce deploy ordering (negative to positive). New applications should be placed in the appropriate wave based on dependencies.

---

## Intelligent Triage

When answering a question or diagnosing a problem:

1. **Start with local files** — Read Application YAMLs and workload manifests for the authoritative desired state.
2. **Cross-reference with live state** — Use read-only kubectl (direct or via SSH) to see what's actually running.
3. **Check sync status** — `kubectl get applications -n argocd` shows healthy/out-of-sync state.
4. **For the home cluster**, prefer SSH-based kubectl — the workstation's default context points to DigitalOcean (`2143prod`).
5. **For sync issues**, look at the ArgoCD server logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=200`.
6. **Don't repeat work** — if you already fetched live state in this session, reuse it.
7. **If argocd CLI is configured**, use `argocd app diff <name>` for the clearest view of drift.

---

## Safety Quick Reference

| Action | Allowed? | Notes |
|--------|----------|-------|
| `kubectl get/describe/logs` | Yes | Read-only, verify context first |
| `kubectl apply/delete/patch` | **NO** | Never. Use local files + ArgoCD sync |
| `kubectl config get-contexts` | Yes | Always before any kubectl command |
| `ssh closet.local kubectl get ...` | Yes | Read-only remote diag, home cluster |
| `ssh closet.local kubectl apply` | **NO** | Never apply over SSH |
| `argocd app list/get` | Yes | Read-only, if server context configured |
| `argocd app sync` | **NO** | Never. Push to Git and let ArgoCD sync |
| `argocd app diff --dry-run` | Yes | Safe preview |
| `git add/commit` | Yes | After verifying environment |
`git push` | **ASK** | Pushing deploys instantly — Git state = deployment state. Always confirm before pushing.
| Edit local YAML files | Yes | After verifying environment |
Edit files in wrong repo | **NO** | Always verify repo first
`kubectl config use-context <name>` | **ASK** | Tell the user what switch is needed and why; ask before changing
Modified files already dirty (unrelated changes) | **STOP** | Warn user and stop; do not proceed without direction
