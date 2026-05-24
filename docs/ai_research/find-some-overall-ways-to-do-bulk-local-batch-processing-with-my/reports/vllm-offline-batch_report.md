# vLLM Offline and Batch Inference — Research Report

## 1. Summary

vLLM provides two distinct paths for batch inference on consumer AMD GPUs: **offline batch mode** (`LLM.generate()` / `LLM.chat()`) and **OpenAI-compatible server mode** (`vllm serve`). Both benefit from the same underlying engine optimizations — continuous batching with PagedAttention, iteration-level scheduling, and memory-efficient KV cache management — which deliver 3–5× throughput improvement over naive HuggingFace pipelines.

Offline mode accepts a list of prompts, automatically batches them considering memory constraints, and returns all outputs in one call. It does not apply chat templates automatically (manual tokenizer call needed, or use `LLM.chat()` with message lists). Server mode exposes standard `/v1/chat/completions` and `/v1/completions` endpoints, making it a drop-in replacement for any OpenAI-compatible client — including agent harnesses that expect tool/function calling and structured output APIs.

For AMD ROCm on the RX 7900 XT specifically, vLLM support has matured dramatically. As of January 2026 (v0.14.0+), AMD ROCm is a "first-class platform": 93% CI pass rate (up from 37% in November 2025), official prebuilt wheels (`vllm==0.14.0+rocm700`), and prebuilt Docker images (`vllm/vllm-openai-rocm`). The ROCM_AITER_FA attention backend delivers 1.2–4.4× throughput on Instinct GPUs through three-path routing (decode/prefill/extend). On consumer RDNA3 cards (RX 7900 series), the `TRITON_ATTN` and `ROCM_ATTN` backends are the primary options, as AITER primitives are not available. Setup friction is still higher than NVIDIA (manual ROCm/HIP driver setup), but the WSL-only era is over — native Linux is fully supported.

For the user's overnight batch queue use case, **server mode is the better architectural fit for agent harness integration** because the agent harness (OMP) already speaks OpenAI-compatible HTTP. Offline mode is simpler for pure text-completion batch jobs but requires writing a Python wrapper script. The `vllm run-batch` CLI offers a middle ground: it reads prompts as JSON lines from stdin or a file and processes them without a persistent server, potentially useful for simple queue-to-file pipelines.

## 2. Relation to Primary Question

vLLM's offline batch mode is a strong candidate for the overnight processing engine in a batch queue architecture: it can efficiently process a list of queued prompts in a single Python invocation with automatic memory-aware batching. However, if the agent harness (OMP) needs tool calling, streaming, or structured output during batch jobs, the OpenAI-compatible server mode is the correct choice — it fully supports these APIs while still benefiting from continuous batching, and the existing NixOS vLLM module already provides a ROCm-enabled container configuration.

## 3. Source Evaluation

### Primary Sources

**Source 1: vLLM Official Documentation — Offline Inference**
- URL: https://docs.vllm.ai/en/stable/serving/offline_inference/
- Credibility: **Primary. Official project documentation.** Maintained by the vLLM project (Linux Foundation). Continuously updated; current as of v0.18.x (May 2026).
- Weight: Highest. This is the authoritative reference for API behavior, capabilities, and limitations. All API claims are verified here.

**Source 2: vLLM Official Documentation — Quickstart**
- URL: https://docs.vllm.ai/en/stable/getting_started/quickstart/
- Credibility: **Primary. Official project documentation.** Contains canonical code examples for both offline and server modes. Explicitly documents the `LLM.chat()` convenience method and the chat template caveat for `LLM.generate()`.
- Weight: Highest. Defines the intended usage patterns.

**Source 3: vLLM Official Documentation — GPU Installation (AMD ROCm)**
- URL: https://docs.vllm.ai/en/stable/getting_started/installation/gpu/
- Credibility: **Primary. Official project documentation.** Lists supported AMD GPUs including "Radeon RX 7900 series (gfx1100/1101)", ROCm version requirements (6.3+), and prebuilt wheel availability (rocm700, rocm721 variants).
- Weight: Highest. Authoritative on hardware support matrix.

**Source 4: AMD ROCm Blog — "ROCm Becomes a First-Class Platform in the vLLM Ecosystem"**
- URL: https://rocm.blogs.amd.com/software-tools-optimization/vllm-omni/README.html
- Authors: Hongxia Yang, Peng Sun, Andy Luo, Tun Jian Tan, Pin Siang Tan, Kenny Roche, Gregory Shtrasberg, Doug Lehr, Simon Mo.
- Published: January 21, 2026
- Credibility: **Primary with vendor bias.** Published on AMD's official ROCm blog by named AMD and vLLM engineers. The 37%→93% CI pass rate claim and Docker image availability are verifiable facts. The "it just works" framing reflects AMD's promotional interest. vLLM maintainer Simon Mo is a co-author, lending cross-organization credibility.
- Weight: High for factual claims (CI numbers, release dates, Docker image tags). Discount the promotional tone.

**Source 5: vLLM Blog — "Beyond Porting: How vLLM Orchestrates High-Performance Inference on AMD ROCm"**
- URL: https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html
- Published: February 27, 2026
- Credibility: **Primary. Official vLLM project blog.** Deep technical article on the ROCM_AITER_FA three-path routing architecture, benchmark methodology, and attention backend comparison. Specific benchmark commands and Docker image tags are provided. Discloses that AITER backends target Instinct GPUs and that Radeon GPUs are limited to `TRITON_ATTN` and `ROCM_ATTN`.
- Weight: High. Authoritative on backend architecture and Radeon consumer GPU limitations.

**Source 6: vLLM Official Documentation — OpenAI-Compatible Server**
- URL: https://docs.vllm.ai/en/stable/serving/openai_compatible_server/
- Credibility: **Primary. Official project documentation.** Documents all supported API endpoints (Chat, Completions, Responses, tool calling, structured outputs), `--enable-auto-tool-choice` flag, and `--tool-call-parser` configuration.
- Weight: Highest for API surface and feature support claims.

### Secondary Sources

**Source 7: CraftRigs — "AMD ROCm in 2026 — Is It Finally Ready for Local LLMs?"**
- URL: https://craftrigs.com/articles/amd-rocm-local-llm-2026/
- Author: CraftRigs (site with affiliate links; editorial team not individually named)
- Published: March 29, 2026
- Credibility: **Secondary. Independent review site with affiliate marketing.** Benefits from being current (March 2026) and citing verifiable benchmarks (cprimozic.net, llm-tracker.info). The 107 tok/s on RX 7900 XTX claim references community benchmark submissions. Discloses affiliate links. The author has clear pro-AMD-for-budget-builders bias but acknowledges CUDA's continued ease-of-use advantage.
- Weight: Medium. Useful for real-world performance data and setup experience (e.g., "three days in 2024 → 40 minutes with ROCm 7.2"), but cross-reference benchmark claims with primary sources. The fine-tuning RDNA limitations analysis (Wave32 vs. Wave64 architecture mismatch) is technically specific and consistent with AMD's own documentation gap.

**Source 8: Zenn.dev (troutceremony) — "Building a Local LLM Environment with RX 7900 XTX, WSL2, ROCm, and vLLM"**
- URL: https://zenn.dev/troutceremony/articles/f1bf689b878a06?locale=en
- Published: February 10, 2026
- Credibility: **Secondary. Individual developer blog.** Provides hands-on experience with the exact GPU family (RX 7900 XTX, sibling to the user's RX 7900 XT). Notes FP8 KV cache quantization limitation on ROCm (now partially resolved in v0.16.0). Author is a practitioner, not a vendor.
- Weight: Medium. Useful for practical gotchas (quantization limitations, setup steps). Claims are specific and falsifiable. Corroborates CraftRigs' broader assessments.

**Source 9: DigitalOcean — "How to Choose the Right GPU for vLLM Inference"**
- URL: https://www.digitalocean.com/community/conceptual-articles/vllm-gpu-sizing-configuration-guide
- Published: January 12, 2026
- Credibility: **Secondary. Cloud provider documentation/guide.** Focuses on server-grade hardware sizing. Contains general tuning advice (gpu_memory_utilization, max_num_seqs, max_num_batched_tokens) applicable to any GPU.
- Weight: Medium-Low. General guidance is sound but not AMD-specific. Useful for configuration parameter explanations.

**Source 10: Compute Market — "Best AMD GPU for Local LLM Inference 2026"**
- URL: https://www.compute-market.com/blog/best-amd-gpu-local-llm-inference-2026
- Published: ~April 2026 (2 weeks ago as of report date)
- Credibility: **Secondary. GPU marketplace with buyer's guide content.** Contains affiliate links and commercial interest. Claims RX 7900 XTX runs Llama 3 70B Q4 at 14–18 tok/s on ROCm 7.2. Sources cited include Phoronix benchmarks.
- Weight: Medium-Low. Useful for current pricing context and model/GPU pairing guidance but treat performance claims as indicative.

## 4. Conclusions

### 4.1 Offline Batch Mode (`LLM.generate()` / `LLM.chat()`)

**How it works:** Initialize an `LLM` object with a model name. Call `llm.generate(prompts, sampling_params)` with a list of prompt strings, or `llm.chat(messages_list, sampling_params)` with OpenAI-format message lists. vLLM automatically batches all prompts into one efficient forward pass, considering memory constraints. Returns a list of `RequestOutput` objects.

**Key behavioral details (verified from official docs):**
- `LLM.generate()` does **not** apply chat templates. For instruct/chat models, manually apply via `tokenizer.apply_chat_template()` or use `LLM.chat()` instead.
- The LLM object loads the model into GPU memory once. All prompts in a single `generate()`/`chat()` call are batched together using continuous batching. This means: if you put 50 prompts in the list, the engine processes them concurrently within the batch, not sequentially. This is far more efficient than one-at-a-time calls.
- Sampling params can be per-prompt (pass a list matching prompt count) or global (single object applied to all).
- The `LLM` class supports `--attention-backend` for ROCm (`TRITON_ATTN`, `ROCM_ATTN`, etc.) and all standard engine config (`max_model_len`, `gpu_memory_utilization`, `max_num_seqs`).

**For overnight batch queue use:**
- A single Python script that loads the model, reads prompts from `~/batch-queue/pending/*.md`, and calls `llm.chat()` once with all prompts would be the simplest approach. No server process needed.
- **Downside:** The model stays loaded only during the script's lifetime. If you want to add prompts mid-run (e.g., queue up more during the day while processing continues), you'd need either periodic restarts or server mode.
- **Downside for agent harness:** `LLM.generate()`/`chat()` returns raw text. It does not provide tool/function calling, structured output enforcement, or streaming — all of which the OMP agent harness likely needs. The OMP tool would need to either: (a) use the offline API as a plain completion engine (losing tool calling), or (b) switch to the server API.

### 4.2 Continuous Batching — What It Actually Means

vLLM's continuous batching is the engine's core efficiency mechanism, active in **both offline and server modes.** Key mechanics:
- **Iteration-level scheduling:** The GPU processes one token per active sequence per forward pass. When any sequence finishes (emits EOS), its slot is immediately freed for a new sequence. No waiting for the full batch to complete.
- **PagedAttention:** KV cache is allocated in fixed-size pages (like OS virtual memory), eliminating memory fragmentation. This allows more concurrent sequences in the same VRAM budget.
- **Mixed prefill/decode:** In server mode, new prompt processing (prefill, compute-bound) is interleaved with ongoing token generation (decode, memory-bound) in the same batch. In offline mode with a fixed prompt list, the engine can schedule these together for maximum throughput.

**For the user's use case:** Continuous batching matters less for overnight sequential processing (where throughput optimization is secondary to correctness) and more for scenarios where multiple independent prompts could benefit from concurrent processing. If the queue contains independent research prompts, batching them together into one `LLM.generate()` call would complete faster than sequential one-at-a-time processing. But if each prompt depends on the output of the previous (unlikely for research prompts), batching doesn't help.

### 4.3 AMD ROCm Support Status

**Current status (May 2026): Production-ready for inference on RX 7900 series.**

Verified facts:
- RX 7900 XT (gfx1100) is **explicitly listed** in vLLM's supported GPU documentation.
- Prebuilt wheels: `uv pip install vllm --extra-index-url https://wheels.vllm.ai/rocm/` (ROCm 7.0, Python 3.12, glibc ≥ 2.35).
- Prebuilt Docker: `vllm/vllm-openai-rocm:v0.14.0` through `:latest` and `:nightly`.
- CI pass rate: 93% as of January 2026, with daily regression maintenance.
- Supported attention backends for RDNA3: `TRITON_ATTN` (default fallback) and `ROCM_ATTN` (legacy 2-path). The high-performance `ROCM_AITER_FA` backend requires AITER primitives only available on Instinct (CDNA3) GPUs.

**Limitations vs. NVIDIA:**
- Raw tok/s: ~10–25% slower on equivalent hardware (per community benchmarks and AMD's own CES 2026 acknowledgment).
- FP8 KV cache quantization: Was unsupported on ROCm; vLLM v0.16.0 has added initial FP8 ROCm support, but stability is not yet at NVIDIA parity.
- Setup friction: Manual ROCm/HIP driver setup required. The CraftRigs report notes ~40 minutes setup time with ROCm 7.2 (down from 3 days in 2024).
- Fine-tuning: Not supported on consumer RDNA cards (Wave32 vs. Wave64 architectural mismatch in Flash Attention CK backend; Triton workaround exists but is unofficial).
- Speculative decoding: EAGLE3 and DFlash perform poorly on AMD GPUs due to lack of optimized attention backends.
- Context length: A 64K token wall has been reported on Threadripper+AMD systems; community patches exist.

**The user's RX 7900 XT (24GB) is well-suited for vLLM inference.** The existing NixOS module (`nixos/modules/vllm.nix`) already supports `gpuBackend = "rocm"` with the correct `--device=/dev/kfd`, `--device=/dev/dri`, `--group-add=video`, and `--group-add=render` container flags. The module defaults to `vllm/vllm-openai:latest` for the image; for ROCm this should be `vllm/vllm-openai-rocm:latest`.

### 4.4 Server Mode vs. Offline Mode for Agent Harness Integration

| Factor | Offline Mode (`LLM.generate()`) | Server Mode (`vllm serve`) |
|---|---|---|
| **API surface** | Python API only (prompt list → output list) | OpenAI-compatible REST API (`/v1/chat/completions`, `/v1/completions`) |
| **Tool/function calling** | Not supported (raw text generation only) | Fully supported (`--enable-auto-tool-choice`, `--tool-call-parser`) |
| **Structured output** | Not natively supported | Supported (JSON schema enforcement via guided decoding) |
| **Streaming** | Not supported | Supported (SSE streaming) |
| **Chat templates** | Manual via tokenizer or `LLM.chat()` | Automatic (server applies model's chat template) |
| **Process model** | One-shot: load model, batch all prompts, exit | Persistent: model stays loaded, accepts requests indefinitely |
| **Concurrency** | Single process, batched internally | Multiple concurrent clients via continuous batching |
| **VRAM** | Freed when Python process exits | Occupied for server lifetime |
| **Integration with OMP** | Requires custom Python wrapper; OMP calls script | OMP can use existing OpenAI client; no custom code needed |
| **Queue integration** | Script reads files, processes, writes results | Queue system sends HTTP requests; results collected from responses |

**Recommendation for agent harness (OMP) integration:** Server mode is the clear winner. The OMP agent harness already speaks OpenAI-compatible HTTP. Running `vllm serve` with the existing NixOS module provides a persistent endpoint that the harness can call exactly as it would call Ollama today. Tool calling, structured output, and streaming all work. The model stays loaded in VRAM for the duration of the overnight batch window.

If the user prefers a simpler architecture (no persistent server), offline mode could work but would require: (a) writing a Python wrapper that loads the model, reads prompts from queue files, calls `LLM.chat()`, and writes outputs; (b) accepting the loss of tool calling and streaming; (c) accepting that each batch run has model load/unload overhead.

### 4.5 `vllm run-batch` CLI — A Middle Ground

vLLM provides a `vllm run-batch` CLI command that accepts JSON-lines input with prompts and sampling parameters. This could serve as a simpler alternative to writing a custom Python wrapper for offline inference. It reads from stdin or a file and outputs results. For a queue processor script, this means: `cat pending/*.md | vllm run-batch --model ... > results.jsonl`.

Key parameters supported: `--chat-template`, `--lora-modules`, `--trust-request-chat-template`, all standard engine config options.

**Trade-off:** Still no tool calling support. Still no streaming. But removes the need to maintain a custom Python inference script.

### 4.6 Practical Recommendations for the User's Batch Queue Architecture

1. **Use server mode for OMP integration.** Start `vllm serve` (via the existing NixOS module, switching to the ROCm image) before the batch run begins. The OMP harness calls `http://localhost:8000/v1/chat/completions` exactly as it would call Ollama. No custom inference code needed.

2. **Configure for overnight throughput, not latency.** For overnight batch processing where response time doesn't matter:
   - `--gpu-memory-utilization 0.92` (aggressive, since no other GPU workload runs overnight)
   - `--max-num-seqs 8` (higher concurrency to maximize throughput)
   - `--max-model-len 32768` (reduce from default 65536 to save VRAM for more concurrent sequences)
   - `--enable-chunked-prefill` (better GPU utilization for mixed-length prompts)
   - `--attention-backend TRITON_ATTN` (most stable for RDNA3; ROCM_ATTN as fallback)

3. **Use the ROCm Docker image.** Override `services.vllm.image` to `vllm/vllm-openai-rocm:latest` and `services.vllm.gpuBackend` to `"rocm"`. Set `VLLM_ROCM_USE_AITER=0` in `environmentVariables` since AITER is not available on RDNA3.

4. **Model choice matters.** The user's qwen3.6:27b (17.4GB) fits in the RX 7900 XT's 24GB with room for KV cache. vLLM loads models from HuggingFace in safetensors format, not GGUF. The equivalent would be `Qwen/Qwen3-30B-A3B` or a quantized variant. vLLM supports AWQ, GPTQ, and FP8 quantization formats. Quantized models reduce VRAM usage, leaving more room for KV cache and concurrent sequences.

5. **Health checks for the queue processor.** Before the queue processor starts the vLLM server, verify: (a) ROCm device is visible (`rocm-smi` or `hipInfo`), (b) model is cached locally, (c) port 8000 is free. After starting the server, poll `http://localhost:8000/health` until it returns 200 before dispatching jobs.

6. **Consider `vllm run-batch` for simple jobs.** For prompts that don't need tool calling (e.g., "summarize this paper", "analyze this data file"), `vllm run-batch` with a JSON-lines input file is simpler and avoids the persistent server footprint. A hybrid approach: use server mode for OMP agent sessions, and `vllm run-batch` for straightforward completion jobs.

7. **VRAM management.** vLLM's `gpu_memory_utilization` parameter is a hard cap — the engine will not exceed it. For the RX 7900 XT's 24GB running a 27B model at ~17.4GB (full precision), you'd want `gpu_memory_utilization=0.85` to leave ~3GB for KV cache. At 32K context with 4 concurrent sequences, KV cache can consume 2–4GB depending on model architecture. Monitor with `rocm-smi` during test runs.

## 5. Bibliography

AMD. (2026, January 21). *ROCm becomes a first-class platform in the vLLM ecosystem*. ROCm Blogs. https://rocm.blogs.amd.com/software-tools-optimization/vllm-omni/README.html

Compute Market. (2026, May). *Best AMD GPU for local LLM inference 2026 — buyer guide*. https://www.compute-market.com/blog/best-amd-gpu-local-llm-inference-2026

CraftRigs. (2026, March 29). *AMD ROCm in 2026 — Is it finally ready for local LLMs?* https://craftrigs.com/articles/amd-rocm-local-llm-2026/

DigitalOcean. (2026, January 12). *How to choose the right GPU for vLLM inference*. https://www.digitalocean.com/community/conceptual-articles/vllm-gpu-sizing-configuration-guide

troutceremony. (2026, February 10). *Building a local LLM environment with RX 7900 XTX, WSL2, ROCm, and vLLM*. Zenn. https://zenn.dev/troutceremony/articles/f1bf689b878a06?locale=en

vLLM Project. (n.d.). *GPU installation*. vLLM Documentation. Retrieved May 18, 2026, from https://docs.vllm.ai/en/stable/getting_started/installation/gpu/

vLLM Project. (n.d.). *Offline inference*. vLLM Documentation. Retrieved May 18, 2026, from https://docs.vllm.ai/en/stable/serving/offline_inference/

vLLM Project. (n.d.). *OpenAI-compatible server*. vLLM Documentation. Retrieved May 18, 2026, from https://docs.vllm.ai/en/stable/serving/openai_compatible_server/

vLLM Project. (n.d.). *Quickstart*. vLLM Documentation. Retrieved May 18, 2026, from https://docs.vllm.ai/en/stable/getting_started/quickstart/

vLLM Project. (n.d.). *vllm run-batch*. vLLM Documentation. Retrieved May 18, 2026, from https://docs.vllm.ai/en/stable/cli/run-batch/

vLLM Project. (2026, February 27). *Beyond porting: How vLLM orchestrates high-performance inference on AMD ROCm*. vLLM Blog. https://blog.vllm.ai/2026/02/27/rocm-attention-backend.html
