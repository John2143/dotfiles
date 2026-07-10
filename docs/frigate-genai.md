# Frigate GenAI — Architecture & Operations

## What it is

Frigate GenAI watches Frigate NVR's MQTT event stream, starts a Temporal workflow for each detection event, and uses a vision-capable LLM (Gemini or Ollama) to describe what happened in natural language. Every event goes through: frame extraction → multi-turn LLM analysis with tool use → description written back to Frigate's sub_label. The system runs on a home k3s cluster, scales to zero when idle, and deploys via WorkerDeployments (Temporal-managed rainbow deploys with zero-downtime progressive rollout).

---

## Architecture diagram

```
Frgate NVR ──MQTT──> triggers pod (Temporal workflow starter)
    │                    │
    │              Temporal Server
    │             /    │     │      \
    │     genai-tasks  ffmpeg-tasks  gemini-tasks  ollama-tasks
    │     (misc acts)  (transcoding) (vision LLM)  (local LLM)
    │         │            │            │             │
    │     triggers-     ffmpeg-      gemini-       ollama-
    │     vXX pod      vXX pod      vXX pods      vXX pod
    │     (no KEDA)   (KEDA 0-3)   (KEDA 0-5)    (KEDA 0-1)
    │
    │              LiteLLM Proxy (2 replicas, HA)
    │              /         \
    │         Gemini API    Ollama (local)
    │
    └── sub_label written back to Frigate API
```

---

## Component roles

### 1. Triggers pod (always running, no KEDA)

**Mode:** `--mode=triggers`
**Task queue:** `genai-tasks` (misc activities only)
**WorkerDeployment:** `frigate-genai-triggers`
**Rollout strategy:** `AllAtOnce` (no progressive ramp for single-replica)

The triggers pod is the **brain stem** of the system. It:

1. **Listens to MQTT** from Frigate NVR. When an event ends, it receives the event payload (camera, label, start/end times, score, zones, snapshot URL).

2. **Starts a Temporal workflow** — `GenAIWorkflow` — one per event. The workflow orchestrates frame extraction, LLM analysis, and description update. It passes the event metadata as workflow input.

3. **Serves an HTTP API** on port 9090 for:
   - `GET /api/stats` — event counts, MQTT/Temporal connection status
   - `POST /reprocess/<event_id>` — re-trigger a failed event
   - `GET /files/events/<event_id>/agent-log.html` — browsable per-event agent trace
   - `POST /api/pause/<model>` / `DELETE /api/pause/<model>` / `GET /api/pause` — pause/unpause models

4. **Hosts misc activities** — `select_model_activity`, `update_description_activity`, `fetch_snapshot_activity`, `cleanup_cancelled_activity`, `init_agent_state_activity`, `tool_upscale_activity`. These run on the triggers pod because they're lightweight and don't need GPU.

5. **Runs the GenAIWorkflow listener** — the triggers pod is the only one that listens on `genai-tasks` for the workflow itself. Other pods only pull activity tasks.

**Why one replica?** The MQTT subscriber and workflow starter are single-writer by nature. A second triggers pod would double-fire workflows. The Temporal workflow listener itself scales via activity distribution across queues.

**Why no KEDA?** The triggers pod must always run to receive MQTT events. If it scaled to zero, events would be missed (MQTT QoS 1 means they queue at the broker, but Temporal workflows wouldn't start until the pod comes back).

**Resources:** 100m CPU request, 128Mi memory — it's mostly sleeping waiting for MQTT.

### 2. FFmpeg pod (KEDA-scaled, 0-3 replicas)

**Mode:** `--mode=ffmpeg`
**Task queue:** `genai-tasks-ffmpeg`
**WorkerDeployment:** `frigate-genai-ffmpeg`
**Rollout strategy:** `AllAtOnce`

The ffmpeg pod extracts frames from Frigate's HLS recordings. It:

1. **Pulls `.m3u8` HLS streams** from Frigate's `/vod/<camera>/start/<ts>/end/<ts>/index.m3u8` endpoint
2. **Decimates to FPS** (default 1 fps for initial scan; up to source FPS for detail passes)
3. **Returns JPEG byte arrays** to the workflow as a list
4. **Runs two activities:** `transcode_into_parts_activity` (batch extraction for timeline) and `tool_transcode_activity` (single-frame extraction for detailed tool inspection)

**Why KEDA scaled?** FFmpeg is CPU-heavy (software decoding). Multiple events queue up during busy periods, and KEDA scales pods based on `genai-tasks-ffmpeg` queue depth. When idle for 10 minutes, pods scale to zero.

**Why its own task queue?** Isolates CPU-intensive work from LLM work. A Gemini turn shouldn't be delayed by frame extraction backlog, and vice versa.

**Why AllAtOnce rollout?** Single-activity no-state worker — no progressive ramp needed. A new version either extracts frames or it doesn't.

**Max concurrent:** 2 (controlled by `TEMPORAL_MAX_FFMPEG` env). Each ffmpeg process uses one CPU core. Pod spec limits to 1000m CPU.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.

### 3. Gemini pod (KEDA-scaled, 0-5 replicas)

**Mode:** `--mode=genai-gemini`
**Task queues:** `genai-tasks` (misc) + `genai-tasks-gemini` (LLM turns)
**WorkerDeployment:** `frigate-genai-gemini`
**Rollout strategy:** **Progressive** — 10% ramp → 5 min pause → 50% ramp → 5 min pause → 100%

The gemini pod is the **heavy lifter**. It:

1. **Listens on `genai-tasks-gemini`** for LLM turn activities:
   - `run_genai_turn_activity` — the main LLM call with tool use loop
   - `tool_find_keyframes_activity` — deterministic keyframe selection via pixel-difference analysis
   - `tool_frame_diff_activity` — pairwise frame comparison for the LLM to query directly
   - `tool_tag_image_activity` — batched useful/not-useful tagging for per-event working memory
   - `tool_get_snapshot_activity` — fetch a full-resolution camera snapshot
   - `tool_show_frame_activity` — extract a specific frame for the model to inspect
   - `tool_crop_activity` — crop a region of an image
   - `tool_compact_activity` — prune the conversation history to stay under context limits
   - `tool_set_description_activity` — commit the description early (persisted even if workflow later fails)
   - `apply_tool_messages_activity` — merge tool results back into the conversation
   - `summarize_agent_activity` — produce final structured summary
   - `save_agent_log_activity` — archive the full agent conversation to S3

2. **Also listens on `genai-tasks`** for misc activities (model selection, snapshot fetch, cleanup, upscale) — same as triggers pod, providing redundancy.

3. **Calls the Gemini API** through the LiteLLM proxy at `https://llm.2143.me/v1/chat/completions`.

4. **Has 5 concurrent activity slots** per pod, controlled by `TEMPORAL_MAX_GEMINI_GENAI`.

**Why Progressive rollout?** Gemini is the highest-risk deployment. A bad prompt or tool change can waste API credits on every event. The progressive rollout (10% → 50% → 100%) limits blast radius — if v51 has a bug, only 10% of events hit it for the first 5 minutes, and we can revert before the full ramp.

**Why topologySpread?** 4 physical nodes. The topology spread constraint (`maxSkew: 1`, `ScheduleAnyway`) spreads Gemini pods across nodes for fault tolerance. If one node goes down, other nodes still serve LLM turns.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.

### 4. Ollama pod (KEDA-scaled, 0-1 replicas)

**Mode:** `--mode=genai-ollama`
**Task queues:** `genai-tasks` (misc) + `genai-tasks-ollama` (LLM turns)
**WorkerDeployment:** `frigate-genai-ollama`
**Rollout strategy:** `AllAtOnce`

Identical to Gemini pod but calls the **local Ollama API** through LiteLLM. Single replica because the local model can't handle more than one concurrent request.

**Why Ollama?** Optional fallback. The model selector (`select_model_activity`) can route events to Ollama based on weighting. When the user doesn't want to spend API credits on low-confidence events, Ollama handles them for free. Globally pausable via the HTTP API.

**Max concurrent:** 1 (controlled by `TEMPORAL_MAX_OLLAMA_GENAI`). Ollama on a single GPU can only handle one request at a time.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.

---

## Task queues — the routing layer

Temporal separates **where work runs** (task queues) from **what work is** (activities/workflows).

| Task Queue | Purpose | Listeners | Scaled by |
|---|---|---|---|
| `genai-tasks` | Misc activities + workflow listener | triggers (1), gemini (N), ollama (N) | No (triggers) / Yes (gemini/ollama via KEDA) |
| `genai-tasks-gemini` | LLM turns + tool execution (find_keyframes, frame_diff, tag_image, show_frame, crop, compact, set_description, upscale, apply) | gemini only | KEDA (0-5) |
| `genai-tasks-ffmpeg` | Frame extraction | ffmpeg only | KEDA (0-3) |
| `genai-tasks-ollama` | LLM turns via Ollama | ollama only | KEDA (0-1) |

**Why separate queues?** Isolation. A ffmpeg backlog shouldn't block Gemini turns. Gemini rate-limiting shouldn't starve Ollama requests. Each workload can independently scale based on its own queue depth.

**Why do Gemini/Ollama also listen on `genai-tasks`?** Redundancy. The triggers pod runs the workflow and hosts misc activities. If the triggers pod is the only misc activity listener and it's being restarted, no new workflows can start. Gemini and Ollama picking up misc activities provides headroom.

---

## The GenAI Workflow — what happens per event

```
1. MQTT event arrives
   → triggers pod receives it
   → starts GenAIWorkflow

2. select_model_activity
   → reads provider.json config
   → weights gemini vs ollama
   → checks pause state via S3
   → returns selected model

3. transcode_into_parts_activity
   → ffmpeg pod extracts frames at 1 fps from HLS
   → returns JPEG byte list

3.5. find_keyframes — auto-run for clips with >5 frames
   → deterministic pixel-difference analysis picks the 8 most informative frames
   → saves `differences.json` for later `find_keyframes`/`frame_diff` queries
   → injects a zero-cost keyframe summary into the LLM's first turn

4. init_agent_state_activity
   → builds system prompt + tool definitions
   → loads initial frames as base64
   → creates conversation history

5. Loop: run_genai_turn_activity
   → calls LLM via LiteLLM
   → model responds with text or tool calls
   → if tool call:
      → execute tool (crop/show_frame/snapshot/transcode)
      → apply_tool_messages_activity (merge result back)
      → compact if context grows too large
      → loop back to run_genai_turn_activity
   → if text response:
      → break loop

6. summarize_agent_activity
   → produces structured {description, confidence, transcode, tags}

7. update_description_activity
   → POSTs sub_label back to Frigate API
   → updates Frigate event with description

8. save_agent_log_activity + cleanup_cancelled_activity
   → archives full conversation to S3
   → cleans up frame artifacts
```

**Why tools?** The LLM can request additional information mid-analysis — crop a region, extract a specific frame at higher resolution, compare two frames side-by-side. This is more accurate than feeding all frames at once (hits context limits) or feeding only thumbnails (loses detail).

**Why compact?** Gemini context is 1M tokens but gets expensive as it grows. Compacting prunes old turns to a summary, keeping the context window small and cheap.

**Why set_description early?** The `tool_set_description_activity` commits a description mid-analysis. If the workflow later fails (LLM rate limit, timeout), the partial description is already in Frigate. Sunk cost isn't wasted.

---

## Retry policy — differentiated retry

The system uses two retry strategies depending on error type:

### Transient LLM errors — long retry (20 attempts, 1s→60s backoff)

- **RateLimitError (429):** Gemini rate-limiting. Wait and retry — the rate limit window clears.
- **APIStatusError (50x):** LiteLLM proxy or upstream 502/503. Transient outage.
- **Network errors:** DNS resolution failure, connection refused during proxy restart.

**Window:** 20 attempts with exponential backoff from 1s to 60s (~19 minutes total). A litellm pod restart during RollingUpdate takes ~10s — well within the window. Previous policy (5 attempts, ~2 min) couldn't survive a longer outage.

### Permanent errors — instant fail, no retries

- **ValueError, TypeError, RuntimeError:** Code bugs (bad prompt format, type mismatch). Retrying won't fix them.
- **ApplicationError(non_retryable=True):** Tool activities raise this when the model provides invalid arguments:
  - `tool_crop_activity`: crop region is zero-area `(x1==x2, y1==y2)`
  - `tool_show_frame_activity`: frame index out of range
  - `tool_upscale_activity`: input image too large
  - `tool_get_snapshot_activity`: Frigate returns error

**Why differentiate?** Without it, a syntax bug in a tool call would be retried 20 times over 19 minutes, burning API credits and blocking the workflow queue. The model's mistake is permanent — retrying won't produce a different result.

**Why 20 attempts for transient?** Gemini rate limits are typically 60-90 seconds. The old 5-attempt policy exhausted in ~2 minutes — a single rate limit could kill the workflow. 20 attempts with 1s-60s backoff gives enough time to survive 2-3 consecutive rate-limit windows.

### Heartbeat jitter

`_run_with_heartbeat` adds ±20% random jitter to heartbeat intervals to prevent worker stampedes. If all 5 gemini pods heartbeated simultaneously, they'd create a CPU spike. Jitter spreads heartbeats across the period.

---

## Deployment pipeline — from push to running pods

```
git push (dotfiles master)
  → CI: .github/workflows/build-frigate-genai.yml
    → build job:
       nix build → docker tag → ghcr push (v57, v58, ...)
    → update-argo job:
       clone argo repo → sed unsafeCustomBuildID + image + TEMPORAL_WORKER_BUILD_ID into *-workerdeployment.yaml
       → verify tags → smoke-test ffmpeg startup → git commit → git push (argo main)
  → ArgoCD (polls argo main every 3 min):
    → syncs frigate-genai app (WorkerDeployment CRs updated from v51 to v52)
  → Temporal Worker Controller (watches CRs):
    → creates versioned Deployment: frigate-genai-gemini-v52
    → progressive rollout: 10% → pause 5 min → 50% → pause 5 min → 100%
    → old version (v51) sunsets: scaledown 30 min → delete 2h
```

**Why WorkerDeployments instead of direct Deployments?** Traditional Kubernetes Deployments replace pods instantly — every pod gets the new image at once. If the new image has a bug, all workflows fail. WorkerDeployments use Temporal's Pinned versioning — each workflow is pinned to its starting build ID. v51 workflows complete on v51 pods; v52 workflows start on v52 pods. Old pods drain naturally, new pods take new work. Zero interruption to in-flight work.

**Why CI pushes to two repos?** Separates code (dotfiles) from infrastructure state (argo). The dotfiles repo owns the Python code, CI workflow, and Nix build. The argo repo owns the Kubernetes manifests — including the image tags generated by CI. This means rollback is a single `git revert` in the argo repo.

**Why Nix-built images?** The Docker image is a Nix closure — every dependency (Python, PIL, boto3, temporalio, paho-mqtt) is pinned by hash. No `apt-get install` or `pip install` at build time; no dependency drift between CI and production. The image is a reproducible closure of exactly what was tested.

**Why `unsafeCustomBuildID`?** The WorkerDeployment system normally expects the controller to set the build ID. `unsafeCustomBuildID` lets the ArgoCD-managed CR directly specify which version to deploy. The controller reads it and creates versioned Deployments with that build ID in labels. `unsafe` prefix is Temporal's way of saying "you're bypassing the server-managed versioning protocol" — but for GitOps, the server doesn't manage versions; ArgoCD does.

---

## LiteLLM proxy — the LLM gateway

The genai workers never talk directly to Gemini or Ollama. All LLM calls go through **LiteLLM**, a unified proxy at `https://llm.2143.me`.

**Why a proxy?**
- **Model rotation:** LiteLLM can route to different providers by model name without code changes. Switching from `gemini-2.0-flash` to `gemini-2.5-pro` is a proxy config change, not a code deploy.
- **Rate limiting:** LiteLLM handles retry logic and rate-limit backoff upstream of the workers. Workers get simpler error handling.
- **Cost tracking:** LiteLLM logs token usage and cost per request. Search attributes on Temporal workflows track this for per-event cost attribution.
- **Multi-model routing:** Ollama and Gemini are separate backends accessed through the same API — workers use the same `openai` client interface for both.

**Deployment:** 2 replicas across arch and closet nodes (HA). 3Gi memory, RollingUpdate. If Node A's litellm pod restarts, Node B's pod serves traffic. If both restart simultaneously, the retry policy (20 attempts) covers the gap.

**Why 2 replicas?** Single replica was OOM-killed during load spikes (Gemini 2.5-pro responses are large payloads). 3Gi memory handles the peak + RollingUpdate ensures zero-downtime restarts.

---

## KEDA — event-driven scaling

KEDA (Kubernetes Event-Driven Autoscaling) watches Temporal task queue depth and scales pods:

```
Temporal task queue → KEDA temporal scaler → ScaledObject → HPA → Deployment replicas
```

**Per-deployment scaling:**

| Worker | Min | Max | Trigger | Target queue size | Cooldown |
|---|---|---|---|---|---|
| ffmpeg | 0 | 3 | `genai-tasks-ffmpeg` (activity) | 2 | 600s |
| gemini | 0 | 5 | `genai-tasks-gemini` (activity) + `genai-tasks` (activity) | 5 + 2 | 600s |
| ollama | 0 | 1 | `genai-tasks-ollama` (activity) + `genai-tasks` (activity) | 1 + 2 | 600s |
| triggers | 1 | — | Cron trigger (always-on) | — | — |

**Why KEDA instead of HPA on CPU/memory?** CPU/memory HPA doesn't work well for workers that block on network I/O (LLM API calls use 5-10% CPU while waiting for a 30-second response). Queue depth is the true measure of backlog.

**Why cooldown 600s?** Prevents rapid scale-down/scale-up cycles. If a pod scales down too fast, new events that arrive 30 seconds later trigger a scale-up, creating latency. 10-minute cooldown means pods stick around through brief activity gaps.

**Why WorkerResourceTemplate (WRT)?** The WRT is a Temporal WorkerDeployment feature that bridges to KEDA. The controller reads the WRT, patches in the versioned Deployment name (`frigate-genai-gemini-v51`), and creates a ScaledObject targeting the correct version's pods. Without WRTs, KEDA would scale old deployments.

---

## S3 (SeaweedFS) — state & artifacts

All event data lives in SeaweedFS S3 (`frigate-genai` bucket):

| Path | Purpose | TTL |
|---|---|---|
| `events/<event_id>/frames/` | Extracted JPEG frames | 14d |
| `events/<event_id>/agent/` | Conversation history, agent log | 14d |
| `events/_paused/<model>` | Pause markers (empty object) | permanent |
| `events/_stats.json` | Processing statistics | permanent |

**Why S3 instead of local disk?** Pods come and go (scale to zero). Local disk state is lost on pod termination. S3 is the shared persistence layer across all workers. The triggers pod writes pause state to S3; Gemini pods read it to check if Ollama is paused.

**Why 14-day TTL?** Frame extraction is the most compute-intensive step. Keeping frames for 14 days means reprocessing an event is cheap (skip ffmpeg). After 14 days, the event is either processed or forgotten.

**Why SeaweedFS?** Self-hosted on the k3s cluster (running as a workload, ArgoCD-managed). No cloud egress costs. Latency is sub-millisecond for `10.42.x.x` pod network.

---

## Model rotation — why multiple models

The `select_model_activity` reads from `provider.json` (generated by Nix from `frigate-genai-config.nix`):

```json
{
  "models": {
    "gemini-2.5-pro": {"weight": 0.7, "temperature": 0.3},
    "gemini-2.0-flash": {"weight": 0.2, "temperature": 0.3},
    "gemma3:27b": {"weight": 0.1, "temperature": 0.3}
  },
  "ollama": ["gemma3:27b"]
}
```

**Why weighted rotation?** Gemini 2.5-pro is expensive but accurate. 2.0-flash is cheap but less detailed. Weights route 70% of events to the expensive model, 20% to the cheap model, and 10% to local Ollama. This balances cost vs quality without hard-coding which model handles which label.

**Why temperature 0.3?** Object descriptions need consistency, not creativity. A dog should always be described as "a brown dog" not "a majestic canine contemplatively crossing the driveway." Low temperature reduces hallucinated details.

**Why Nix-generated config?** The config is a Nix derivation. Adding a model is a one-line code change; the JSON is rebuilt and baked into the image. No manual config management.

---

## Node topology

4-node k3s cluster (Kubernetes on NixOS):

| Node | Role | Architecture |
|---|---|---|
| `arch` | Control plane + worker | amd64 (Intel i9-9900K) |
| `closet` | Worker | amd64 (Intel i5-12400) |
| `office` | Worker | amd64 (Intel i7-8700K) |
| `nas` | Worker + storage | amd64 (Intel) |

**Pod distribution** (v51, confirmed 2026-07-08):
- **litellm**: 2 replicas on `closet` + `arch` (HA)
- **gemini**: 4 replicas across all 4 nodes (topology spread)
- **triggers**: 1 replica on `office`
- **ffmpeg**: 1 replica on `arch`
- **ollama**: 0 replicas (idle, KEDA scale-to-zero)

---

## Health checks

```bash
# WorkerDeployment status (should show vXX in CURRENT column)
kubectl get workerdeployment -o wide

# Versioned Deployments (should show vXX pods at 1/1)
kubectl get deploy -l 'temporal.io/deployment-name'

# KEDA (all should be Ready=True)
kubectl get scaledobject

# ArgoCD apps
kubectl get applications -n argocd frigate-genai
kubectl get applications -n argocd temporal-worker-controller

# Temporal UI
open https://temporal.ts.2143.me

# API stats
curl -sk https://cameras.ts.2143.me/api/stats

# Recent workflow completions
kubectl logs -n default deploy/frigate-genai-triggers-v51 --tail=100 | grep 'duration='
```

---

## Deploy changes

```bash
# Push to dotfiles master. CI auto-builds and deploys.
cd repos/dotfiles
git add -A && git commit -m "fix(genai): fix tool_get_snapshot_activity image handling" && git push

# Watch CI:
gh run watch --repo John2143/dotfiles

# After CI completes:
# 1. update-argo job commits new tag to argo main
# 2. ArgoCD syncs within 3 min
# 3. Temporal Worker Controller creates versioned pods
# 4. Progressive rollout (gemini only): 10% → 5 min → 50% → 5 min → 100%
# 5. Old pods drain (scaledown 30 min) then delete (2 hr)

# Verify rollout:
kubectl get workerdeployment -o wide   # TARGET should show new version
kubectl get deploy -l 'temporal.io/deployment-name'  # new versioned pods
```

---

## Rollback

### Tier A — bad build ID (worker uses wrong image)

The new version is live but processing events incorrectly. Revert the CI bump commit in argo:

```bash
cd repos/argo
git revert <ci-bump-commit>   # e.g., "frigate-genai: bump images to v52"
git push origin main
```

ArgoCD syncs the old `unsafeCustomBuildID` back. The controller drains the bad version pods and creates the old version. In-flight workflows continue on the bad version until they complete — no data loss, just one bad description per affected event.

### Tier B — complete reversion to old Deployment model

```bash
# 1. Revert WorkerDeployment changes in dotfiles
cd repos/dotfiles
git revert d97da56
git push origin master

# 2. Revert WorkerDeployment changes in argo
cd repos/argo
git revert 75e4bdf
git push origin main

# 3. Remove controller
helm uninstall temporal-worker-controller -n temporal-system
helm uninstall temporal-worker-controller-crds -n temporal-system

# 4. ArgoCD syncs old Deployment/ScaledObject YAMLs back from git history
```

---

## Common failure modes

### WorkerDeployment CURRENT column empty

The controller hasn't promoted a version yet. Check:
- `kubectl get workerdeployment -o yaml | grep -A5 status` — any conditions?
- `kubectl logs -n temporal-system deploy/temporal-worker-controller` — controller errors?
- Usually resolves within 2-3 minutes as versioned Deployments become ready.

### Workers scale but workflows fail with 502

LiteLLM proxy transient outage. The retry policy (20 attempts, 19 min window) handles most. If persistent:
- Check LiteLLM pods: `kubectl get pods -l app=litellm`
- Check LiteLLM logs: `kubectl logs -l app=litellm --tail=50 | grep -i error`
- Verify API keys in `frigate-genai-worker-creds` secret

### Activity timeouts (heartbeat)

LLM response > 300s. The genai activity has `start_to_close_timeout=300s` (5 min) and sends heartbeats every 15s with ±20% jitter. If a model takes >5 min to respond:
- Check which model is being used (Gemini 2.5-pro with complex tool chains can approach this)
- Increase `start_to_close_timeout` in the workflow if needed

### KEDA ScaledObjects READY: False

Missing CRD or KEDA operator down. Check:
- `kubectl get pods -n keda` — operator running?
- `kubectl get crd | grep keda` — CRDs present?
- Apply missing CRDs via server-side apply, restart operator

### Snapshots returning errors (pre-v51)

**Fixed in v51.** The `tool_get_snapshot_activity` used `Image.open(img_path)` but `img_path` was already a file descriptor string — the second `open()` was a missing step. Now `Image.open(img_path)` is present and confirmed in deployment.

### Crop tool instant-failing with "Invalid crop region"

**Expected behavior.** The Gemini model chose a zero-area crop region `(1.0,1.0)-(1.0,1.0)`. The activity raises `ApplicationError(non_retryable=True)` — instant fail, no retries. The workflow either recovers (model tries a different tool) or fails fast. This is the differentiated retry policy working as designed.

---

## External dependencies

| Service | Endpoint | Purpose | Fallback |
|---|---|---|---|
| Gemini API | via `llm.2143.me` | Vision LLM | Ollama (weighted rotation) |
| Ollama | via `llm.2143.me` | Local vision LLM | Gemini |
| Frigate NVR MQTT | `mosquitto:1883` | Event ingestion | MQTT QoS 1 (broker queues events) |
| Frigate NVR API | `arch.ts.2143.me:5000` | HLS frame extraction, sub_label update | None — critical path |
| SeaweedFS S3 | `seaweedfs-filer:8333` | Frame/artifact storage | None — critical path |
| Temporal Server | `temporal-frontend:7233` | Workflow orchestration | None — critical path |
| LiteLLM | `llm.2143.me` | LLM API proxy | None — critical path |

---

## Design decisions — why not X

- **Why not Kafka/MQTT as the workflow engine?** Temporal gives durability guarantees (workflows survive pod crashes, server restarts, and network partitions) and built-in retry/backoff. MQTT with QoS 1 only guarantees delivery to the broker, not to the worker.

- **Why not direct Deployment + kubectl rollout restart?** WorkerDeployments provide Pinned versioning — in-flight workflows NEVER run on a new version mid-execution. Traditional rollouts kill running pods and restart on the new image, which can corrupt in-progress LLM calls.

- **Why not a single task queue for everything?** FFmpeg, Gemini, and misc activities have different CPU profiles, scaling needs, and failure modes. Isolating them on separate queues means a ffmpeg backlog doesn't block LLM turns, and vice versa.

- **Why not HPA on CPU/Memory?** LLM API calls are I/O-bound (waiting for HTTP responses). A pod handling 5 concurrent turns uses ~100m CPU. Queue depth is the only signal that reflects actual backlog.

- **Why Nix for the Docker image?** Reproducible closures. No `pip install temporalio==1.2.3` that drifts between CI and production. The exact same Python environment (including transitive C extensions like Pillow) is tested as deployed.

- **Why two repos (dotfiles + argo)?** Code vs infrastructure state. The image tag (`v51`, `v52`) is infrastructure state — it changes every deploy. Keeping it in the argo repo means rollback is a single `git revert` in argo, not a code revert in dotfiles. CI writes to argo; humans write to dotfiles.

- **Why Progressive rollout only for Gemini?** Gemini is the highest-risk path — it costs API credits and produces user-visible descriptions. FFmpeg is deterministic (frame extraction either works or doesn't). Ollama is a single-replica fallback. Triggers is single-replica always-on.

- **Why mean-centered pixel diff for keyframes?** Spatially aware (motion registers proportionally to area moved), per-frame mean-centering cancels global lighting shifts, GaussianBlur suppresses sensor noise, and the data_box weights the detection region at 0.7. Global histogram methods were rejected: spatially blind and hypersensitive to lighting. The precomputed keyframe result is injected as a `role="user"` message (no fake tool-call ID needed), while LLM-invoked calls use normal `role="tool"` messages.

---

## Updating this document

This file lives in `dotfiles/docs/frigate-genai.md`. Update it when:
- A new task queue is added
- The retry policy changes
- A new worker mode is introduced
- The deployment pipeline changes (CI workflow, rollout strategy)
- A new external dependency is added
