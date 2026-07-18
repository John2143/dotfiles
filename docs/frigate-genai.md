# Frigate GenAI — Architecture & Operations

## What it is

Frigate GenAI watches Frigate NVR's MQTT event stream, starts a Temporal workflow for each detection event, and uses a vision-capable LLM (Gemini or Ollama) to describe what happened in natural language. Every event goes through: frame extraction → multi-turn LLM analysis with tool use → description written back to Frigate's sub_label. The system runs on a home k3s cluster and deploys as standard Kubernetes Deployments with Recreate strategy.

---

## Architecture diagram

```
Frgate NVR ──MQTT──> triggers pod (Temporal workflow starter)
    │                    │
    │              Temporal Server
    │                    │ (SPIRE X.509 mTLS)
    │             genai-tasks  ffmpeg-tasks  gemini-tasks  ollama-tasks
    │             (misc acts)  (transcoding) (vision LLM)  (local LLM)
    │         │            │            │             │
    │     triggers      ffmpeg       gemini        ollama
    │     pod           pod          pods          pod
    │     (fixed 1)    (fixed 1)    (fixed 1)     (fixed 1)
    │
    │              LiteLLM Proxy (2 replicas, HA)
    │              /         \
    │         Gemini API    Ollama (local)
    │
    └── sub_label written back to Frigate API
```

---

## Component roles

### 1. Triggers pod (always running, fixed 1 replica)

**Mode:** `--mode=triggers`
**Task queue:** `genai-tasks` (misc activities only)
**Deployment:** `frigate-genai-triggers`
**Rollout strategy:** `Recreate`

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

**Resources:** 100m CPU request, 128Mi memory — it's mostly sleeping waiting for MQTT.

### 2. FFmpeg pod (fixed 1 replica)

**Mode:** `--mode=ffmpeg`
**Task queue:** `genai-tasks-ffmpeg`
**Deployment:** `frigate-genai-ffmpeg`
**Rollout strategy:** `Recreate`

The ffmpeg pod extracts frames from Frigate's HLS recordings. It:

1. **Pulls `.m3u8` HLS streams** from Frigate's `/vod/<camera>/start/<ts>/end/<ts>/index.m3u8` endpoint
2. **Decimates to FPS** (default 1 fps for initial scan; up to source FPS for detail passes)
3. **Returns JPEG byte arrays** to the workflow as a list
4. **Runs two activities:** `transcode_into_parts_activity` (batch extraction for timeline) and `tool_transcode_activity` (single-frame extraction for detailed tool inspection)

**Why its own task queue?** Isolates CPU-intensive work from LLM work. A Gemini turn shouldn't be delayed by frame extraction backlog, and vice versa.

**Why Recreate rollout?** Single-activity no-state worker — no progressive ramp needed. A new version either extracts frames or it doesn't.

**Max concurrent:** 2 (controlled by `TEMPORAL_MAX_FFMPEG` env). Each ffmpeg process uses one CPU core. Pod spec limits to 1000m CPU.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.

### 3. Gemini pod (fixed 1 replica)

**Mode:** `--mode=genai-gemini`
**Task queues:** `genai-tasks` (misc) + `genai-tasks-gemini` (LLM turns)
**Deployment:** `frigate-genai-gemini`
**Rollout strategy:** `Recreate`

The gemini pod is the **heavy lifter**. It:

1. **Listens on `genai-tasks-gemini`** for LLM turn activities (run_genai_turn, tool_find_keyframes, tool_frame_diff, tool_tag_image, tool_get_snapshot, tool_show_frame, tool_crop, tool_compact, tool_set_description, apply_tool_messages, summarize_agent, save_agent_log).

2. **Also listens on `genai-tasks`** for misc activities (model selection, snapshot fetch, cleanup, upscale) — same as triggers pod, providing redundancy.

3. **Calls the Gemini API** through the LiteLLM proxy at `https://llm.2143.me/v1/chat/completions`.

4. **Has 5 concurrent activity slots** per pod, controlled by `TEMPORAL_MAX_GEMINI_GENAI`.

**Why topologySpread?** 4 physical nodes. The topology spread constraint (`maxSkew: 1`, `ScheduleAnyway`) spreads Gemini pods across nodes for fault tolerance. If one node goes down, other nodes still serve LLM turns.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.

### 4. Ollama pod (fixed 1 replica)

**Mode:** `--mode=genai-ollama`
**Task queues:** `genai-tasks` (misc) + `genai-tasks-ollama` (LLM turns)
**Deployment:** `frigate-genai-ollama`
**Rollout strategy:** `Recreate`

Identical to Gemini pod but calls the **local Ollama API** through LiteLLM. Single replica because the local model can't handle more than one concurrent request.

**Why Ollama?** Optional fallback. The model selector (`select_model_activity`) can route events to Ollama based on weighting. When the user doesn't want to spend API credits on low-confidence events, Ollama handles them for free. Globally pausable via the HTTP API.

**Max concurrent:** 1 (controlled by `TEMPORAL_MAX_OLLAMA_GENAI`). Ollama on a single GPU can only handle one request at a time.

**Resources:** 250m CPU request, 512Mi memory, 1000m CPU limit, 2Gi memory limit.
---

## Task queues — the routing layer

Temporal separates **where work runs** (task queues) from **what work is** (activities/workflows).

| Task Queue | Purpose | Listeners | Replicas |
|---|---|---|---|
| `genai-tasks` | Misc activities + workflow listener | triggers, gemini, ollama | Fixed (1 each) |
| `genai-tasks-gemini` | LLM turns + tool execution | gemini only | Fixed (1) |
| `genai-tasks-ffmpeg` | Frame extraction | ffmpeg only | Fixed (1) |
| `genai-tasks-ollama` | LLM turns via Ollama | ollama only | Fixed (1) |

**Why separate queues?** Isolation. A ffmpeg backlog shouldn't block Gemini turns. Gemini rate-limiting shouldn't starve Ollama requests. Each workload is independently deployable via ArgoCD-managed Deployments.

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
       clone argo repo → update image tag in *-deployment.yaml
       → verify tags → git commit → git push (argo main)
  → ArgoCD (polls argo main every 3 min):
    → syncs frigate-genai app (Deployment image tags updated)
  → Kubernetes:
    → Recreate strategy: old pod terminates, new pod starts with new image
```

**Why standard Deployments instead of WorkerDeployments?** The WorkerDeployment system (Temporal-managed rainbow deploys with progressive rollout) added operational complexity without proportional benefit for this workload. Frigate GenAI workflows are short-lived (p50 ~82s). Standard Kubernetes Deployments with Recreate strategy provide clean cutover: old pod drains in-flight work, new pod picks up fresh workflows. No versioned pods, no controller, no progressive rollout — simpler GitOps with ArgoCD.

**Why CI pushes to two repos?** Separates code (dotfiles) from infrastructure state (argo). The dotfiles repo owns the Python code, CI workflow, and Nix build. The argo repo owns the Kubernetes manifests — including the image tags generated by CI. Rollback is a single `git revert` in the argo repo.

**Why Nix-built images?** The Docker image is a Nix closure — every dependency (Python, PIL, boto3, temporalio, paho-mqtt) is pinned by hash. No `apt-get install` or `pip install` at build time; no dependency drift between CI and production.

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

## Scaling (formerly KEDA)

**KEDA was removed in July 2026 cutover.** The system now uses fixed `replicas: 1` across all components:

| Worker | Replicas | Notes |
|---|---|---|
| triggers | 1 | Always-on (MQTT subscriber) |
| ffmpeg | 1 | Single-threaded CPU work |
| gemini | 1 | One pod handles all LLM turns |
| ollama | 1 | Single-GPU local model |

**Why fixed replicas instead of KEDA event-driven scaling?** The workload pattern is low-volume (dozens of events/day, not thousands). KEDA's scale-to-zero introduced cold-start latency (pod startup + LLM warmup) that wasn't justified by cost savings on a home cluster. Fixed replicas simplify operations and eliminate KEDA CRDs, ScaledObjects, and the Temporal Worker Controller from the deployment surface.

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


## Network & Authentication — SPIRE X.509 mTLS

Frigate GenAI workers authenticate to Temporal via **SPIRE X.509 mTLS** — no API keys, no PocketID tokens.

**Connection chain:**
1. SPIRE Agent (CSI driver) provisions X.509 SVIDs to each worker pod via Unix socket (`/spiffe-workload-api/spire-agent.sock`)
2. Worker calls `spire-agent api fetch x509` before connecting, writing cert+key to a tmpfs
3. Worker connects to Temporal gRPC at `temporal-grpc.john2143.com:7233` with:
   - Client certificate (SPIRE-issued X.509 SVID)
   - Server CA verification (`TEMPORAL_TLS_CA_PATH` → `/etc/temporal-certs/ca.crt`)
   - TLS server name: `temporal-grpc.john2143.com`
4. Temporal frontend verifies client cert against the SPIRE trust bundle (`requireClientAuth: true`)

**Trust domain:** `kube.john2143.com` (root SPIRE server at home cluster). All worker SVIDs are under this domain — no cross-cluster federation needed for same-cluster workers.

**Env vars (all workers):**
- `TEMPORAL_TLS=true`
- `SPIFFE_ENDPOINT_SOCKET=unix:///spiffe-workload-api/spire-agent.sock`
- `TEMPORAL_TLS_CA_PATH=/etc/temporal-certs/ca.crt`
- `TEMPORAL_ADDRESS=temporal-grpc.john2143.com:7233`
- `TEMPORAL_TLS_SERVER_NAME=temporal-grpc.john2143.com`

**No PocketID needed:** Same-cluster workers use mTLS only. The `POCKETID_TEMPORAL_CLIENT_ID` env var is optional — needed only for cross-cluster clients (e.g., remote john2143-com web app). When absent, workers connect with SPIRE mTLS exclusively.
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

**Pod distribution** (July 2026, post-WorkerDeployment cutover):
- **litellm**: 2 replicas on `closet` + `arch` (HA)
- **gemini**: 1 replica (topology spread preference)
- **triggers**: 1 replica (any node)
- **ffmpeg**: 1 replica (any node)
- **ollama**: 1 replica (GPU node preference)
---

## Health checks

```bash
# Deployment status (all should be 1/1 Ready)
kubectl get deploy -l 'app.kubernetes.io/part-of=frigate-genai'

# ArgoCD apps
kubectl get applications -n argocd frigate-genai

# Temporal UI
open https://temporal.ts.2143.me

# API stats
curl -sk https://cameras.ts.2143.me/api/stats

# Recent workflow completions
kubectl logs -n default deploy/frigate-genai-triggers --tail=100 | grep 'duration='
```

## Deploy changes

```bash
# Push to dotfiles master. CI auto-builds and deploys.
cd repos/dotfiles
git add -A && git commit -m "fix(genai): fix tool_get_snapshot_activity image handling" && git push

# Watch CI:
gh run watch --repo John2143/dotfiles

# After CI completes:
# 1. update-argo job commits new image tag to argo main
# 2. ArgoCD syncs within 3 min
# 3. Kubernetes Recreate strategy: old pod terminates, new pod starts

# Verify rollout:
kubectl get deploy frigate-genai-gemini -o wide   # should show new image tag
kubectl rollout status deploy/frigate-genai-gemini
```
---

## Rollback

Revert the CI bump commit in argo:

```bash
cd repos/argo
git revert <ci-bump-commit>   # e.g., "frigate-genai: bump images to vXX"
git push origin main
```

ArgoCD syncs the old image tag back. Kubernetes Recreate strategy terminates the bad pod and starts a new one with the old image. In-flight workflows may fail on pod termination — Temporal retries pick them up on the old version.

---

## Common failure modes

### Workers scale but workflows fail with 502

LiteLLM proxy transient outage. The retry policy (20 attempts, 19 min window) handles most. If persistent:
- Check LiteLLM pods: `kubectl get pods -l app=litellm`
- Check LiteLLM logs: `kubectl logs -l app=litellm --tail=50 | grep -i error`
- Verify API keys in `frigate-genai-worker-creds` secret

### Activity timeouts (heartbeat)

LLM response > 300s. The genai activity has `start_to_close_timeout=300s` (5 min) and sends heartbeats every 15s with +/-20% jitter. If a model takes >5 min to respond:
- Check which model is being used (Gemini 2.5-pro with complex tool chains can approach this)
- Increase `start_to_close_timeout` in the workflow if needed

### Snapshots returning errors (pre-v51)

**Fixed in v51.** The `tool_get_snapshot_activity` used `Image.open(img_path)` but `img_path` was already a file descriptor string — the second `open()` was a missing step. Now `Image.open(img_path)` is present and confirmed in deployment.

### Crop tool instant-failing with "Invalid crop region"

**Expected behavior.** The Gemini model chose a zero-area crop region `(1.0,1.0)-(1.0,1.0)`. The activity raises `ApplicationError(non_retryable=True)` — instant fail, no retries. The workflow either recovers (model tries a different tool) or fails fast. This is the differentiated retry policy working as designed.

---

## Performance baseline (2026-07-12)

Baseline from 2,000 GenAIWorkflow executions (July 10-12, 2026). Source: `analyze_jobs.py` against Temporal history API.

### Overall health

| Metric | Value |
|---|---|
| Total root workflows | 2,000 |
| Completed | 920 (46.0%) |
| Failed | 828 (41.4%) |
| Terminated | 252 (12.6%) |

**The 41.4% failure rate is not a code defect.** 92.1% of all failures are two infrastructure issues:

| Root cause | Count | % of failures | Explanation |
|---|---|---|---|
| Ollama unavailable | 970 | 48.0% | `litellm` returning "no available server" — Ollama instance was down |
| Gemini rate limit (429) | 890 | 44.1% | "prepayment credits depleted" / "exceeded current quota" |
| Terminated (deployment rollover) | 111 | 5.5% | Workflows killed by deployment rollover |
| Activity timeouts | 20 | 1.0% | StartToClose or Heartbeat timeouts |
| Everything else combined | 28 | 1.4% | Server errors, Frigate API, auth, genuine app errors |

When Ollama is running and Gemini credits are available, expected failure rate drops to low single digits.

### Duration (completed workflows only)

| Percentile | Duration |
|---|---|
| p50 | 82 seconds |
| p90 | 312 seconds (5.2 min) |
| p95 | 378 seconds (6.3 min) |
| p99 | 3,282 seconds (54.7 min) |
| max | 10,685 seconds (178.1 min) |

61% of completions have exactly 42-47 state transitions (14-16 agent turns). The long tail (>30 min, 13 workflows) all have 47-56 transitions — the agent gets stuck looping or the LLM API is slow, not more turns.

### Duration by model (completed, p50)

| Model | n | p50 | Has tool failures | Why |
|---|---|---|---|---|
| `gemini-2.5-flash-lite` | 388 | **54s** | 12.4% | Fastest; more tool failures but recovers quickly |
| `gemini-2.5-pro` | 416 | 100s | 11.8% | Baseline; balanced |
| `gemini-2.5-flash` | 116 | **310s** | 1.7% | 6x slower than flash-lite despite fewest tool failures — likely higher per-token latency or different prompt routing |

**`gemini-2.5-flash` is an outlier.** Verify whether its accuracy justifies the 6x wall-time cost over flash-lite. Only 116 workflows use it — it may be an older model version still in rotation.

### Confidence by label

| Label | n | High | Low | Nothing found |
|---|---|---|---|---|
| person | 231 | **65%** | 25% | 2% |
| dog | 39 | 49% | 28% | 3% |
| package | 8 | 62% | 25% | 0% |
| car | 636 | **10%** | 45% | 27% |

**Cars are the hardest label.** Only 10% high confidence. 27% of car analyses find nothing actionable — the agent can't determine what's noteworthy about the vehicle (arriving? departing? whose?). Binary presence labels (person, package) score much higher than interpretive labels (car).

### Confidence by camera

| Camera | n | High | Low | Nothing found | Likely location |
|---|---|---|---|---|---|
| cam03 | 135 | **60%** | 27% | 4% | Indoor |
| cam04 | 74 | **59%** | 27% | 4% | Indoor |
| cam02 | 78 | 37% | 38% | 1% | Mixed |
| cam01 | 350 | 15% | 44% | 18% | Driveway (outdoor) |
| cam06 | 283 | 11% | 42% | **36%** | Street (outdoor) |

Outdoor cameras produce dramatically lower confidence. cam06 (street) has 36% "nothing found" — the agent frequently can't determine anything actionable from wide-angle public street footage. Indoor cameras (cam03, cam04) achieve ~60% high confidence.

### Build versions

| Build | Workflows | Completed | Failed | Failure rate |
|---|---|---|---|---|
| v74 | 1,507 | 920 | 367 | 24.4% |
| v75 | 492 | 0 | 460 | 93.5% |
| v76 | 1 | 0 | 1 | 100% |

**v75's 93.5% failure rate is infrastructure, not a regression.** v75 deployed during the Ollama outage + Gemini quota exhaustion period. All v75 failures are the same Ollama-unavailable + rate-limit root causes as v74. Zero completed v75 workflows means v75 was never tested under normal conditions — it was immediately rolled back or superseded. v76 has 1 workflow (too few to assess).

### Other observations

- **Cost tracking is not wired up.** The `Cost` search attribute exists in `config.py` but no workflow upserts it. All 920 completions show empty cost.
- **97% of completions skip transcode** (single-snapshot or `skip_frames=True`). Only 26 workflows used full HLS frame extraction. Transcode is rarely needed for successful analysis.
- **99 workflows (10.8%) completed with tool failures.** The agent recovered from invalid crops, frame source errors, etc. and still produced a result. These take ~50% longer (p50=116s vs 78s).
- **Average agent turns: 14-16** (42-48 state transitions ÷ 3 transitions per turn). Highly consistent — the agent converges in a tight band when things work.

### Updating this baseline

```bash
cd repos/dotfiles
python nixos/modules/frigate_genai/analyze_jobs.py --limit 2000 --output-dir ./tmep/ --cache-dir ./tmep/temporal_cache/
```

Re-run after significant changes (new model added, prompt overhaul, retry policy change) and replace the numbers above.

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

- **Why Recreate strategy instead of RollingUpdate?** The workers are single-replica and stateful (in-flight LLM calls). RollingUpdate would start a new pod before the old one terminates, causing two workers on the same task queue. Recreate ensures clean handoff: old pod drains, new pod picks up.

- **Why not a single task queue for everything?** FFmpeg, Gemini, and misc activities have different CPU profiles and failure modes. Isolating them on separate queues means a ffmpeg backlog doesn't block LLM turns, and vice versa.

- **Why not HPA on CPU/Memory?** LLM API calls are I/O-bound (waiting for HTTP responses). A pod handling 5 concurrent turns uses ~100m CPU. Fixed replicas keep it simple for a low-volume home workload.

- **Why Nix for the Docker image?** Reproducible closures. No `pip install temporalio==1.2.3` that drifts between CI and production. The exact same Python environment (including transitive C extensions like Pillow) is tested as deployed.

- **Why two repos (dotfiles + argo)?** Code vs infrastructure state. The image tag (`v51`, `v52`) is infrastructure state — it changes every deploy. Keeping it in the argo repo means rollback is a single `git revert` in argo, not a code revert in dotfiles. CI writes to argo; humans write to dotfiles.

- **Why not WorkerDeployments?** The WorkerDeployment system (Temporal-managed progressive rollout with versioned pods and the worker controller) was replaced in July 2026. Frigate GenAI workflows are short-lived (p50 ~82s). Standard Kubernetes Deployments with Recreate strategy provide simpler GitOps with fewer moving parts.

- **Why mean-centered pixel diff for keyframes?** Spatially aware (motion registers proportionally to area moved), per-frame mean-centering cancels global lighting shifts, GaussianBlur suppresses sensor noise, and the data_box weights the detection region at 0.7. Global histogram methods were rejected: spatially blind and hypersensitive to lighting. The precomputed keyframe result is injected as a `role="user"` message (no fake tool-call ID needed), while LLM-invoked calls use normal `role="tool"` messages.

---

## Updating this document

This file lives in `dotfiles/docs/frigate-genai.md`. Update it when:
- A new task queue is added
- The retry policy changes
- A new worker mode is introduced
- The deployment pipeline changes (CI workflow, rollout strategy)
- A new external dependency is added
