# Frigate GenAI — Architecture & Operations

## What it is

Frigate detects objects; this system describes what actually happened. A
dispatcher batches new camera events while nobody is at the workstation, groups
repeats into scenes, and describes each scene with **one local vision-model
call** on the office GPU. Everything runs on-premises: no cloud LLM, no spend.

## Architecture

```
Frigate ──MQTT──> mqtt-listener  (redo triggers only)
   │
   └─/api/events──> dispatcher ──300 s──> DrainWorkflow (genai-tasks)
                        │                     │
                        │ seat gate (Mimir)   ├─ collect: classify, merge, dedupe
                        │                     ├─ label skips: "Skipped: <reason>"
                        │                     └─ start GenAIWorkflow per scene
                        │                            │
                  office GPU host                    ├─ ffmpeg frames (genai-tasks-ffmpeg)
                  (Hyprland idle + VRAM)             ├─ pick_keyframes + crop_detection
                                                     ├─ describe_scene (genai-tasks-ollama)
                                                     └─ record result, write description
```

## Components

| Component | Mode | Replicas | Role |
|---|---|---|---|
| triggers | `--mode=triggers` | 1 | Runs `GenAIWorkflow`; owns `genai-tasks` activities |
| ollama worker | `--mode=genai-ollama` | 0–1 (KEDA) | Runs `describe_scene`, `pick_keyframes`, `crop_detection` on `genai-tasks-ollama` |
| dispatcher | `--mode=dispatcher` | 1 | Runs `DrainWorkflow` + intake; starts a drain every 300 s |
| ffmpeg | `--mode=ffmpeg` | 1 | `transcode_into_parts` on `genai-tasks-ffmpeg` |
| mqtt-listener | `--mode=mqtt-listener` | 1 | Rewrites an event description to `redo` and it is re-described |
| dashboard | `--mode=dashboard` | 1 | Event table, pause toggles, reprocess; mutating endpoints need `GENAI_ADMIN_TOKEN` |

## Intake rules (`frigate_genai/intake.py`)

Pure functions, thresholds at module level.

**Skip** (labelled `Skipped: <reason>`, never described):
- audio labels (`speech`, `bark`, `yell`);
- a vehicle outside every household zone (cam02's `in_court` is the road);
- on cam01/cam06, a person or dog outside our zones for under 30 s;
- a must-keep label under 3 s **and** `top_score < 0.80`, except package and cam05;
- a low-priority label under 5 s or with `top_score < 0.75`.

**Keep**: must-keep labels (person, package, carriers, cat, dog, wildlife) are
described first; everything else (vehicles, face, umbrella, …) after.

Events on one camera merge into a **scene** when the next starts within 120 s of
the previous end and the scene spans at most 600 s. A scene that shows the same
thing in the same box as the last *described* scene (IoU ≥ 0.5, within 30 min,
no person or package involved) is dropped as a repeat.

Measured intake: ~234 scenes/day, 162 must-keep, worst day 294.

## The per-scene workflow (`GenAIWorkflow`)

1. Model from the drain (12b by default, 26b when the card is free).
2. Snapshot + ffmpeg frames in parallel (`skip_frames` for retries).
3. `pick_keyframes` — pixel-difference selection, max 8 frames.
4. `crop_detection` — the detector box from `/api/events/<id>`, cropped from the
   sharpest keyframe at quality 95; falls back to the centre 60% of the frame.
5. `describe_scene` — one call, `temperature=0`, `max_tokens=500`,
   `response_format=json_schema` (scene / subjects / action / confidence /
   needs_review). Two malformed replies degrade to `confidence=low,
   needs_review=true`; they never raise.
6. `record_result` → `_state/results/<scene_id>.json`, **before** the Frigate
   write, then the description (retry 24×, 30 s → 30 min).
7. Weak must-keep results queue one retry on the 26b model (`retry_of` set, no
   second retry).
8. Frames and crop are deleted from S3.

## Model and provider config

Baked into both images at `/var/lib/frigate-genai-sidecar/provider.json`
(`nixos/modules/frigate-genai-config.nix`): models `ollama/gemma4:12b` and
`ollama/gemma4:26b`, `ollama_base_url = http://office.ts.2143.me:11434/v1`.
Inference goes straight to the host — LiteLLM is not in the path. The
`frigate-genai` LiteLLM key is a tripwire (allow-list + $1/day budget): any
traffic on it is a bug and alerts.

Prompt templates live beside it in `prompts.json` (per-camera note, per-label
hints). A prompt or model change is a rebuild + CI tag bump, not a config edit.

## Seat gate

Batch inference only runs while the workstation is idle. The office host runs a
60 s user timer (`frigate-genai-seated.nix`) sampling Hyprland IPC and writing
`/var/lib/node_exporter/textfile/frigate_genai_gate.prom`:

| Metric | Meaning |
|---|---|
| `frigate_genai_gate_open` | 1 when the seat has been idle 180 s |
| `frigate_genai_free_vram_mb` | free VRAM on the GPU |
| `frigate_genai_loaded_models` | models resident in Ollama |
| `frigate_genai_gate_idle_seconds` | current idle streak |

The dispatcher reads them from Mimir and fails **closed**: missing series,
stale file (> 300 s), `free_vram_mb < 12000` or more than one resident model all
mean "no work". A 26b call additionally needs ≥ 21500 MiB free.
Manual override: `~/.local/state/frigate-genai/seated` containing `1` or `0`,
honoured for 30 minutes.

## Pause

`PUT`-style flags in S3, checked by the dispatcher and the MQTT listener:

```bash
# pause everything (crash-safe: the flag is the signal)
aws --endpoint-url "$S3_ENDPOINT" s3 cp /dev/null s3://frigate-genai/_state/paused/genai
# resume
aws --endpoint-url "$S3_ENDPOINT" s3 rm s3://frigate-genai/_state/paused/genai
```

`_state/paused/ollama` keeps the 12b model in use and never touches the 26b.
The dashboard toggles the same flags.

## State in SeaweedFS (`frigate-genai` bucket)

| Path | Purpose | TTL |
|---|---|---|
| `events/<id>/frames/`, `snapshot.jpg`, `crop.jpg` | working artifacts, deleted when the workflow ends | 14d rule |
| `_state/results/<scene_id>.json` | durable per-scene result: model, tokens, confidence, description | permanent |
| `_state/done.json` | ids already handled; pruned to 8 days | permanent |
| `_state/watermark.json` | last event `end_time` collected | permanent |
| `_state/spend/<date>.json` | scenes, skips, retries, GPU seconds, `cloud_calls` | permanent |
| `_state/paused/*` | pause flags | permanent |
| `_state/stats.json` | dashboard counters | permanent |

## Deployment pipeline

```
git push (dotfiles master)
  → CI build-frigate-genai.yml: nix build → attic → ghcr (v<run>, latest)
    → update-argo: rewrite image tags + smoke-test every mode, commit to argo main
  → ArgoCD syncs frigate-genai within 3 min (Recreate strategy)
```

Smoke-tested modes: `triggers dispatcher mqtt-listener dashboard`. Adding a mode
without adding it there ships untested.

Rollback: `git revert` the argo tag bump within the 1 h sunset `deleteDelay`;
after that the previous build id is gone and the revert must also revert the
`dotfiles` commit and let CI rebuild.

## Health checks

```bash
kubectl -n default get workerdeployments.temporal.io
kubectl -n default logs deploy/frigate-genai-dispatcher --tail=50   # drain start/lines
kubectl -n default logs deploy/frigate-genai-ollama --tail=50       # describe lines
curl -s localhost:8080/api/stats                                    # dashboard pod
curl -s 'http://mimir:8080/prometheus/api/v1/query?query=frigate_genai_gate_open'
```

A healthy drain logs `collect_scenes: N events`, `drain: N scenes, M skips`, then
`Describe <scene>: model=… conf=…`, and the newest
`_state/spend/<date>.json` has `cloud_calls: 0`.

## Verifying a change

```bash
cd nixos/modules && python3 -m unittest discover -s frigate_genai/tests -t . -v
```

Quality regression set (24 real events, files under `scratch/LocalBenchDetectorAreas/`):
**≥ 17/24 correct presence, ≤ 8 outputs with a clear invention, 100% schema-valid,
≤ 3.5 s/event**. Baseline for the single-call path: 19/24, 5–6 inventions, 2.82 s.

## Known follow-ups

- Frigate 0.18 map+roles config migration: the legacy mask polygons must be
  converted before `version: "0.18-0"` can be set; every `genai` block stays
  disabled until then.
- Dog-only pet classifier (Luna): 73% of dog crops are ≥ 100×100 px; cat crops
  are not (28%), so cat identity stays `not_determinable`.
