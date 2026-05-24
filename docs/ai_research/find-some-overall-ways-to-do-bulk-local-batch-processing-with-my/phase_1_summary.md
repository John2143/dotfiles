# Phase 1 Summary

## Primary Question
What are the most effective architectures, tools, and patterns for running bulk/batch LLM inference workloads on consumer-grade home GPU hardware, specifically for overnight automated processing — queuing prompts during the day, running them sequentially on local GPU(s) at night, and collecting results?

## Sub-Topic Findings

### Ollama Batch and Concurrent Inference
**Perspective**: none
**Researcher conclusion**: Ollama has no built-in batch mode — external queue processing is required. Its sequential default (`OLLAMA_NUM_PARALLEL=1`) is well-aligned with overnight batch on a single GPU: it avoids VRAM contention and guarantees predictable per-job memory usage. Key recommendations: set `OLLAMA_KEEP_ALIVE=-1` to prevent model unloading between jobs, configure `num_batch=1024` as a safe optimization for the user's ~6.6GB VRAM headroom, and use `/api/generate` with `stream: false` for the queue processor. The existing plan's architecture (filesystem queue → sequential processor → Ollama) is correct.
**Relation to primary question**: Ollama serves as the inference backend in a queue-processor architecture; it handles raw token generation while an external system manages scheduling, queuing, and result collection. No changes to the inference backend are needed — the plan's approach of wrapping Ollama is correct.

### vLLM Offline and Batch Inference
**Perspective**: none
**Researcher conclusion**: vLLM provides two batch paths: offline mode (`LLM.generate()`/`LLM.chat()` — one-shot Python API) and server mode (OpenAI-compatible REST API with continuous batching). AMD ROCm is now a first-class vLLM platform as of v0.14.0 (93% CI pass rate, dedicated Docker images). Server mode is recommended for agent harness (OMP) integration because it supports tool calling, structured output, and streaming — all of which offline mode lacks. The `vllm run-batch` CLI offers a middle ground for simple file-based batch jobs. The user's existing `nixos/modules/vllm.nix` already supports `gpuBackend = "rocm"`. For the qwen3.6:27b model, vLLM would need the HuggingFace safetensors equivalent (`Qwen/Qwen3-30B-A3B`), not the GGUF format Ollama uses.
**Relation to primary question**: vLLM is a viable higher-throughput alternative to Ollama for the inference backend, particularly if the user needs tool calling, structured output, or batch processing of many prompts. However, the added operational complexity (ROCm Docker image, model format conversion, persistent server) makes Ollama the simpler v1 choice.

### Open-Source LLM Job Queue and Batch Systems
**Perspective**: open-source pragmatist
**Researcher conclusion**: No dedicated "LLM batch queue" project exists that is simpler than a filesystem-based queue with `flock` and systemd timers. The three-tier landscape: (1) inference-engine-native queuing (vLLM slots, Ollama FIFO) is for live serving concurrency, not overnight job scheduling; (2) lightweight wrappers (ollama-batch-cluster, ollama-batch-requests) exist but are multi-GPU focused; (3) general-purpose job queues (Celery, BullMQ, SLURM) introduce unwarranted dependency complexity for single-machine use. The filesystem-based architecture in the existing plan is the correct level of complexity. Continuous batching is largely irrelevant for sequential overnight processing — it benefits concurrent requests, not one-at-a-time jobs.
**Relation to primary question**: The queue architecture matters less than the inference engine choice for this use case. The filesystem-queue + systemd pattern is validated as the simplest correct approach for single-GPU overnight batch. No external dependencies (Redis, RabbitMQ, SLURM) are justified at this scale.

### Hardware and Infrastructure Patterns for Overnight GPU Batch
**Perspective**: AMD ROCm home-lab operator
**Researcher conclusion**: AMD consumer GPUs require proactive management of three risk categories: (1) VRAM leaks triggered by model switching — mitigated by model-pinning (load once, process all jobs, unload); (2) MES firmware hangs (`amdgpu.cwsr_enable=0` kernel parameter is non-negotiable for RDNA3); (3) host memory leaks in ROCm <7.2.0 (~70-90 GB/hr). A three-tier watchdog is recommended: Ollama API liveness probe → `rocm-smi` power check → `amdgpu_gpu_recover` debugfs reset. Systemd user timers require `loginctl enable-linger` for overnight firing. Multi-machine orchestration (office + arch) should use per-machine model specialization, not distributed inference. The RX 7900 XT at ~180-225W during inference can safely run 8-hour overnight sessions with proper cooling.
**Relation to primary question**: Hardware-level AMD ROCm instability risks must be designed around — they are not edge cases but expected failure modes for unattended multi-hour runs. The queue processor architecture must include watchdog loops, GPU health checks, and single-model-per-run pinning rather than assuming reliable GPU operation.

### Agent Harness Batch Processing Patterns
**Perspective**: none
**Researcher conclusion**: Every major agent harness now has a headless mode. OMP's print mode (`omp -p "prompt" --no-session`) is the most natural fit for the user's existing stack. The overnight agent queue pattern is well-established across multiple open-source projects (night-watch-cli, sleepless-agent, block/agent-task-queue, overstory), all converging on the same architecture: filesystem queue with pending/running/done/failed dirs, flock locking, per-job `mktemp -d` isolation, timeout enforcement, and systemd scheduling. The existing plan matches this pattern exactly. Critical operational guards for unattended execution: loop detection, per-tool timeouts, context window management, state externalization, and error classification (transient vs. fatal).
**Relation to primary question**: Agent harness batch processing is fundamentally different from raw LLM batch inference — it requires stateful multi-turn orchestration with tool-call loop management. The architecture needs both layers: an inference backend (Ollama) and a harness-level queue system. The existing plan provides both.

## Cross-Cutting Insights

1. **The existing plan is validated across all five sub-topics.** Every report independently concluded that the filesystem-queue + systemd + sequential-processor architecture is correct. No contradictions emerged between reports. The plan needs enhancement (watchdog patterns, model-pinning, ROCm stability prerequisites) but no fundamental redesign.

2. **Ollama vs. vLLM is the central tradeoff.** Ollama is simpler (already running, GGUF models, no format conversion) but offers lower throughput. vLLM offers higher throughput via continuous batching and better agent harness integration (tool calling, structured output) but requires operational overhead (ROCm Docker, safetensors models). For v1, Ollama is the pragmatic choice; vLLM is a performance upgrade path.

3. **ROCm stability is the highest-risk area.** Three independent reports flagged AMD-specific failure modes (VRAM leaks, MES firmware hangs, host memory leaks). These are not theoretical — they are documented in AMD's own issue tracker with confirmed reproduction steps. The `amdgpu.cwsr_enable=0` kernel parameter, ROCm ≥7.2.0, and model-pinning are prerequisites, not optimizations.

4. **The batch queue pattern is a solved problem.** Five open-source overnight agent queue projects and a survey of production failure analyses all converge on the same architectural pattern. The user's plan does not need novel design — it needs careful implementation of known patterns with AMD-specific hardening.

5. **Systemd user timers have a critical gotcha.** `loginctl enable-linger` is required for user timers to fire when no login session is active. Without it, an overnight timer scheduled for 23:00 will not fire because the user's session was closed. This is a single-command fix but easy to miss.

6. **Continuous batching is a red herring for sequential overnight processing.** Both the Ollama and job-queue reports independently concluded that continuous batching benefits concurrent request handling, not sequential one-at-a-time processing. For overnight batch where latency is irrelevant and jobs are long-running agent sessions, sequential processing is correct.

## Consolidated Bibliography

AMD. (2026, January 21). *ROCm becomes a first-class platform in the vLLM ecosystem*. ROCm Blogs. https://rocm.blogs.amd.com/software-tools-optimization/vllm-omni/README.html

AMD. (2026, February 27). Beyond porting: How vLLM orchestrates high-performance inference on AMD ROCm. *vLLM Blog*. https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html

AMD. (n.d.). *Limitations and recommended settings — Use ROCm on Radeon GPUs* (ROCm 6.3.4 documentation). https://rocm.docs.amd.com/projects/radeon/en/docs-6.3.4/docs/limitations.html

Anthropic. (2026). *Run Claude Code programmatically*. Claude Code Docs. https://code.claude.com/docs/en/headless

Aphrodite Engine Project. (2026). *aphrodite-engine* [Source code]. GitHub. https://github.com/aphrodite-engine/aphrodite-engine

Block. (2026). *agent-task-queue: Local task queuing for AI agents* [Source code]. GitHub. https://github.com/block/agent-task-queue

can1357. (2026). *oh-my-pi: AI Coding agent for the terminal* [Source code]. GitHub. https://github.com/can1357/oh-my-pi

Compute Market. (2026, May). *Best AMD GPU for local LLM inference 2026*. https://www.compute-market.com/blog/best-amd-gpu-local-llm-inference-2026

context-machine-lab. (2026). *sleepless-agent: 24/7 AI agent that maximizes Claude Code Pro usage via Slack* [Source code]. GitHub. https://github.com/context-machine-lab/sleepless-agent

CraftRigs. (2026, March 29). *AMD ROCm in 2026 — Is it finally ready for local LLMs?* https://craftrigs.com/articles/amd-rocm-local-llm-2026/

CrewAI. (2026). *Flows*. CrewAI Documentation. https://docs.crewai.com/en/concepts/flows

DigitalOcean. (2026, January 12). *How to choose the right GPU for vLLM inference*. https://www.digitalocean.com/community/conceptual-articles/vllm-gpu-sizing-configuration-guide

EastonDev Blog. (2026, April 10). *Ollama performance optimization: Complete guide to quantization, batch processing, and memory tuning*. https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/

Fast.io. (2026, February 10). *How to Build AI Agents for Batch Processing*. https://fast.io/resources/ai-agent-batch-processing/

Fowler, M. (2026, May 12). *Harness engineering for coding agent users*. martinfowler.com. https://martinfowler.com/articles/harness-engineering.html

Gauthier, P. (2026). *Scripting aider*. Aider Documentation. https://aider.chat/docs/scripting.html

Glukhov, R. (2025, May). *How Ollama handles parallel requests*. https://www.glukhov.org/llm-performance/ollama/how-ollama-handles-parallel-requests/

Hugging Face. (2026). Text Generation Inference (TGI) documentation. https://huggingface.co/docs/text-generation-inference/en/index

jonit-dev. (2026). *night-watch-cli: AI agent that implements your specs, opens PRs, and reviews code overnight* [Source code]. GitHub. https://github.com/jonit-dev/night-watch-cli

Linux Kernel Documentation. (n.d.). *AMDGPU DebugFS*. https://docs.kernel.org/gpu/amdgpu/debugfs.html

Llama.cpp Project. (2026). llama.cpp server README. GitHub. https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

LMSYS Organization. (2024, December 4). SGLang v0.4: Zero-overhead batch scheduler. *LMSYS Blog*. https://www.lmsys.org/blog/2024-12-04-sglang-v0-4/

Markaicode. (2026, March 12). *Configure Ollama concurrent requests: Parallel inference setup 2026*. https://markaicode.com/ollama-concurrent-requests-parallel-inference/

Markaicode. (2026, March 10). *Handling long-running AI jobs with Redis and Celery*. https://markaicode.com/redis-celery-long-running-ai-jobs/

McDermott, R. (2024). *ollama-batch-cluster* [Source code]. GitHub. https://github.com/robert-mcdermott/ollama-batch-cluster

McDermott, R. (2024, November 25). *Large scale batch processing with Ollama*. Medium. https://robert-mcdermott.medium.com/large-scale-batch-processing-with-ollama-1e180533fb8a

MindStudio. (2026). *How to Build an AI Agent That Runs Overnight: A Practical Guide*. https://www.mindstudio.ai/blog/build-ai-agent-runs-overnight

Ollama. (n.d.). *API reference*. https://ollama.readthedocs.io/en/api/

Ollama. (n.d.). *FAQ*. https://docs.ollama.com/faq

Ollama. (2024, January 5). *OOM errors for large context models* [Issue #1800]. GitHub. https://github.com/ollama/ollama/issues/1800

Ollama. (2025, July 2). *Parallel computing support for concurrent Ollama requests* [Issue #11277]. GitHub. https://github.com/ollama/ollama/issues/11277

OpenHands. (2026). *Headless Mode*. OpenHands Documentation. https://docs.openhands.dev/openhands/usage/cli/headless

Red Hat Developer. (2025, August 8). *Ollama vs. vLLM: A deep dive into performance benchmarking*. https://developers.redhat.com/articles/2025/08/08/ollama-vs-vllm-deep-dive-performance-benchmarking

Renze, B. (2026, March 4). *How AI Agents Handle Stalled Tasks and Timeouts*. DEV Community. https://dev.to/bobrenze/how-ai-agents-handle-stalled-tasks-and-timeouts-lessons-from-my-production-failure-1jj9

ROCm/ROCm. (2025, September 17). *Ollama triggers some weird form of memory leak* [Issue #5362]. GitHub. https://github.com/ROCm/ROCm/issues/5362

ROCm/ROCm. (2025, October 28). *amdgpu compute wave store and resume causing MES firmware 0x80 hang* [Issue #5590]. GitHub. https://github.com/ROCm/ROCm/issues/5590

ROCm/ROCm. (2026, January 30). *Host CPU memory leak with amdgpu-dkms driver* [Issue #5915]. GitHub. https://github.com/ROCm/ROCm/issues/5915

Sandler, E. (2026, April 27). *Batch API is terrible for one agent. It might be great for a fleet.* https://eran.sandler.co.il/post/2026-04-27-batch-api-is-terrible-for-one-agent/

SGLang Project. (2026). *sglang* [Source code]. GitHub. https://github.com/sgl-project/sglang

Shanghai AI Laboratory. (2026). LMDeploy documentation. https://lmdeploy.readthedocs.io/en/latest/

SumGuy. (2026, January 22). *Ollama memory management: Why models keep loading*. https://sumguy.com/ollama-memory-management/

systemd. (2026). *systemd.service(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.service.5.en.html

systemd. (2026). *systemd.timer(5)*. Debian Manpages. https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html

The Energy Cost of Execution-Idle in GPU Clusters. (2026). arXiv:2604.04745. https://arxiv.org/pdf/2604.04745

The New Stack. (2026). *Inside the vLLM inference server: From prompt to response*. https://thenewstack.io/inside-the-vllm-inference-server-from-prompt-to-response/

troutceremony. (2026, February 10). *Building a local LLM environment with RX 7900 XTX, WSL2, ROCm, and vLLM*. Zenn. https://zenn.dev/troutceremony/articles/f1bf689b878a06?locale=en

Vipin PG. (2025). *Building a bash script to auto-restart crashed ollama models*. https://vipinpg.com/blog/building-a-bash-script-to-auto-restart-crashed-ollama-models-detecting-oom-kills-and-resetting-cuda-contexts/

vLLM Project. (n.d.). *GPU installation*. https://docs.vllm.ai/en/stable/getting_started/installation/gpu/

vLLM Project. (n.d.). *Offline inference*. https://docs.vllm.ai/en/stable/serving/offline_inference/

vLLM Project. (n.d.). *OpenAI-compatible server*. https://docs.vllm.ai/en/stable/serving/openai_compatible_server/

vLLM Project. (n.d.). *Quickstart*. https://docs.vllm.ai/en/stable/getting_started/quickstart/

vLLM Project. (n.d.). *vllm run-batch*. https://docs.vllm.ai/en/stable/cli/run-batch/

West, J. (2026). *overstory: Multi-agent orchestration for AI coding agents* [Source code]. GitHub. https://github.com/jayminwest/overstory

Whoff Agents. (2026, April 9). *AI Agent Production Failures: What Breaks and How to Build Around It*. DEV Community. https://dev.to/whoffagents/ai-agent-production-failures-what-breaks-and-how-to-build-around-it-17lj

Wu, Z., et al. (2025). *Batch Query Processing and Optimization for Agentic Workflows*. arXiv. https://arxiv.org/html/2509.02121v1

Zhang, Y., et al. (2025). *Agent.xpu: Efficient Scheduling of Agentic LLM Workloads on Heterogeneous SoC*. arXiv. https://arxiv.org/html/2506.24045v1/

Zhu, T., Shah, D., & Wierman, A. (2025). Queueing, predictions, and large language models: Challenges and open problems. *Stochastic Systems*. https://arxiv.org/abs/2503.07545

## Decision
**SUFFICIENT.** The primary question is answered fully and confidently. All five sub-topics produced consistent, mutually reinforcing findings with no contradictions. The existing plan's architecture is validated; the research surfaced concrete enhancements (ROCm stability prerequisites, watchdog patterns, model-pinning, `loginctl enable-linger`) that can be incorporated into implementation. No new sub-questions emerged that require further investigation. The consolidated bibliography provides 50+ sources for audit.
