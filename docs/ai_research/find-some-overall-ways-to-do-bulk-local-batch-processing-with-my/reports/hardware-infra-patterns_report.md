# Hardware and Infrastructure Patterns for Overnight GPU Batch Processing on Consumer AMD GPUs

## 1. Summary

Consumer AMD GPUs running ROCm present a distinct set of challenges for overnight batch inference that differ materially from the NVIDIA-centric advice dominating most online resources. The RX 7900 XT (24 GB VRAM, RDNA3/gfx1100) is fully capable of running 27B-class models like qwen3.6:27b for multi-hour stretches, but success hinges on proactively managing three categories of AMD-specific risk: (1) **VRAM fragmentation and driver-level memory leaks** triggered by repeated model loading/unloading cycles, (2) **MES firmware hangs** that can silently wedge the GPU into a 100%-utilization, low-power-draw state requiring a driver-level reset, and (3) **thermal and power management** that demands active monitoring rather than set-and-forget defaults.

The most robust pattern for overnight AMD batch processing is **model-pinning** — loading the target model once at batch start, processing all queued prompts sequentially through the same loaded instance, then unloading at completion. This avoids the primary trigger for ROCm VRAM leaks (mid-run model switching) and eliminates the 6–8 minute model-loading penalty between jobs. The Ollama `keep_alive` mechanism supports this naturally: set `OLLAMA_KEEP_ALIVE=-1` for the batch window, then issue a `keep_alive=0` API call at shutdown. For VRAM-constrained scenarios requiring multiple models, `OLLAMA_MAX_LOADED_MODELS` can be set to 1 to force deterministic unload-before-load behavior, though this reintroduces the model-switching risk surface.

For recovery from GPU hangs, a layered watchdog strategy is recommended: (1) the Ollama `/api/ps` endpoint as a lightweight liveness probe every 60 seconds, (2) `rocm-smi` VRAM utilization checks to detect the "100% utilization, near-zero power" hang signature, and (3) `amdgpu_gpu_recover` debugfs access (`/sys/kernel/debug/dri/0/amdgpu_gpu_recover`) as a last-resort GPU reset before falling back to a service restart. The `amdgpu.cwsr_enable=0` kernel parameter is an essential stability prerequisite for RDNA3 GPUs on any ROCm version through 7.2.0. Systemd user timers with `Persistent=true`, `RuntimeMaxSec=8h`, and a properly configured `ExecStop` handler provide the scheduling backbone, while `logind` lingering (`loginctl enable-linger`) ensures timers fire outside active login sessions.

Multi-GPU orchestration across the office and arch machines should follow a **per-machine model specialization** pattern rather than distributed inference: each machine independently loads the model best suited to its VRAM budget, runs from a shared or replicated queue directory (via NFS, rsync, or a simple HTTP pull), and reports results back. This avoids the complexity of Ray/vLLM multi-node setups on heterogeneous consumer hardware where network bandwidth and GPU capability asymmetry make tensor/pipeline parallelism impractical.

## 2. Relation to Primary Question

These findings directly inform the architecture of an overnight batch queue: the hardware-level instability risks on AMD ROCm (VRAM leaks, MES hangs, memory fragmentation) **must be designed around**, not patched over — the queue processor must treat GPU health as a first-class concern with watchdog loops, reset procedures, and single-model-per-run pinning, rather than assuming the GPU will reliably survive an 8-hour unattended run.

## 3. Source Evaluation

### Primary / High-Weight Sources

**ROCm/ROCm Issue #5362 — "Ollama triggers some weird form of memory leak"** (GitHub, 2025-09-17, closed)
- URL: https://github.com/ROCm/ROCm/issues/5362
- **Credibility: High.** Primary source — an official AMD ROCm bug tracker. The issue was acknowledged by AMD staff (@ppanchad-amd) and an internal ticket was created. Multiple users (RX 7800 XT, RX 7900 XTX) reproduced the same VRAM leak behavior across different Fedora versions and Ollama versions. The bug report includes `rocminfo` output, `dmesg` logs, and docker-compose configs, making it well-documented.
- **Weight:** Defines a known failure mode that must be mitigated. The confirmed trigger is model switching + mid-generation cancellation. The workaround (avoid model switching, restart ollama between runs) is directly actionable.

**ROCm/ROCm Issue #5590 — "amdgpu compute wave store and resume causing MES firmware 0x80 hang"** (GitHub, 2025-10-28)
- URL: https://github.com/ROCm/ROCm/issues/5590
- **Credibility: High.** Primary AMD issue tracker. Confirmed by AMD engineers. The `amdgpu.cwsr_enable=0` workaround is explicitly documented and linked from multiple other ROCm issues (#5724, #5915) as a prerequisite for RDNA3 stability.
- **Weight:** Establishes the kernel parameter requirement for overnight runs on the user's RX 7900 XT.

**ROCm/ROCm Issue #5915 — "Host CPU memory leak with amdgpu-dkms driver during GPU compute workloads"** (GitHub, 2026-01-30)
- URL: https://github.com/ROCm/ROCm/issues/5915
- **Credibility: High.** Primary AMD bug tracker. Documents a ~70–90 GB/hour host memory leak in ROCm 7.1.x during multi-hour compute, reduced to ~5.4 GB/hr with ROCm 7.2.0 + cwsr_enable=0. Directly relevant to overnight batch runs.
- **Weight:** Informs minimum ROCm version requirements and host memory monitoring for multi-hour jobs.

**systemd.service(5) and systemd.timer(5) — Debian Manpages** (2026-03-23)
- URL: https://manpages.debian.org/testing/systemd/systemd.service.5.en.html, https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html
- **Credibility: High.** Official systemd documentation, maintained by the systemd project. Definitive reference for `RuntimeMaxSec`, `Persistent=`, `WakeSystem=`, `ExecStop`, and `TimeoutStopSec` semantics.
- **Weight:** Authoritative on timer/service behavior. The documented interaction between `RuntimeMaxSec` and `EXTEND_TIMEOUT_USEC=` is critical for implementing graceful shutdown at cutoff time.

**AMD ROCm Documentation — "Limitations and recommended settings for Radeon GPUs"**
- URL: https://rocm.docs.amd.com/projects/radeon/en/docs-6.3.4/docs/limitations.html
- **Credibility: High.** Official AMD documentation. Lists known limitations for consumer Radeon GPUs running ROCm.
- **Weight:** Official guidance on what is and isn't supported on RDNA3 consumer hardware.

**AMDGPU DebugFS — Linux Kernel Documentation**
- URL: https://docs.kernel.org/gpu/amdgpu/debugfs.html
- **Credibility: Very High.** Kernel.org documentation — the definitive reference for amdgpu debugfs interfaces including `amdgpu_gpu_recover`.
- **Weight:** Authoritative on GPU reset procedures and `gpu_recovery` parameter semantics.

### Secondary / Supporting Sources

**"Ollama Memory Management: Why Models Keep Loading" — SumGuy's Ramblings** (2026-01-22)
- URL: https://sumguy.com/ollama-memory-management/
- **Credibility: Medium.** Independent technical blog. The author demonstrates working knowledge of Ollama internals (scheduler, LRU unloading, `findRunnerToUnload`) and provides testable command examples. Not peer-reviewed but factually consistent with Ollama source code behavior.
- **Weight:** Useful synthesis of Ollama VRAM management behavior. All claims are verifiable against the Ollama source and `/api/ps` endpoint. The `OLLAMA_KEEP_ALIVE` and `OLLAMA_MAX_LOADED_MODELS` documentation matches official Ollama docs.

**"Building a bash script to auto-restart crashed ollama models" — Vipin PG** (2025)
- URL: https://vipinpg.com/blog/building-a-bash-script-to-auto-restart-crashed-ollama-models-detecting-oom-kills-and-resetting-cuda-contexts/
- **Credibility: Medium.** Independent developer blog. CUDA-focused (NVIDIA), but the architectural pattern (systemd service with 60-second health check, API endpoint test > log parsing, different recovery for OOM vs. driver-level hangs) is backend-agnostic and directly transferable to ROCm.
- **Weight:** Practical watchdog architecture pattern, adapted for AMD in the conclusions.

**"Ollama vs. vLLM: A deep dive into performance benchmarking" — Red Hat Developer** (2025-08-08)
- URL: https://developers.redhat.com/articles/2025/08/08/ollama-vs-vllm-deep-dive-performance-benchmarking
- **Credibility: High.** Red Hat is an established enterprise vendor. Quantitative benchmarks (793 TPS vs. 41 TPS) with reproducible methodology. The analysis is NVIDIA-focused but the architectural comparison holds.
- **Weight:** Influences the vLLM-vs-Ollama tradeoff analysis for batch workloads. The 3.2x throughput advantage of vLLM is relevant but must be weighed against the operational complexity on ROCm.

**"Large Scale Batch Processing with Ollama" — Robert McDermott, Medium** (2024-11-25)
- URL: https://robert-mcdermott.medium.com/large-scale-batch-processing-with-ollama-1e180533fb8a
- **Credibility: Medium.** Technical blog by a practitioner. Describes a working multi-GPU Ollama batch cluster processing 100K prompts/hour on small models. The approach (independent Ollama instances per GPU, load-balancing script) is practical.
- **Weight:** Validates the per-machine model specialization pattern. The 2,000 prompts/hour on Qwen 2.5 32B provides a useful throughput baseline.

**"The Energy Cost of Execution-Idle in GPU Clusters" — arXiv:2604.04745** (2026)
- URL: https://arxiv.org/pdf/2604.04745
- **Credibility: High.** Academic paper on arXiv. Peer-reviewed venue TBD but methodology is sound (empirical measurement of GPU power states during "execution-idle" periods, finding up to 65% of total energy consumed during underutilized intervals).
- **Weight:** Quantifies the idle-power penalty. For a single consumer GPU, the absolute numbers are smaller (one RX 7900 XT vs. 8× datacenter GPUs) but the principle holds: keeping a model loaded incurs a non-trivial continuous power cost.

**"Beyond Porting: How vLLM Orchestrates High-Performance Inference on AMD ROCm" — vLLM Blog** (2026-02-27)
- URL: https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html
- **Credibility: High.** Official vLLM project blog. Documents the `ROCM_AITER_FA` backend, Radeon consumer GPU support, and three-path routing (Prefill/Decode/Extend). Directly from vLLM maintainers.
- **Weight:** Confirms that vLLM now supports consumer Radeon GPUs and has AMD-specific optimizations. Critical for assessing whether vLLM is a viable alternative to Ollama for batch processing on this hardware.

### Lower-Weight / Caution Sources

**Various Medium/Dev.to blog posts and forum threads (Tom's Hardware, Overclock.net, Linus Tech Tips, Steam Community)**
- **Credibility: Low-Medium.** These are community forums and personal blogs. Temperature recommendations for the RX 7900 XT (core: 60–80°C ideal, junction: 85–95°C normal, 110°C hard limit) are consistent across multiple independent sources and align with AMD's published specifications, so the consensus is reliable. However, individual anecdotes about thermal paste pump-out or vapor chamber defects are not verified.
- **Weight:** Used only for thermal operating ranges where multiple independent sources agree. Not relied upon for novel claims.

**"How Hot is Too Hot? A Deep Dive Into 7900 XT Temps" — SilverPC Blog** (2025-10-17)
- URL: https://blog.silverpc.hu/2025/10/17/how-hot-is-too-hot-a-deep-dive-into-7900-xt-temps/
- **Credibility: Low.** Commercial PC blog, no identified author expertise. However, the hard thermal limit figures (110°C junction, RDNA3 throttling behavior) match AMD's official specifications.
- **Weight:** Used only for corroboration of thermal limits visible in official AMD docs.

## 4. Conclusions

### Architecture Decision: Model-Pin, Don't Switch

The most impactful architectural decision for overnight AMD batch processing is to **avoid model switching entirely within a batch run**. The known ROCm VRAM leak (Issue #5362) is triggered by loading/unloading models repeatedly — Ollama reports the model as unloaded, `rocm-smi` shows no process using VRAM, but the memory is not returned to the allocatable pool. Only Firefox (using a different GPU memory allocation path) and a full reboot can recover it.

**Recommendation:** Design the queue processor to either (a) use a single model for the entire batch run, loading once at start and unloading at end, or (b) if multiple models are required, restart the Ollama daemon between model switches as a mitigation. The batch queue should group prompts by target model and process one model's queue completely before switching.

For the current architecture (qwen3.6:27b as the primary model at 17.4 GB VRAM out of 24 GB available), model-pinning is viable: load once, process all queued prompts sequentially, unload.

### Thermal Management for Multi-Hour Runs

For the RX 7900 XT during overnight compute:
- **Safe operating range:** Core temperature 60–80°C, junction below 100°C. The hard RDNA3 thermal throttle limit is 110°C junction.
- **Inference power draw:** Expect 60–75% of the 300W TDP during inference (180–225W), lower than training/fine-tuning loads.
- **Undervolting is recommended** for sustained runs — it reduces temperature, power, and fan noise with negligible throughput loss by preventing thermal throttling.
- **Monitor don't assume:** `rocm-smi --showtemp --showpower` logging every 5 minutes provides an auditable thermal record. A pre-run `rocm-smi --setfan 200` can be used to force higher fan speeds for cooling headroom.

### Watchdog and Health-Check Strategy

A three-tier watchdog approach, from least to most disruptive:

1. **Liveness probe (every 60s):** `curl -s http://localhost:11434/api/ps` — if Ollama is unresponsive, the API won't return. This catches process-level failures.

2. **GPU health check (every 120s):** `rocm-smi -i 0 --json | jq '.. | select(.power_used?) | .power_used'` — the ROCm hang signature is 100% GPU utilization with **near-zero power draw** (the GPU is stuck in a spin loop, not computing). If power drops below ~50W while a job is supposedly running, the GPU is hung.

3. **GPU reset (on confirmed hang):**
   - First attempt: `sudo rocm-smi --gpureset -d 0` (may not work for all hang types)
   - Fallback: `echo 1 | sudo tee /sys/module/amdgpu/parameters/gpu_recovery` followed by `sudo cat /sys/kernel/debug/dri/0/amdgpu_gpu_recover`
   - Last resort: `sudo systemctl restart ollama` and skip the current job, re-queueing it

### ROCm Stability Prerequisites

Before deploying an overnight batch system, ensure:

1. **Kernel parameter:** `amdgpu.cwsr_enable=0` in the kernel command line. This is a non-negotiable requirement for RDNA3 GPUs (RX 7000 series) on any ROCm version through at least 7.2.0. Without it, MES firmware hangs are documented and likely on multi-hour runs.

2. **ROCm version:** Minimum ROCm 7.2.0. Earlier versions (7.1.x) have a documented host CPU memory leak (~70–90 GB/hour) that will OOM the system on overnight runs. 7.2.0 reduces this to ~5.4 GB/hr with the CWSR workaround, making 8-hour runs viable on a system with >= 64 GB RAM.

3. **ROCm/Ollama version compatibility:** Ollama 0.17+ bundles ROCm 7 libraries. The kernel driver and userspace ROCm libraries must match major versions. Mismatched versions cause 30-second GPU initialization hangs followed by CPU fallback.

### Systemd Timer Integration Patterns

Key configuration details for the batch-queue timer and service:

- **`Persistent=true`** in `[Timer]` catches up on missed runs after a power-off or reboot. Note: this does NOT reliably catch up after suspend/sleep — `Persistent` is designed for power-off scenarios, not S3 sleep. The office machine should be configured to not suspend during the batch window.

- **`RuntimeMaxSec=8h`** in `[Service]` provides a hard upper bound. When exceeded, systemd sends SIGTERM (via `KillSignal=`), waits `TimeoutStopSec=`, then SIGKILL. The service's `ExecStop=` script should flush the current job result before the SIGKILL arrives.

- **`EXTEND_TIMEOUT_USEC=`** via sd_notify: If using `Type=notify`, the batch processor can extend `RuntimeMaxSec` to finish the current job before shutdown. This is the mechanism for "finish the current job, then stop" rather than mid-job SIGTERM.

- **`loginctl enable-linger john`** — Required for user timers to fire when no login session is active. Without lingering, the user timer only fires while the user is logged in, defeating the purpose of overnight scheduling.

- **`WakeSystem=true` only works for root timers** — not applicable to user-level batch scheduling. Do not rely on wake-from-sleep for user services.

### Multi-GPU / Multi-Machine Orchestration

For the office + arch setup:

- **Do not attempt distributed inference** (tensor parallelism or pipeline parallelism across machines). Consumer network bandwidth and the GPU capability asymmetry (24 GB vs. <8 GB) make this impractical.

- **Per-machine model specialization:** Office runs qwen3.6:27b (fits in 24 GB), arch runs gemma4 (fits in <8 GB). Each machine independently processes prompts tagged for its model.

- **Queue distribution options (ordered by complexity):**
  1. **Static assignment:** Prompts specify a target model; the enqueue function routes to the correct machine's queue directory.
  2. **Shared filesystem:** NFS-mount the queue directory on both machines. Each processor claims jobs by moving them to a per-machine `running/` subdirectory.
  3. **HTTP pull:** The arch processor periodically polls the office queue for gemma4-tagged jobs, fetches them, and posts results back.

- **Throughput expectations:** With qwen3.6:27b on the RX 7900 XT, expect roughly 20–40 tokens/second (decode-limited, single-request). A typical research prompt of 2000 input + 2000 output tokens runs in about 60–100 seconds. An 8-hour window can process approximately 300–500 prompts of this size, assuming 60s per job including overhead. This is ample for personal research queue use.

### Idle-Power vs. Throughput Tradeoff

For overnight batch processing specifically, the idle-power concern is **less relevant** than in production serving: the batch window is time-bound (e.g., 23:00–07:00), and the GPU will be actively computing for most of that window. The dominant cost is throughput, not idle draw.

If electricity cost is a concern, consider:
- `rocm-smi --setpoweroverdrive` to cap power draw (e.g., 200W instead of the default 300W TDP). This reduces throughput proportionally but may be acceptable for overnight runs where wall-clock time is not the binding constraint.
- NVIDIA datacenter measurements show loaded-but-idle GPUs consume ~41W extra per GPU above baseline idle. For a single consumer GPU, the loaded-idle penalty is smaller but non-zero. If there will be long gaps between jobs (e.g., processing completes at 02:00 but the window runs until 07:00), consider unloading the model after the last job to eliminate the idle power draw.

## 5. Bibliography

ROCm/ROCm. (2025, September 17). *Ollama triggers some weird form of memory leak. It's like the whole graphic stack has the ability to unload VRAM disabled* [Issue #5362]. GitHub. https://github.com/ROCm/ROCm/issues/5362

ROCm/ROCm. (2025, October 28). *amdgpu compute wave store and resume causing MES firmware 0x80 hang* [Issue #5590]. GitHub. https://github.com/ROCm/ROCm/issues/5590

ROCm/ROCm. (2025, November 29). *amdgpu firmware (MES 0x83) causing GPU Hang / Memory access fault w/ Strix Halo* [Issue #5724]. GitHub. https://github.com/ROCm/ROCm/issues/5724

ROCm/ROCm. (2026, January 30). *Host CPU memory leak with amdgpu-dkms driver during GPU compute workloads* [Issue #5915]. GitHub. https://github.com/ROCm/ROCm/issues/5915

AMD. (n.d.). *Limitations and recommended settings — Use ROCm on Radeon GPUs* (ROCm 6.3.4 documentation). https://rocm.docs.amd.com/projects/radeon/en/docs-6.3.4/docs/limitations.html

Linux Kernel Documentation. (n.d.). *AMDGPU DebugFS*. https://docs.kernel.org/gpu/amdgpu/debugfs.html

Linux Kernel Documentation. (n.d.). *drm/amdgpu AMDgpu driver*. https://dri.freedesktop.org/docs/drm/gpu/amdgpu.html

SumGuy. (2026, January 22). *Ollama memory management: Why models keep loading*. SumGuy's Ramblings. https://sumguy.com/ollama-memory-management/

Vipin PG. (2025). *Building a bash script to auto-restart crashed ollama models: Detecting OOM kills and resetting CUDA contexts*. https://vipinpg.com/blog/building-a-bash-script-to-auto-restart-crashed-ollama-models-detecting-oom-kills-and-resetting-cuda-contexts/

Red Hat Developer. (2025, August 8). *Ollama vs. vLLM: A deep dive into performance benchmarking*. https://developers.redhat.com/articles/2025/08/08/ollama-vs-vllm-deep-dive-performance-benchmarking

McDermott, R. (2024, November 25). *Large scale batch processing with Ollama*. Medium. https://robert-mcdermott.medium.com/large-scale-batch-processing-with-ollama-1e180533fb8a

The Energy Cost of Execution-Idle in GPU Clusters. (2026). arXiv:2604.04745. https://arxiv.org/pdf/2604.04745

vLLM Blog. (2026, February 27). *Beyond porting: How vLLM orchestrates high-performance inference on AMD ROCm*. https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html

systemd. (2026, March 23). *systemd.service(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.service.5.en.html

systemd. (2026, March 23). *systemd.timer(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html

ArchWiki. (n.d.). *systemd/Timers*. https://wiki.archlinux.org/title/Systemd/Timers

AMD. (2024, September 19). *Inferencing and serving with vLLM on AMD GPUs*. ROCm Blogs. https://rocm.blogs.amd.com/artificial-intelligence/vllm/README.html

Ollama. (n.d.). *FAQ*. https://docs.ollama.com/faq

Ollama. (n.d.). *Troubleshooting*. https://docs.ollama.com/troubleshooting

DynamoLLM: Designing LLM Inference Clusters for Performance and Energy Efficiency. (2025). *HPCA 2025*. https://jovans2.github.io/files/DynamoLLM_HPCA2025.pdf

SilverPC Blog. (2025, October 17). *How hot is too hot? A deep dive into 7900 XT temps*. https://blog.silverpc.hu/2025/10/17/how-hot-is-too-hot-a-deep-dive-into-7900-xt-temps/

TechReviewer. (n.d.). *Is the Radeon RX 7900 XT good for running LLMs?* https://www.techreviewer.com/tech-specs/amd-rx-7900-xt-gpu-for-llms/

ROCm SMI LIB 7.0.0 Documentation. (n.d.). *Radeon Open Compute (ROCm) - System Management Interface - Command Line Tool*. https://rocm.docs.amd.com/projects/rocm_smi_lib/en/docs-6.1.0/python_usage.html

Ollama. (2026). *New model scheduling*. Ollama Blog. https://ollama.com/blog/new-model-scheduling

Markaicode. (2026, March 12). *Configure Ollama keep-alive: Memory management for always-on models*. https://markaicode.com/ollama-keep-alive-memory-management/

systemd. (2022, October 13). *Persistent timer doesn't trigger after missed calendar run* [Issue #24984]. GitHub. https://github.com/systemd/systemd/issues/24984
