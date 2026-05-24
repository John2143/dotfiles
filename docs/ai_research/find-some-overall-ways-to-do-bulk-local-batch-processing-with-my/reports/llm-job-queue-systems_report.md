# LLM Job Queue and Batch Systems for Consumer GPU Hardware

## 1. Summary

The landscape of LLM inference job queuing and batch processing has matured dramatically in 2025–2026. The field can be divided into three tiers: **inference-engine-native queuing** (built into the model server itself), **lightweight external queue wrappers** (thin orchestration around an existing inference server), and **general-purpose job queues adapted for LLM workloads** (Celery, BullMQ, SLURM, etc.).

For a single-machine, overnight batch-processing use case on AMD consumer GPUs, the most pragmatic approach is **either a lightweight filesystem-based queue processor (a shell script with `flock` and systemd timers) or vLLM's built-in offline batch runner**. The filesystem approach matches the existing plan in `PLAN.md` and is the lowest-dependency option. vLLM's offline batch API (`vllm run-batch` using the OpenAI batch JSONL format) offers higher throughput via continuous batching but requires running the vLLM server, which adds operational complexity.

Dedicated LLM inference engines (vLLM, SGLang, Aphrodite, TGI, LMDeploy) all implement continuous batching with built-in request queues and slots. These are optimized for **concurrent serving**—handling many simultaneous users with low latency—not for **sequential overnight batch processing**. Their queuing mechanisms (FIFO slots, `max-num-seqs`, `max-waiting-tokens`) are designed to maximize GPU utilization during live serving, not to persist jobs across machine reboots or schedule them for a specific time window.

General-purpose job queues (Celery, BullMQ, SLURM) are overkill for a single-machine, single-GPU scenario. They introduce dependencies (Redis, RabbitMQ, database backends), serialization overhead, and operational complexity that are not justified when the queue can be the filesystem and the scheduler can be systemd. However, they become valuable if the system ever scales to multiple machines or requires features like retry policies, priority queues, or web dashboards.

**Key finding for the user's specific hardware**: vLLM now has first-class AMD ROCm support with a dedicated CI pipeline (93% pass rate as of January 2026), TRITON_ATTN backend for RDNA3 consumer GPUs, and pre-built wheels for ROCm 7.x. Aphrodite Engine also supports ROCm 6.1+ with NAVI GPU build options. Both are viable alternatives to Ollama for batch workloads on the RX 7900 XT, offering significantly higher throughput via continuous batching. However, Ollama remains the simplest option if throughput is not the bottleneck—which it likely is not for overnight batch processing where 8 hours of GPU time is available.

## 2. Relation to Primary Question

The primary question asks what architectures exist for running bulk LLM inference on consumer GPUs overnight. This sub-topic's findings establish that dedicated batch-queue-for-LLM projects are rare; most solutions either leverage the inference engine's built-in request queue (vLLM, llama.cpp, Ollama) for live serving concurrency, or they wrap the engine in a general-purpose job scheduler. For single-GPU overnight use, a filesystem-based queue with systemd—as already planned—is the correct level of complexity, and the inference engine choice (Ollama vs. vLLM) matters more for throughput and model compatibility than for queue management.

## 3. Source Evaluation

### Source 1: llama.cpp Server Documentation (GitHub ggml-org/llama.cpp, `tools/server/README.md`)
- **URL**: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- **Credibility**: Primary source. Official documentation for the most widely used GGUF inference server. Maintained by the core ggml team. Updated within 19 hours of research.
- **Weighting**: High. Authoritative on llama.cpp's slot/queue architecture. Directly describes the `--parallel`, `--cont-batching`, and slot mechanics.

### Source 2: vLLM Official Documentation (`docs.vllm.ai`)
- **URL**: https://docs.vllm.ai/en/latest/serving/offline_inference/
- **Credibility**: Primary source. Official documentation for the leading open-source LLM inference engine (77k GitHub stars, Apache 2.0). Maintained by the vLLM project at UC Berkeley and the broader community.
- **Weighting**: High. Authoritative on batch/offline inference APIs, OpenAI batch format support, and ROCm platform support.

### Source 3: Aphrodite Engine GitHub Repository
- **URL**: https://github.com/aphrodite-engine/aphrodite-engine
- **Credibility**: Primary source. Open-source inference engine (AGPL-3.0, 1,733 stars) built on vLLM. Active development as of May 2026. Powers PygmalionAI's production infrastructure.
- **Weighting**: Medium-High. Relevant for its explicit AMD ROCm support for consumer GPUs (NAVI build flag) and OpenAI Batch API integration. Smaller community than vLLM but actively maintained.

### Source 4: SGLang Official Repository and LMSYS Blog
- **URL**: https://github.com/sgl-project/sglang; https://www.lmsys.org/blog/2024-12-04-sglang-v0-4/
- **Credibility**: Primary sources. SGLang is hosted under LMSYS, a non-profit research organization. The v0.4 release blog is an official project announcement. The project reports 400,000+ GPU deployments.
- **Weighting**: Medium-High. SGLang's zero-overhead batch scheduler and cache-aware scheduling are state-of-the-art, but the project is more relevant for multi-GPU serving clusters than single-consumer-GPU batch processing.

### Source 5: TGI (Text Generation Inference) Official Documentation
- **URL**: https://huggingface.co/docs/text-generation-inference/en/index
- **Credibility**: Primary source. Hugging Face's production-grade inference engine. Well-maintained, widely deployed.
- **Weighting**: Medium. TGI's continuous batching and queue architecture are well-designed, but TGI does not officially support AMD consumer GPUs—it targets NVIDIA datacenter GPUs and some AMD Instinct cards. Limited applicability for the user's RX 7900 XT.

### Source 6: LMDeploy Official Documentation and GitHub
- **URL**: https://github.com/InternLM/lmdeploy; https://lmdeploy.readthedocs.io/en/latest/
- **Credibility**: Primary source. Developed by Shanghai AI Laboratory (InternLM team). Active development, v0.12.3 as of April 2026.
- **Weighting**: Medium. LMDeploy's "persistent batch" architecture claims 1.8x throughput over vLLM, but its primary target is NVIDIA GPUs and Ascend NPUs. AMD ROCm support is not prominently documented.

### Source 7: Ollama Batch Cluster (robert-mcdermott/ollama-batch-cluster)
- **URL**: https://github.com/robert-mcdermott/ollama-batch-cluster
- **Credibility**: Secondary source. Community project (34 stars, 11 forks) by an individual developer. Demonstrated on 28-GPU clusters with 90%+ utilization sustained over 24 hours.
- **Weighting**: Medium. The project is directly relevant—it solves exactly the batch-processing-with-Ollama problem—but as a small community project it carries less institutional weight. The architectural pattern (multiple Ollama instances per GPU, JSONL prompt files, TOML config) is well-documented and reproducible.

### Source 8: "Queueing, Predictions, and LLMs: Challenges and Open Problems" (arXiv:2503.07545)
- **URL**: https://arxiv.org/abs/2503.07545
- **Credibility**: Primary academic source. Peer-reviewed publication in *Stochastic Systems* (INFORMS). Authored by academic researchers.
- **Weighting**: High for theoretical foundations. Identifies fundamental challenges: variable inference times, dynamic KV cache memory constraints, divergent interactive vs. batch latency requirements. Not implementation-specific.

### Source 9: AMD ROCm vLLM Blog Posts (AMD, vLLM Project)
- **URL**: https://rocm.blogs.amd.com/software-tools-optimization/vllmv1-rocm-llm/README.html; https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html
- **Credibility**: Primary sources from AMD and the vLLM project. Official technical communications.
- **Weighting**: High for AMD-specific deployment guidance. Confirms first-class ROCm CI, TRITON_ATTN backend for RDNA3 consumer GPUs, and chunked-prefill scheduler performance.

### Source 10: Markaicode and Medium Articles on Celery/Redis/BullMQ for AI
- **URL**: https://markaicode.com/redis-celery-long-running-ai-jobs/; https://markaicode.com/redis-job-queue-bullmq/
- **Credibility**: Secondary sources. Technical blog posts from a programming tutorial site. Authors are individual developers, not institutionally verified.
- **Weighting**: Low-Medium. Useful for practical patterns and benchmark numbers, but claims should be verified against primary documentation. The architectural patterns described (FastAPI → Redis → Celery Worker → LLM) are well-established and independently verifiable.

### Source 11: "Inside the vLLM Inference Server" (The New Stack)
- **URL**: https://thenewstack.io/inside-the-vllm-inference-server-from-prompt-to-response/
- **Credibility**: Secondary source. Established tech publication. Provides accessible technical explanations of vLLM internals.
- **Weighting**: Medium. Good explanatory content but not a primary source for implementation details.

### Source 12: SLURM for AI Workloads Guide (Spheron Blog)
- **URL**: https://www.spheron.network/blog/slurm-gpu-cloud-ai-training-hpc-scheduler-guide/
- **Credibility**: Secondary source. Cloud GPU provider's technical guide. Has commercial interest in promoting GPU cloud usage but provides accurate technical configuration details.
- **Weighting**: Medium. Practical SLURM configuration guidance is useful, but the multi-node HPC focus makes it less relevant for single-machine consumer GPU setups.

## 4. Conclusions

### 4.1 The Existing Plan Is Already the Right Architecture

The filesystem-based queue (`~/batch-queue/{pending,running,done,failed}/`) with `flock`, systemd timers, and a Fish shell processor is the simplest correct solution for the stated use case. This conclusion is reinforced, not challenged, by the survey of existing systems:

- **No dedicated "LLM batch queue" project exists that is simpler than the filesystem approach.** The inference engines provide request-level queues optimized for live serving concurrency, not job-level queues with persistence, timing, and result collection.
- **General-purpose job queues add unwarranted complexity.** Celery requires Redis/RabbitMQ and Python. BullMQ requires Redis and Node.js. SLURM requires a controller daemon and is designed for multi-node HPC clusters. For a single machine running sequential overnight jobs, the filesystem is a perfectly adequate queue.
- **Systemd user timers are the correct scheduler.** They are built into NixOS, require no additional dependencies, and provide `RuntimeMaxSec` for safety timeouts. This is simpler and more reliable than cron, Celery Beat, or any external scheduler.

### 4.2 Inference Engine Selection Matters More Than Queue Architecture

The choice of inference backend (Ollama vs. vLLM vs. llama.cpp server) has a larger impact on throughput and reliability than the queue mechanism:

| Engine | AMD ROCm Support | Batch Throughput | Queue Model | Best For |
|--------|-----------------|-----------------|-------------|----------|
| **Ollama** | Yes (ROCm, built-in) | Low (sequential by default) | Built-in FIFO, `OLLAMA_NUM_PARALLEL`/`OLLAMA_MAX_QUEUE` | Simplicity, already running |
| **vLLM** | Yes (first-class as of 2026) | High (continuous batching, chunked prefill) | Internal slot queue, `max-num-seqs`, `vllm run-batch` CLI | Throughput, OpenAI batch format |
| **llama.cpp server** | Yes (ROCm via GGML) | Medium (continuous batching, `--parallel` slots) | Slot-based FIFO, `--parallel`/`--cont-batching` | Lightweight, GGUF model support |
| **Aphrodite** | Yes (ROCm 6.1+, NAVI build flag) | High (vLLM-derived) | Same as vLLM + OpenAI Batch API | OpenAI API compatibility + ROCm |
| **SGLang** | Limited (primarily NVIDIA/AMD Instinct) | Highest (zero-overhead scheduler) | Cache-aware priority scheduling | Multi-GPU serving clusters |
| **TGI** | No (NVIDIA + AMD Instinct only) | High | Continuous batching, `max-concurrent-requests` | Production HF ecosystem |
| **LMDeploy** | Limited (NVIDIA + Ascend focus) | Very High (1.8x vs vLLM claimed) | Persistent batch with N slots | NVIDIA GPU deployments |

### 4.3 Recommended Architecture: Two-Tier

**Tier 1 (current plan — for agent sessions)**: Filesystem queue + systemd + Ollama's existing endpoint. This handles OMP agent sessions where each job is a full agent invocation with tool access, file I/O, and potentially long runtimes. The `omp` CLI approach is correct because it gives the agent a full working environment.

**Tier 2 (optional enhancement — for bulk prompt completion)**: vLLM's `run-batch` command for high-throughput prompt processing when agent tool access is not needed. This would be useful for bulk data extraction, classification, or summarization jobs where hundreds of prompts need processing. The OpenAI batch JSONL format is well-supported and results are machine-readable.

### 4.4 Non-Obvious Angles

1. **Ollama's sequential default is a feature, not a bug, for overnight batch.** Ollama processes requests one at a time by default (`OLLAMA_NUM_PARALLEL=1`). For overnight processing where latency is irrelevant and you want to avoid VRAM fragmentation across parallel contexts, this is actually desirable. Increasing parallelism would only help if there is idle GPU capacity during single-request processing, which is unlikely with large models on consumer GPUs.

2. **vLLM's `run-batch` command is designed for exactly this use case but has an important caveat.** It processes a JSONL file of prompts through the vLLM engine with continuous batching for maximum throughput, and outputs a JSONL file of results. However, it requires the vLLM server to already be running and the model loaded. For overnight batch, this means either keeping vLLM running 24/7 (wasting VRAM during the day) or scripting a start-server → run-batch → stop-server sequence, which adds complexity.

3. **The ollama-batch-cluster project's key insight is GPU pinning.** The author found that a single Ollama instance with `OLLAMA_SCHED_SPREAD` could not fully utilize multiple GPUs. By running one Ollama instance per GPU pinned via `CUDA_VISIBLE_DEVICES` (or the ROCm equivalent `ROCR_VISIBLE_DEVICES`), utilization jumped to 90%+. For the user's two-machine setup, this pattern would apply if both machines are available simultaneously.

4. **Continuous batching is largely irrelevant for sequential overnight processing.** Continuous batching maximizes throughput by interleaving tokens from multiple concurrent requests. If jobs run one at a time (as the plan specifies), there is nothing to interleave. The throughput benefit of engines like vLLM and SGLang comes from concurrent request handling, not from single-request optimization. The plan's sequential approach is correct for single-GPU overnight use.

5. **AMD ROCm support has reached a tipping point in 2026.** vLLM's dedicated ROCm CI pipeline (93% pass rate), the TRITON_ATTN backend for RDNA3 consumer GPUs, and pre-built ROCm wheels mean that vLLM on the RX 7900 XT is now a viable production option—not an experimental one. The user should consider testing vLLM as an alternative backend, particularly if Ollama's throughput becomes a bottleneck for large batch jobs.

### 4.5 What Not to Build

- **Do not introduce Redis, RabbitMQ, or any message broker for a single-machine queue.** The filesystem is simpler, more reliable (no broker process to crash), and easier to debug (just `cat` the prompt files).
- **Do not build a web dashboard in v1.** The `batch-status` Fish function in the plan is the right level of visibility.
- **Do not attempt distributed processing across office+arch machines in v1.** The arch machine is currently unreachable. Multi-machine coordination adds significant complexity (network reliability, partial failure handling, result aggregation) that is not justified for v1.

## 5. Bibliography

AMD. (2026, February 27). Beyond porting: How vLLM orchestrates high-performance inference on AMD ROCm. *vLLM Blog*. https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html

AMD. (2026). vLLM V1 meets AMD Instinct GPUs: A new era for LLM inference performance. *ROCm Blogs*. https://rocm.blogs.amd.com/software-tools-optimization/vllmv1-rocm-llm/README.html

Anyscale. (2026). Understand LLM batch inference basics. *Anyscale Documentation*. https://docs.anyscale.com/llm/batch-inference/llm-batch-inference-basics

Aphrodite Engine Project. (2026). Aphrodite Engine documentation. https://aphrodite.pygmalion.chat/

Aphrodite Engine Project. (2026). *aphrodite-engine* [Source code]. GitHub. https://github.com/aphrodite-engine/aphrodite-engine

Glukhov, R. (2025, May). How Ollama handles parallel requests. *Personal Site and Technical Blog*. https://www.glukhov.org/post/2025/05/how-ollama-handles-parallel-requests/

Hugging Face. (2026). Text Generation Inference (TGI) documentation. https://huggingface.co/docs/text-generation-inference/en/index

Hugging Face. (2026). Text Generation Inference architecture. https://huggingface.co/docs/text-generation-inference/en/architecture

LMSYS Organization. (2024, December 4). SGLang v0.4: Zero-overhead batch scheduler, cache-aware load balancer, faster structured outputs. *LMSYS Blog*. https://www.lmsys.org/blog/2024-12-04-sglang-v0-4/

Llama.cpp Project. (2026). llama.cpp server README. GitHub. https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

Markaicode. (2026, March 10). Handling long-running AI jobs with Redis and Celery: Queue, track, and recover. https://markaicode.com/redis-celery-long-running-ai-jobs/

Markaicode. (2026, March 4). Reliable job queue with BullMQ and Redis: AI task processing with retries and priority. https://markaicode.com/redis-job-queue-bullmq/

Markaicode. (2026, March 12). Configure Ollama concurrent requests: Parallel inference setup 2026. https://markaicode.com/ollama-concurrent-requests-parallel-inference/

McDermott, R. (2024). *ollama-batch-cluster* [Source code]. GitHub. https://github.com/robert-mcdermott/ollama-batch-cluster

McDermott, R. (2024, November 25). Large scale batch processing with Ollama. *Medium*. https://robert-mcdermott.medium.com/large-scale-batch-processing-with-ollama-1e180533fb8a

Programming Helper Tech. (2026, January 28). Celery 2026: Python distributed task queue, Redis, RabbitMQ, and the 5.6 recovery release. https://www.programming-helper.com/tech/celery-2026-python-distributed-task-queue-redis-rabbitmq

Promptsicle. (2026, April 12). Optimizing llama-server throughput with batching. https://promptsicle.com/tips/boosting-llama-server-performance-with-batch-settings/

Schultz, N. R. A. (2024). *ollama-batch-requests* [Source code]. GitHub. https://github.com/nathan-r-a-schultz/ollama-batch-requests

SGLang Project. (2026). *sglang* [Source code]. GitHub. https://github.com/sgl-project/sglang

Shanghai AI Laboratory. (2026). LMDeploy documentation. https://lmdeploy.readthedocs.io/en/latest/

Shanghai AI Laboratory. (2026). *lmdeploy* [Source code]. GitHub. https://github.com/InternLM/lmdeploy

Spheron Network. (2026). Slurm for AI workloads on GPU cloud: HPC-style job scheduling for LLM training and batch inference (2026 guide). https://www.spheron.network/blog/slurm-gpu-cloud-ai-training-hpc-scheduler-guide/

The New Stack. (2026). Inside the vLLM inference server: From prompt to response. https://thenewstack.io/inside-the-vllm-inference-server-from-prompt-to-response/

vLLM Project. (2026). Offline inference. *vLLM Documentation*. https://docs.vllm.ai/en/latest/serving/offline_inference/

vLLM Project. (2026). vLLM CLI reference: run-batch. https://docs.vllm.ai/en/latest/cli/run-batch/

vLLM Project. (2026). GPU installation. *vLLM Documentation*. https://docs.vllm.ai/en/latest/getting_started/installation/gpu/

Zhu, T., Shah, D., & Wierman, A. (2025). Queueing, predictions, and large language models: Challenges and open problems. *Stochastic Systems*. https://arxiv.org/abs/2503.07545
