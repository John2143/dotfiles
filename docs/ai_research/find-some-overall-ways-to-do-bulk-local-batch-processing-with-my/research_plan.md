# Research Plan: find-some-overall-ways-to-do-bulk-local-batch-processing-with-my

## Primary Question
What are the most effective architectures, tools, and patterns for running bulk/batch LLM inference workloads on consumer-grade home GPU hardware, specifically for overnight automated processing — queuing prompts during the day, running them sequentially on local GPU(s) at night, and collecting results?

## Context
The user has a home lab with AMD GPUs (RX 7900 XT 24GB on primary "office" machine, plus a secondary "arch" machine with smaller GPU). Ollama is running via ROCm serving qwen3.6:27b (17.4GB), qwen3.6:latest/36B (23.9GB), and gemma4 (9.6GB). vLLM is configured but not running. All machines run NixOS with systemd available for scheduling. The user is in the planning phase of building a batch inference queue and wants to survey existing approaches before committing to an architecture.

## Sub-Topics

### Sub-Topic 1: Ollama Batch and Concurrent Inference
- **Slug**: ollama-batch-concurrent
- **Perspective**: none — factual survey of API capabilities
- **Report path**: reports/ollama-batch-concurrent_report.md
- **Focus**: Ollama's support for batch/concurrent requests. API endpoints (`/api/generate`, `/api/chat`), concurrent request handling, queuing behavior under load, any built-in batch modes. Practical limits for single-GPU setup. Whether Ollama's generate endpoint can handle a stream of sequential requests efficiently or if there are better patterns.

### Sub-Topic 2: vLLM Offline and Batch Inference
- **Slug**: vllm-offline-batch
- **Perspective**: none — factual survey of capabilities
- **Report path**: reports/vllm-offline-batch_report.md
- **Focus**: vLLM's batch/offline inference modes. The `LLM.generate()` API with prompt lists for true batch processing. Continuous batching for concurrent requests. AMD ROCm support status (rocm docker image, any limitations vs. NVIDIA). Suitability for overnight sequential batch processing vs. high-throughput serving. Whether the OpenAI-compatible server mode is better for agent harness integration than offline mode.

### Sub-Topic 3: Open-Source LLM Job Queue and Batch Systems
- **Slug**: llm-job-queue-systems
- **Perspective**: open-source pragmatist — prefer actively maintained, battle-tested tools; flag abandoned or experimental projects
- **Report path**: reports/llm-job-queue-systems_report.md
- **Focus**: Existing systems purpose-built for queuing and processing LLM inference jobs. Candidates: llama.cpp server's built-in queue/slots, Aphrodite Engine, text-generation-inference (TGI), LMDeploy, LocalAI, Harbor, Ollama-Scale, any dedicated "LLM batch queue" or "LLM job scheduler" projects. Also evaluate general-purpose job queues (Celery, BullMQ, RabbitMQ, Redis+PGQ) adapted for LLM workloads and whether the adaptation overhead is worth it.

### Sub-Topic 4: Hardware and Infrastructure Patterns for Overnight GPU Batch
- **Slug**: hardware-infra-patterns
- **Perspective**: AMD ROCm home-lab operator — surface AMD-specific concerns (VRAM management, driver stability, thermal behavior) that differ from the NVIDIA-centric advice dominating most forums
- **Report path**: reports/hardware-infra-patterns_report.md
- **Focus**: Practical patterns for overnight GPU batch processing on consumer hardware. VRAM management (loading/unloading models between jobs), thermal/power considerations for multi-hour runs, watchdog/health-check patterns, handling GPU hangs or ROCm driver issues, graceful shutdown at cutoff time. Multi-GPU orchestration across machines (office + arch). Systemd timer integration patterns. Idle-power vs. throughput tradeoffs.

### Sub-Topic 5: Agent Harness Batch Processing Patterns
- **Slug**: agent-harness-batch-patterns
- **Perspective**: none — survey of existing practice
- **Report path**: reports/agent-harness-batch-patterns_report.md
- **Focus**: Patterns for using AI agent harnesses (Claude Code, OMP/Oh My Pi, Aider, OpenHands/OpenDevin, CrewAI, AutoGPT) in batch/headless mode for research. How people script multi-turn agent sessions, handle tool-call loops without human intervention, manage per-job working directories, deal with timeouts and error recovery. Prior art for "batch agent research" or "overnight agent queue" systems. Whether general harness batch processing is different enough from raw LLM batch to warrant different infrastructure.
