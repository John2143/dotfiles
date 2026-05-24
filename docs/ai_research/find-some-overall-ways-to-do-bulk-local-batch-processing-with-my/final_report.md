# Final Report: Bulk Local Batch Processing with Home GPUs

## 1. Answer

The most effective architecture for bulk overnight LLM batch processing on consumer AMD GPUs is a **filesystem-based queue processor** that runs sequential agent sessions through Ollama, orchestrated by systemd user timers. This conclusion is supported by five independent research sub-topics spanning inference engines, job queue systems, hardware/infrastructure patterns, and agent harness batch processing — with no contradictions across reports.

The architecture is straightforward: a queue directory (`pending/` → `running/` → `done/` | `failed/`) where each file is a research prompt, a Fish shell processor script that acquires an `flock` lock, iterates pending jobs, spawns `omp -p "$(cat prompt)" --no-session --model office-ollama/qwen3.6:27b` in an isolated temporary working directory, enforces a 30-minute per-job timeout, and collects results. A systemd user timer fires nightly. This pattern — validated across five open-source overnight agent queue projects (night-watch-cli, sleepless-agent, block/agent-task-queue, overstory, TinyAGI) — requires no external dependencies (no Redis, RabbitMQ, or SLURM), stores all state on the filesystem, and is the simplest correct solution for single-GPU overnight use.

Three AMD-specific prerequisites are non-negotiable: the `amdgpu.cwsr_enable=0` kernel parameter (prevents MES firmware hangs on RDNA3), ROCm version ≥7.2.0 (fixes a ~70–90 GB/hr host memory leak present in earlier versions), and `loginctl enable-linger` (required for user timers to fire when no login session is active). Model-pinning — loading the target model once at batch start and keeping it loaded via `OLLAMA_KEEP_ALIVE=-1` — avoids the primary trigger for ROCm VRAM leaks. A three-tier watchdog (Ollama API liveness probe → `rocm-smi` power check → `amdgpu_gpu_recover` debugfs reset) must be integrated into the processor to handle the GPU hangs that are expected, not exceptional, on multi-hour unattended AMD runs.

Ollama should remain the v1 inference backend (already running, GGUF models, no format conversion) with vLLM as a throughput upgrade path (higher throughput via continuous batching, native tool-calling support, but requires ROCm Docker and safetensors model format). The existing architecture plan is correct and needs enhancement — not redesign — with the AMD-specific hardening patterns identified by this research.

## 2. Evidence Summary

| Key Finding | Source |
|-------------|--------|
| Filesystem-based queue is the correct architecture; no simpler dedicated "LLM batch queue" exists | [Open-Source LLM Job Queue Systems](reports/llm-job-queue-systems_report.md) |
| Ollama has no built-in batch mode; sequential processing (`OLLAMA_NUM_PARALLEL=1`) with `OLLAMA_KEEP_ALIVE=-1` is the safe default | [Ollama Batch and Concurrent Inference](reports/ollama-batch-concurrent_report.md) |
| vLLM now has first-class ROCm support (93% CI pass rate, prebuilt Docker images); server mode recommended for agent harness integration | [vLLM Offline and Batch Inference](reports/vllm-offline-batch_report.md) |
| `amdgpu.cwsr_enable=0` is non-negotiable for RDNA3; ROCm ≥7.2.0 required; model-pinning prevents VRAM leaks | [Hardware and Infrastructure Patterns](reports/hardware-infra-patterns_report.md) |
| Five open-source projects converge on the same queue pattern; OMP print mode is the best fit; loop detection and per-tool timeouts are critical | [Agent Harness Batch Processing Patterns](reports/agent-harness-batch-patterns_report.md) |
| `loginctl enable-linger` required for user timer overnight firing; systemd `RuntimeMaxSec` provides hard safety bound | [Hardware and Infrastructure Patterns](reports/hardware-infra-patterns_report.md) |
| Continuous batching is irrelevant for sequential overnight processing; general-purpose job queues add unwarranted complexity | [Open-Source LLM Job Queue Systems](reports/llm-job-queue-systems_report.md) |

## 3. Confidence Assessment

**High confidence.** All five sub-topics produced consistent, mutually reinforcing findings from 50+ sources including official AMD ROCm documentation, Ollama and vLLM primary documentation, AMD's own issue tracker (with confirmed reproduction steps for the three AMD-specific failure modes), systemd manpages, and source-verified analysis of five open-source overnight agent queue projects. No contradictory evidence emerged. The architectural pattern (filesystem queue + flock + systemd + sequential processing) is validated by independent reports that did not coordinate with each other. The AMD-specific prerequisites (`cwsr_enable=0`, ROCm ≥7.2.0, model-pinning) are confirmed by multiple independent sources including AMD's own bug tracker.

## 4. Limitations and Open Questions

- **vLLM model format gap**: The user's models are in GGUF format (Ollama); vLLM requires safetensors. Converting qwen3.6:27b GGUF to safetensors or sourcing the equivalent HuggingFace model (`Qwen/Qwen3-30B-A3B`) is not covered.
- **Arch machine integration**: The secondary arch machine was unreachable during research. Multi-machine orchestration patterns (per-machine model specialization, shared queue via NFS/HTTP) are identified but not tested against the user's specific network topology.
- **Nightly timer reliability**: `Persistent=true` behavior after systemd suspend vs. power-off was noted as a potential gotcha but not tested against the user's specific NixOS power management configuration.
- **Agent loop detection**: The research identifies loop detection as critical for unattended execution but does not design a specific detection mechanism for OMP's tool-call patterns.
- **VRAM leak workarounds**: The model-pinning mitigation is documented as effective but not guaranteed. A full ollama restart between model switches may still be needed if the leak manifests despite pinning.

## 5. Bibliography

AMD. (2026, January 21). *ROCm becomes a first-class platform in the vLLM ecosystem*. ROCm Blogs. https://rocm.blogs.amd.com/software-tools-optimization/vllm-omni/README.html

AMD. (2026, February 27). Beyond porting: How vLLM orchestrates high-performance inference on AMD ROCm. *vLLM Blog*. https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html

AMD. (n.d.). *Limitations and recommended settings — Use ROCm on Radeon GPUs* (ROCm 6.3.4 documentation). https://rocm.docs.amd.com/projects/radeon/en/docs-6.3.4/docs/limitations.html

Anthropic. (2026). *Run Claude Code programmatically*. Claude Code Docs. https://code.claude.com/docs/en/headless

Block. (2026). *agent-task-queue: Local task queuing for AI agents* [Source code]. GitHub. https://github.com/block/agent-task-queue

can1357. (2026). *oh-my-pi: AI Coding agent for the terminal* [Source code]. GitHub. https://github.com/can1357/oh-my-pi

context-machine-lab. (2026). *sleepless-agent: 24/7 AI agent that maximizes Claude Code Pro usage via Slack* [Source code]. GitHub. https://github.com/context-machine-lab/sleepless-agent

CraftRigs. (2026, March 29). *AMD ROCm in 2026 — Is it finally ready for local LLMs?* https://craftrigs.com/articles/amd-rocm-local-llm-2026/

EastonDev Blog. (2026, April 10). *Ollama performance optimization: Complete guide to quantization, batch processing, and memory tuning*. https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/

Fowler, M. (2026, May 12). *Harness engineering for coding agent users*. martinfowler.com. https://martinfowler.com/articles/harness-engineering.html

Gauthier, P. (2026). *Scripting aider*. Aider Documentation. https://aider.chat/docs/scripting.html

Glukhov, R. (2025, May). *How Ollama handles parallel requests*. https://www.glukhov.org/llm-performance/ollama/how-ollama-handles-parallel-requests/

jonit-dev. (2026). *night-watch-cli: AI agent that implements your specs, opens PRs, and reviews code overnight* [Source code]. GitHub. https://github.com/jonit-dev/night-watch-cli

Linux Kernel Documentation. (n.d.). *AMDGPU DebugFS*. https://docs.kernel.org/gpu/amdgpu/debugfs.html

Markaicode. (2026, March 12). *Configure Ollama concurrent requests: Parallel inference setup 2026*. https://markaicode.com/ollama-concurrent-requests-parallel-inference/

McDermott, R. (2024). *ollama-batch-cluster* [Source code]. GitHub. https://github.com/robert-mcdermott/ollama-batch-cluster

McDermott, R. (2024, November 25). *Large scale batch processing with Ollama*. Medium. https://robert-mcdermott.medium.com/large-scale-batch-processing-with-ollama-1e180533fb8a

Ollama. (n.d.). *API reference*. https://ollama.readthedocs.io/en/api/

Ollama. (n.d.). *FAQ*. https://docs.ollama.com/faq

OpenHands. (2026). *Headless Mode*. OpenHands Documentation. https://docs.openhands.dev/openhands/usage/cli/headless

Red Hat Developer. (2025, August 8). *Ollama vs. vLLM: A deep dive into performance benchmarking*. https://developers.redhat.com/articles/2025/08/08/ollama-vs-vllm-deep-dive-performance-benchmarking

ROCm/ROCm. (2025, September 17). *Ollama triggers some weird form of memory leak* [Issue #5362]. GitHub. https://github.com/ROCm/ROCm/issues/5362

ROCm/ROCm. (2025, October 28). *amdgpu compute wave store and resume causing MES firmware 0x80 hang* [Issue #5590]. GitHub. https://github.com/ROCm/ROCm/issues/5590

ROCm/ROCm. (2026, January 30). *Host CPU memory leak with amdgpu-dkms driver* [Issue #5915]. GitHub. https://github.com/ROCm/ROCm/issues/5915

Sandler, E. (2026, April 27). *Batch API is terrible for one agent. It might be great for a fleet.* https://eran.sandler.co.il/post/2026-04-27-batch-api-is-terrible-for-one-agent/

SumGuy. (2026, January 22). *Ollama memory management: Why models keep loading*. https://sumguy.com/ollama-memory-management/

systemd. (2026). *systemd.service(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.service.5.en.html

systemd. (2026). *systemd.timer(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html

troutceremony. (2026, February 10). *Building a local LLM environment with RX 7900 XTX, WSL2, ROCm, and vLLM*. Zenn. https://zenn.dev/troutceremony/articles/f1bf689b878a06?locale=en

Vipin PG. (2025). *Building a bash script to auto-restart crashed ollama models*. https://vipinpg.com/blog/building-a-bash-script-to-auto-restart-crashed-ollama-models-detecting-oom-kills-and-resetting-cuda-contexts/

vLLM Project. (n.d.). *GPU installation*. https://docs.vllm.ai/en/stable/getting_started/installation/gpu/

vLLM Project. (n.d.). *Offline inference*. https://docs.vllm.ai/en/stable/serving/offline_inference/

vLLM Project. (n.d.). *OpenAI-compatible server*. https://docs.vllm.ai/en/stable/serving/openai_compatible_server/

vLLM Project. (n.d.). *vllm run-batch*. https://docs.vllm.ai/en/stable/cli/run-batch/

West, J. (2026). *overstory: Multi-agent orchestration for AI coding agents* [Source code]. GitHub. https://github.com/jayminwest/overstory

Zhu, T., Shah, D., & Wierman, A. (2025). Queueing, predictions, and large language models: Challenges and open problems. *Stochastic Systems*. https://arxiv.org/abs/2503.07545
