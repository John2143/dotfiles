# Ollama Batch and Concurrent Inference Research Report

## 1. Summary

Ollama provides a robust HTTP API for LLM inference with built-in support for concurrent request handling, FIFO queuing, and internal prompt-evaluation batching — all configurable via environment variables. The two primary inference endpoints are `/api/generate` (single-turn completion) and `/api/chat` (multi-turn conversation). For overnight batch processing of independent research prompts, `/api/generate` with `stream: false` is the simpler and more appropriate endpoint: it has no message-history overhead, each request is stateless and self-contained, and results are returned as a single JSON object rather than a token stream.

Ollama's concurrency is governed by three environment variables: `OLLAMA_NUM_PARALLEL` (max parallel requests per loaded model, defaults to auto-select 1 or 4 based on available memory), `OLLAMA_MAX_QUEUE` (max queued requests before returning HTTP 503, defaults to 512), and `OLLAMA_MAX_LOADED_MODELS` (max concurrently loaded models, defaults to 3×GPU count). By default, Ollama ships conservatively — parallel requests are effectively disabled (`OLLAMA_NUM_PARALLEL=1` on memory-constrained systems), and requests are processed sequentially in FIFO order. This conservative default is well-suited to a single-GPU home-lab setup where the user processes one agent session at a time overnight: sequential processing avoids KV-cache memory amplification (each parallel slot multiplies effective context length), eliminates GPU memory contention, and maximizes per-request throughput.

For users who want to accelerate batch throughput by running multiple concurrent jobs on a single GPU, raising `OLLAMA_NUM_PARALLEL` to 2–4 is viable if VRAM headroom exists. At `OLLAMA_NUM_PARALLEL=4`, per-request latency increases 20–40% but total throughput increases 3–4×. The internal `num_batch` parameter (default 512, inherited from llama.cpp) controls prompt-evaluation batch size and can be tuned via the API's `options` field; raising it to 1024–2048 can improve GPU utilization without affecting per-request latency, at a cost of 20–40% additional peak VRAM usage during the forward pass. For the user's RX 7900 XT (24GB) running qwen3.6:27b (~17.4GB), there is approximately 6–7GB of VRAM headroom — enough to experiment with `OLLAMA_NUM_PARALLEL=2` and `num_batch=1024`, but likely insufficient for 4 parallel slots without risking OOM.

Practical limits for a single-GPU setup with a 27B model at ~4K context: sequential processing is the safe default, and 2-way parallelism is the practical ceiling. A well-known community project, `ollama-batch-cluster` by Robert McDermott, demonstrated that per-GPU Ollama instances (pinned via `CUDA_VISIBLE_DEVICES`/`ROCR_VISIBLE_DEVICES`) with client-side load balancing achieve substantially better GPU utilization than a single Ollama server spanning multiple GPUs — but this is a multi-GPU optimization that does not apply to a single-GPU setup.

## 2. Relation to Primary Question

Ollama's sequential default (`OLLAMA_NUM_PARALLEL=1`) is well-aligned with overnight batch processing on a single consumer GPU: it avoids VRAM contention, guarantees predictable per-job memory usage, and the built-in FIFO queue (default depth 512) absorbs submitted requests without dropping them. For the user's specific use case — queuing OMP agent prompts during the day, running them sequentially overnight — no concurrency tuning is needed; the safest and most reliable approach is to leave `OLLAMA_NUM_PARALLEL=1` and run a single job at a time via a queue-processor script, which is exactly what the existing plan proposes.

## 3. Source Evaluation

### Source 1: Ollama Official FAQ
- **URL:** https://docs.ollama.com/faq
- **Title:** Ollama FAQ
- **Assessment:** **Primary source, official, verified.** This is the authoritative documentation maintained by the Ollama project. It defines the behavior of all server-side environment variables (`OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_QUEUE`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_CONTEXT_LENGTH`) and the concurrent-request handling model. Recency: continuously updated; latest version accessed May 2026. Weight: highest — this is the ground truth for Ollama server behavior.

### Source 2: Ollama API Reference (ReadTheDocs)
- **URL:** https://ollama.readthedocs.io/en/api/
- **Title:** Ollama API Reference
- **Assessment:** **Primary source, official, verified.** Documents the `/api/generate` and `/api/chat` endpoints, including all parameters (`model`, `prompt`, `stream`, `keep_alive`, `options`, `raw`, `context`, `format`). The readthedocs version is slightly older than the docs.ollama.com version (context-window default listed as 2048 vs. 4096), but endpoint definitions are stable. Weight: high for API semantics; cross-referenced with official docs for defaults.

### Source 3: Rost Glukhov — "How Ollama Handles Parallel Requests"
- **URL:** https://www.glukhov.org/llm-performance/ollama/how-ollama-handles-parallel-requests/
- **Title:** How Ollama Handles Parallel Requests
- **Assessment:** **Secondary source, technical blog, unverified author but well-referenced.** Glukhov's article is a detailed technical explainer that synthesizes official docs, source-code inspection, and empirical testing. It provides practical tuning recipes and performance trade-off data (e.g., 3–4× throughput increase at `OLLAMA_NUM_PARALLEL=4` with 20–40% latency penalty). The article references official Ollama documentation and links to related performance benchmarks. Weight: medium-high — useful for practical guidance, but all claims are cross-verifiable against primary sources.

### Source 4: EastonDev Blog — "Ollama Performance Optimization"
- **URL:** https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/
- **Title:** Ollama Performance Optimization: Complete Guide to Quantization, Batch Processing, and Memory Tuning
- **Assessment:** **Secondary source, technical blog, unverified author, recent (April 2026).** Provides empirical `num_batch` benchmarks (118% throughput improvement at `num_batch=2048` vs 512, with 2.2GB additional VRAM cost) and hardware-specific recommendations (RTX 3080/4090). Claims are specific and falsifiable but not peer-reviewed. Weight: medium — useful for parameter guidance, but claims are single-data-point anecdotes.

### Source 5: Robert McDermott — "ollama-batch-cluster" (GitHub)
- **URL:** https://github.com/robert-mcdermott/ollama-batch-cluster
- **Title:** ollama-batch-cluster: Large Scale Batch Processing with Ollama
- **Assessment:** **Primary source, verified author (Robert McDermott), demonstrated results.** An open-source project with documented performance results from a 28-GPU cluster. Key finding: a single Ollama instance with `OLLAMA_SCHED_SPREAD` across multiple GPUs achieved only ~25% per-GPU utilization; running one Ollama instance per GPU (pinned via `CUDA_VISIBLE_DEVICES`) with client-side load balancing achieved >90% utilization. This is directly relevant for multi-GPU setups but does not apply to single-GPU scenarios. Weight: high for multi-GPU scaling findings; low relevance for the user's single-GPU use case.

### Source 6: Markaicode — "Configure Ollama Concurrent Requests"
- **URL:** https://markaicode.com/ollama-concurrent-requests-parallel-inference/
- **Title:** Configure Ollama Concurrent Requests: Parallel Inference Setup 2026
- **Assessment:** **Secondary source, tutorial blog, unverified author, recent (March 2026).** Provides clear explanations of KV-cache mechanics and per-slot memory consumption. States that "Ollama concurrent requests are disabled out of the box" and documents the memory scaling formula (OLLAMA_NUM_PARALLEL × OLLAMA_CONTEXT_LENGTH). Weight: low-medium — accessible explanations but no original research; all key claims are verifiable against the official FAQ.

### Source 7: Ollama GitHub Issue #11277 — "Parallel Computing Support"
- **URL:** https://github.com/ollama/ollama/issues/11277
- **Title:** Parallel Computing Support for Concurrent Ollama Requests (Issue #11277)
- **Assessment:** **Primary source, official project repository, verified.** A user-reported issue about degraded performance with concurrent Python clients. The single official response confirms that `OLLAMA_NUM_PARALLEL` must be explicitly set. The issue was closed as "feature request, needs more info." Weight: medium — confirms that default serial behavior is a known characteristic, not a bug.

### Source 8: Ollama GitHub Issue #1800 — "OOM errors for large context models"
- **URL:** https://github.com/ollama/ollama/issues/1800
- **Title:** OOM errors for large context models can be solved by reducing 'num_batch' (Issue #1800)
- **Assessment:** **Primary source, official project repository, verified.** Confirms that `num_batch` defaults to 512 (inherited from llama.cpp) and documents the `>=32` minimum for cuBLAS kernel usage. Weight: medium — useful for validating `num_batch` behavior and defaults.

### Source 9: Ollama readthedocs.io FAQ
- **URL:** https://ollama.readthedocs.io/en/faq/
- **Title:** Ollama FAQ (ReadTheDocs mirror)
- **Assessment:** **Primary source, official documentation mirror, verified.** Contains the full concurrent-request handling documentation including the exact text of the concurrency section. Slightly older than docs.ollama.com in some defaults (context: 2048 vs. 4096). Weight: high — authoritative for concurrency model details.

## 4. Conclusions

### 4.1 Sequential processing is the correct default for the user's use case

For overnight batch processing of OMP agent sessions (one prompt → one full agent run → results), sequential processing (`OLLAMA_NUM_PARALLEL=1`) is the correct and safest configuration. Each agent session is a long-running, context-heavy task (potentially dozens of tool calls with accumulating context). Running them sequentially avoids:
- KV-cache memory amplification (each parallel slot multiplies effective context by the number of concurrent requests)
- GPU compute contention between concurrent agent sessions
- Risk of OOM crashes from accumulated context across parallel sessions

### 4.2 The `/api/generate` endpoint is the right choice for the queue processor

The plan's proposed `omp -p "$(cat prompt)"` approach already uses the generate path. For the queue processor that feeds prompts to Ollama:
- Use `/api/generate` with `stream: false` for clean, single-response results
- Set `keep_alive` to a high value (e.g., `24h` or `-1`) so the model stays loaded between jobs
- If not set globally via `OLLAMA_KEEP_ALIVE`, set it per-request

### 4.3 Recommended Ollama server configuration for batch overnight use

Based on the user's hardware (RX 7900 XT 24GB, qwen3.6:27b ~17.4GB VRAM):

```
OLLAMA_NUM_PARALLEL=1        # Safe default for long-running agent sessions
OLLAMA_MAX_QUEUE=512          # Default is fine; more than enough for overnight queue
OLLAMA_KEEP_ALIVE=-1          # Keep model loaded indefinitely — no reload penalty between jobs
OLLAMA_MAX_LOADED_MODELS=1    # Only load the target model; avoid VRAM fragmentation
OLLAMA_CONTEXT_LENGTH=4096    # Default; increase only if agent sessions need >4K context
```

These settings should be configured in the Ollama systemd service (via `Environment=` directives in the override file or NixOS module).

### 4.4 VRAM headroom analysis

With qwen3.6:27b consuming ~17.4GB of the 24GB VRAM pool, approximately 6.6GB is available for KV-cache. At the default 4K context, a single parallel slot's KV-cache is well within this budget. Two parallel slots at 4K context each (effective 8K context) are borderline — likely workable but should be tested. Four slots would require ~4× the KV-cache memory and would almost certainly OOM. This reinforces the sequential-processing recommendation.

### 4.5 The `num_batch` parameter can be tuned for prompt-evaluation throughput

Even with sequential request processing (`OLLAMA_NUM_PARALLEL=1`), the internal `num_batch` parameter (tokens processed per forward pass during prompt evaluation) can be increased to improve GPU utilization. The default of 512 is conservative. Increasing to 1024 would consume an additional ~2GB peak VRAM during prompt evaluation but would not affect per-token generation speed. Given the 6.6GB headroom, `num_batch=1024` is a safe optimization. This can be set per-request via the API `options` field or globally in the Modelfile.

### 4.6 Multi-GPU is not a v1 concern

The ollama-batch-cluster findings — that per-GPU Ollama instances outperform a single instance across multiple GPUs — are relevant only if the user later adds GPU capacity (e.g., bringing the arch machine online simultaneously). For the current single-GPU office machine, this is not actionable.

### 4.7 No built-in Ollama batch mode exists

Ollama does not have a dedicated "batch mode" or "job queue" endpoint. It is a stateless HTTP server. The queue-processor pattern proposed in the existing plan — a script that iterates over pending prompts, submits them sequentially to Ollama's `/api/generate`, and collects results — is the correct architecture. Ollama's role is purely as the inference backend; all scheduling, queuing, and result collection must be implemented externally.

### 4.8 The existing plan is architecturally sound

The proposed architecture (fish-function enqueue → filesystem-based queue directory → systemd timer → sequential processor script → results collection) aligns with Ollama's design and capabilities. The only recommended additions:
- Set `OLLAMA_KEEP_ALIVE=-1` (or `24h`) so the model is not unloaded between overnight jobs
- Consider setting `num_batch=1024` via the API `options` for faster prompt evaluation
- Add a `keep_alive` parameter to the API call in the processor script to prevent mid-batch model unloading

## 5. Bibliography

Glukhov, R. (2025, May). *How Ollama handles parallel requests*. Rost Glukhov | Personal site and technical blog. https://www.glukhov.org/llm-performance/ollama/how-ollama-handles-parallel-requests/

Markaicode. (2026, March 12). *Configure Ollama concurrent requests: Parallel inference setup 2026*. https://markaicode.com/ollama-concurrent-requests-parallel-inference/

McDermott, R. (2024). *ollama-batch-cluster: Large scale batch processing with Ollama* [Source code]. GitHub. https://github.com/robert-mcdermott/ollama-batch-cluster

Ollama. (n.d.). *API reference*. Ollama Documentation. https://ollama.readthedocs.io/en/api/

Ollama. (n.d.). *FAQ*. Ollama Documentation. https://docs.ollama.com/faq

Ollama. (n.d.). *FAQ*. Ollama English Documentation. https://ollama.readthedocs.io/en/faq/

Ollama. (2024, January 5). *OOM errors for large context models can be solved by reducing 'num_batch' down from the default of 512* [Issue #1800]. GitHub. https://github.com/ollama/ollama/issues/1800

Ollama. (2025, July 2). *Parallel computing support for concurrent Ollama requests* [Issue #11277]. GitHub. https://github.com/ollama/ollama/issues/11277

EastonDev Blog. (2026, April 10). *Ollama performance optimization: Complete guide to quantization, batch processing, and memory tuning*. https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/
