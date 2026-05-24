# Agent Harness Batch Processing Patterns

## Research Sub-Topic
Patterns for using AI agent harnesses (Claude Code, OMP/Oh My Pi, Aider, OpenHands, CrewAI, AutoGPT) in batch/headless mode for research. How people script multi-turn agent sessions, handle tool-call loops without human intervention, manage per-job working directories, deal with timeouts and error recovery. Prior art for "batch agent research" or "overnight agent queue" systems. Whether general harness batch processing is different enough from raw LLM batch to warrant different infrastructure.

## 1. Summary

AI agent harnesses — the software infrastructure surrounding LLMs that manages conversation loops, tool dispatch, memory, and error recovery — are increasingly being adapted for batch and overnight execution. Every major agent harness now has a dedicated headless or non-interactive mode: Claude Code's `claude -p` and Agent SDK, OMP's print mode (`--mode text|json`) and RPC mode, Aider's `--message` flag and Python API, OpenHands' `--headless` mode, and AutoGPT's `--no-gui` continuous agents. These modes share a common pattern: accept a prompt (via CLI argument, file, or stdin), execute the full agent loop with tool access to completion, and output structured results (text, JSON, JSONL) before exiting.

For overnight agent queues specifically, the prior art landscape is surprisingly mature given the recency of coding agents. Multiple open-source projects implement full overnight queue systems: **night-watch-cli** queues GitHub issues and produces PRs overnight through a workflow state machine (Draft → Ready → In Progress → Review → Done); **sleepless-agent** runs a 24/7 daemon with SQLite-backed task persistence, time-aware budget management (aggressive at night, conservative during day), and isolated per-task workspaces; **block/agent-task-queue** solves the specific problem of concurrent agent execution thrashing a machine by providing local task queuing with file locking; **overstory** orchestrates multi-agent teams in isolated git worktrees with a custom SQLite mail protocol; and **TinyAGI** provides a full task orchestrator with SQLite queue, retry logic, dead-letter management, and a TUI dashboard.

The architectural patterns that emerge across these systems are remarkably consistent: (1) file-system-based queue storage with pending/running/done/failed directories (the simplest pattern) or SQLite for richer metadata; (2) flock-based mutual exclusion to prevent concurrent processing; (3) per-job isolated working directories (`mktemp -d` or dedicated workspace subdirectories); (4) timeouts enforced at the harness level (per-job and overall session); (5) notifications via Slack, ntfy, or system-level messaging; (6) systemd/cron scheduling for the overnight trigger. No system found uses container-based isolation — file-system isolation via separate working directories is universally preferred.

The question of whether agent harness batch processing differs from raw LLM batch inference has a clear answer: **yes, they are fundamentally different problems requiring different infrastructure.** Raw LLM batch inference (e.g., vLLM continuous batching, OpenAI Batch API, Anthropic Message Batches) optimizes for packing many independent token-generation requests onto idle GPU time to reduce cost by up to 50%. Agent harness batch processing, by contrast, requires maintaining state across multi-turn tool-call loops, managing per-job filesystem side effects, enforcing timeouts on individual tool executions, detecting and recovering from infinite loops, and preserving context across session boundaries. The two are complementary: you might use raw batch inference as the model backend for an agent, but the agent harness layer still needs its own queue, scheduling, isolation, and recovery infrastructure. For a consumer GPU with a single model server (Ollama/vLLM), sequential execution with harness-level queuing is the only practical architecture — the "batch" aspect is temporal (overnight) rather than concurrent.

## 2. Relation to Primary Question

Agent harness batch processing is the orchestrating layer that makes overnight bulk LLM workloads practical — it provides the queuing, scheduling, isolation, timeout management, error recovery, and result collection that raw inference engines do not. The primary research question's answer depends as much on choosing and configuring the right agent harness (and its headless mode) as it does on the inference backend, because agent workloads present fundamentally different failure modes (infinite tool loops, context exhaustion, stalled subprocesses) that raw batch APIs are not designed to handle.

## 3. Source Evaluation

### Source 1: Claude Code Headless Mode Documentation
- **URL**: https://code.claude.com/docs/en/headless
- **Title**: "Run Claude Code programmatically"
- **Assessment**: Primary source. Official documentation from Anthropic, the creators of Claude Code. Published and maintained as part of the Claude Code documentation site. Highly authoritative — this is the canonical reference for Claude Code's `-p` mode, bare mode, streaming JSON output, session continuation, and tool approval flags. Recency: retrieved May 2026, actively maintained. **Weight: High.**

### Source 2: OMP/Oh My Pi Operational Modes (DeepWiki)
- **URL**: https://deepwiki.com/can1357/oh-my-pi/6-operational-modes
- **Title**: "Operational Modes"
- **Assessment**: Secondary source. DeepWiki is an AI-generated documentation site that analyzes source code. However, it references specific source files (e.g., `packages/coding-agent/src/modes/print-mode.ts`, `packages/coding-agent/src/cli/args.ts`) with line-level precision. Cross-referenced against the actual OMP GitHub repository at https://github.com/can1357/oh-my-pi. The factual claims about print mode (text/JSON output), RPC mode (JSON-RPC protocol), and session management are verifiable against source. Recency: analyzed from source as of May 2026. **Weight: Medium-High** (AI-generated but source-verifiable).

### Source 3: OMP GitHub Repository
- **URL**: https://github.com/can1357/oh-my-pi
- **Title**: "oh-my-pi: AI Coding agent for the terminal"
- **Assessment**: Primary source. MIT-licensed open-source project with 4,652 stars, 425 forks, and active CI. The README documents 17 distinct harness capabilities including subagent task fan-out, eval kernel bridging, LSP integration, DAP debugging, time-travel streaming rules, and headless print/RPC modes. Recency: actively maintained (releases within days of research date). **Weight: High.**

### Source 4: Aider Scripting Documentation
- **URL**: https://aider.chat/docs/scripting.html
- **Title**: "Scripting aider"
- **Assessment**: Primary source. Official documentation from the Aider project. Documents `--message`, `--message-file`, `--yes`, `--auto-commits`, `--no-stream` flags and the Python API (`Coder.create()`, `coder.run()`). Author is Paul Gauthier, verified open-source maintainer. Recency: actively maintained. **Weight: High.**

### Source 5: OpenHands Headless Mode Documentation
- **URL**: https://docs.openhands.dev/openhands/usage/cli/headless
- **Title**: "Headless Mode"
- **Assessment**: Primary source. Official documentation from the OpenHands project (formerly OpenDevin). Documents `--headless -t "task"` and `--headless -f task.txt` syntax, JSON/JSONL output, and the critical behavior that headless mode always auto-approves all actions (no confirmation prompts). Recency: actively maintained. **Weight: High.**

### Source 6: Sleepless Agent (GitHub + DeepWiki)
- **URL**: https://github.com/context-machine-lab/sleepless-agent and https://deepwiki.com/context-machine-lab/sleepless-agent
- **Title**: "sleepless-agent: 24/7 AI agent that maximizes Claude Code Pro usage via Slack"
- **Assessment**: Primary source for the GitHub repository; secondary for the DeepWiki analysis. The repository is an open-source project with a documented architecture: Slack Bot → Task Queue (SQLite) → Agent Daemon → Claude Executor → Result Manager. The DeepWiki analysis provides useful architectural decomposition but is AI-generated. Key design decisions (time-aware budget thresholds, SQLite task persistence, isolated workspaces, multi-agent planner-worker-evaluator workflow) are verifiable from the source. Author: context-machine-lab (pseudonymous but code is inspectable). Recency: last updated early 2026. **Weight: Medium** (open-source but not widely adopted; design ideas are sound and verifiable).

### Source 7: Night Watch CLI (GitHub)
- **URL**: https://github.com/jonit-dev/night-watch-cli
- **Title**: "night-watch-cli: AI agent that implements your specs, opens PRs, and reviews code overnight"
- **Assessment**: Primary source (repository). Open-source project implementing an overnight agent queue that uses GitHub issues as the task queue with a Draft → Ready → In Progress → Review → Done workflow state machine. Supports custom Anthropic-compatible endpoints. Author: jonit-dev (pseudonymous). Recency: March 2026. **Weight: Low-Medium** (small project, limited adoption, but directly relevant design pattern).

### Source 8: Block Agent Task Queue (GitHub)
- **URL**: https://github.com/block/agent-task-queue
- **Title**: "agent-task-queue: Local task queuing for AI agents"
- **Assessment**: Primary source (repository). Published by Block (formerly Square), a well-known technology company, giving it higher credibility. Addresses the specific problem of agent shell timeouts conflicting with queue wait times. The README identifies a "fatal flaw" — AI tools have built-in shell timeouts (30s-120s), and if a job waits longer in queue, the agent gives up. **Weight: Medium** (from a credible organization but a small utility library).

### Source 9: Martin Fowler — "Harness Engineering for Coding Agent Users"
- **URL**: https://martinfowler.com/articles/harness-engineering.html
- **Title**: "Harness engineering for coding agent users"
- **Assessment**: Secondary/analytical source. Martin Fowler is a widely respected software architecture author and Thoughtworks Chief Scientist. The article provides a conceptual framework (feedforward vs. feedback, computational vs. inferential, maintainability/architecture/behaviour harness categories) for understanding agent harnesses. Published May 2026. While not directly about batch processing, it provides the vocabulary for understanding what a harness does and why batch-specific harness infrastructure is needed. **Weight: Medium-High** (conceptual framework, not empirical research, but from a highly credible author).

### Source 10: Eran Sandler — "Batch API is terrible for one agent. It might be great for a fleet."
- **URL**: https://eran.sandler.co.il/post/2026-04-27-batch-api-is-terrible-for-one-agent/
- **Title**: "Batch API is terrible for one agent. It might be great for a fleet."
- **Assessment**: Secondary source (personal blog, opinion/analysis). The author experiments with routing agent tool-call turns through Anthropic's Batch API and reports that the 90-120 second per-turn latency makes single-agent use impractical but that pooling multiple agents' turns into batch submissions could be viable. Unaffiliated individual contributor but analysis is grounded in concrete experimentation. Published April 2026. **Weight: Low-Medium** (opinion with experimental backing but limited scope).

### Source 11: Various Production Failure Analysis (DEV Community, Medium)
- **URLs**: https://dev.to/whoffagents/ai-agent-production-failures-what-breaks-and-how-to-build-around-it-17lj (April 2026), https://dev.to/bobrenze/how-ai-agents-handle-stalled-tasks-and-timeouts-lessons-from-my-production-failure-1jj9 (March 2026), https://medium.com/@0albidev.1/your-ai-agent-is-not-broken-your-runtime-is-4ff8046758d8 (March 2026), https://fast.io/resources/ai-agent-batch-processing/ (February 2026)
- **Assessment**: Secondary sources (blog posts/tutorials). These provide practical patterns for agent error handling: loop detection via consecutive-call tracking, explicit timeouts on every external call, state externalization to files rather than memory, save-as-you-go patterns, and error logging with skip-to-next-item. Authors are individual developers sharing experience. **Weight: Low-Medium** (practical patterns validated by multiple independent sources describing similar solutions).

### Source 12: CrewAI Flows Documentation
- **URL**: https://docs.crewai.com/en/concepts/flows and https://crewai.com/crewai-flows
- **Assessment**: Primary source (official documentation). Documents CrewAI Flows as an event-driven orchestration layer with `@start()` and `@listen()` decorators, state management, and conditional routing. However, CrewAI Flows is designed for production multi-agent pipelines (claiming 12M+ executions/day) rather than consumer GPU overnight batch. Relevant as a pattern reference for stateful workflow orchestration but over-engineered for a single-GPU home lab. **Weight: Medium** (official docs, but the product targets enterprise use cases).

### Source 13: Agent.xpu / Batch Query Processing Papers
- **URLs**: https://arxiv.org/html/2506.24045v1/ (June 2025) and https://arxiv.org/html/2509.02121v1 (September 2025)
- **Assessment**: Primary source (academic preprints). Agent.xpu proposes a dual-queue architecture (real-time + best-effort) for scheduling agentic LLM workloads on heterogeneous SoCs. The batch query processing paper proposes a server-worker paradigm with pull-based workers and continuous batching. Both are peer-review-track preprints. Recency: 2025. **Weight: Medium** (academic but not yet peer-reviewed; proposed architectures are validated through simulation, not production deployment).

## 4. Conclusions

### 4.1 Harness Batch Processing IS Fundamentally Different from Raw LLM Batch

Raw LLM batch APIs (OpenAI, Anthropic, vLLM continuous batching) optimize token-generation throughput by packing independent requests onto idle GPU cycles. Agent harness batch processing requires **stateful multi-turn orchestration** — the harness must manage tool-call loops, filesystem side effects, context windows, and error recovery across sessions that may last minutes to hours. These are different layers of the stack. For the user's home lab with a single GPU serving Ollama, the right architecture is: **Ollama as the inference backend (handling raw token generation), with a harness-level queue system (handling job scheduling, isolation, timeouts, and result collection).** Do not try to make the inference engine handle agent orchestration, and do not try to make the agent harness handle GPU scheduling.

### 4.2 Every Major Agent Harness Has a Headless Mode — But They Differ in Batch Suitability

| Harness | Headless Mode | Batch Suitability | Key Limitation |
|---------|--------------|-------------------|----------------|
| Claude Code | `claude -p` with Agent SDK | High (Python/TS SDK, JSON output, `--resume`, `--bare`) | Requires Anthropic API; not local-model-native |
| OMP | `--mode text|json` (print) or `--mode rpc` | High (print mode is purpose-built for scripting; RPC for programmatic control) | Print mode is single-shot; RPC mode requires client implementation |
| Aider | `--message` flag or Python API | Medium (good for code-editing batches, `--yes` for auto-approve) | Designed for code editing, not general research agents |
| OpenHands | `--headless -t "task"` | Medium (JSON output, file-based tasks) | Always auto-approves all actions; no fine-grained tool control |
| CrewAI | Flows API with `@start()`/`@listen()` | Medium (powerful orchestration, but enterprise-oriented) | Over-engineered for single-GPU home lab; Python-heavy |
| AutoGPT | `--no-gui`, Platform agents | Low-Medium (continuous agents exist but platform is complex) | Architecture targets cloud deployment; significant setup overhead |

**For the user's context (OMP already in use, Ollama as backend, NixOS + systemd)**: OMP's print mode (`omp -p "prompt" --no-session --model office-ollama/qwen3.6:27b`) is the most natural fit — it already supports the model, runs locally, and the plan document's architecture aligns with OMP's headless design. The existing plan is well-aligned with how OMP print mode works.

### 4.3 The Overnight Queue Architecture Pattern Is Well-Established

Across night-watch-cli, sleepless-agent, block/agent-task-queue, overstory, and TinyAGI, the same architectural pattern repeats:

1. **File-system queue**: `pending/ → running/ → done/ | failed/` with timestamped directories. SQLite for metadata when richer querying is needed.
2. **flock-based locking**: Prevents concurrent processing of the queue.
3. **Per-job isolation**: Each job runs in `mktemp -d` or a dedicated workspace subdirectory. No container overhead.
4. **Timeout enforcement**: Per-job timeouts (default 30 min, configurable) enforced by the harness process, plus a global `RuntimeMaxSec` at the systemd level.
5. **Save-as-you-go**: Results written incrementally; if a job crashes, completed work is preserved.
6. **Notification**: ntfy.sh, Slack webhooks, or system notifications on batch start, per-job failure, and batch completion.
7. **systemd/cron trigger**: `OnCalendar=daily` at 23:00 or similar.

The user's existing plan (section in `local://PLAN.md`) follows this pattern almost exactly — it is well-aligned with prior art and no fundamental redesign is needed.

### 4.4 Critical Operational Patterns for Reliability

From production failure analyses, these guardrails are essential for unattended overnight execution:

- **Loop detection**: Track consecutive identical tool calls; if the same tool is called with the same arguments >3 times, inject a system message telling the model to try a different approach. After a hard threshold (e.g., 9 repetitive calls), terminate the job.
- **Per-tool timeouts**: Every external tool call (bash, web_search, subprocess) should have an explicit timeout. If a tool hangs, the harness kills it rather than blocking the entire batch.
- **Context window management**: Long-running agent sessions can exhaust context windows. Use the harness's compaction mechanism (OMP's `/compact`, Claude Code's auto-compaction) or enforce a maximum number of turns per job.
- **State externalization**: Write intermediate results to disk after each significant step. If the harness process itself dies (OOM, power loss), surviving output is preserved.
- **Error classification**: Distinguish transient errors (retry with backoff), model-recoverable errors (return error as tool output so the model can adjust), and fatal errors (move job to failed/).
- **Idempotent queue processing**: Jobs moved to `running/` should be safe to re-run if the processor crashes before moving them to `done/` or `failed/`.

### 4.5 Recommendations for the User's Architecture

Based on this survey, the plan in `local://PLAN.md` is sound. Specific enhancements to consider:

1. **Add loop detection to the processor script**: Before spawning `omp`, inject a system prompt appendix instructing the agent to stop and report if it repeats the same action more than 3 times.
2. **Use OMP's `--mode json` for structured output**: The JSONL output from print mode includes `AgentEvent` objects that can be parsed for tool call counts, error detection, and cost tracking — more useful than plain text output for automated processing.
3. **Consider per-model queue partitioning**: If different models (qwen3.6:27b vs gemma4) are used for different job types, tag jobs by model requirement and only process jobs matching the currently loaded model.
4. **Add a `batch-cancel` function**: Ability to remove a pending job by name/pattern, useful when the user realizes a queued prompt has a mistake.
5. **The systemd `RuntimeMaxSec` is a critical safety net**: Set it to stop processing by the time the user typically starts work, preventing GPU contention during interactive use.

## 5. Bibliography

Anthropic. (2026). *Run Claude Code programmatically*. Claude Code Docs. https://code.claude.com/docs/en/headless

can1357. (2026). *oh-my-pi: AI Coding agent for the terminal* [Computer software]. GitHub. https://github.com/can1357/oh-my-pi

can1357/oh-my-pi. (2026). *Operational Modes*. DeepWiki. https://deepwiki.com/can1357/oh-my-pi/6-operational-modes

context-machine-lab. (2026). *sleepless-agent: 24/7 AI agent that maximizes Claude Code Pro usage via Slack* [Computer software]. GitHub. https://github.com/context-machine-lab/sleepless-agent

context-machine-lab/sleepless-agent. (2026). *Overview*. DeepWiki. https://deepwiki.com/context-machine-lab/sleepless-agent

CrewAI. (2026). *Flows*. CrewAI Documentation. https://docs.crewai.com/en/concepts/flows

CrewAI. (2026). *CrewAI Flows*. https://crewai.com/crewai-flows

Fowler, M. (2026, May 12). *Harness engineering for coding agent users*. martinfowler.com. https://martinfowler.com/articles/harness-engineering.html

Gauthier, P. (2026). *Scripting aider*. Aider Documentation. https://aider.chat/docs/scripting.html

jonit-dev. (2026). *night-watch-cli: AI agent that implements your specs, opens PRs, and reviews code overnight* [Computer software]. GitHub. https://github.com/jonit-dev/night-watch-cli

OpenHands. (2026). *Headless Mode*. OpenHands Documentation. https://docs.openhands.dev/openhands/usage/cli/headless

Renze, B. (2026, March 4). *How AI Agents Handle Stalled Tasks and Timeouts: Lessons From My Production Failure*. DEV Community. https://dev.to/bobrenze/how-ai-agents-handle-stalled-tasks-and-timeouts-lessons-from-my-production-failure-1jj9

Sandler, E. (2026, April 27). *Batch API is terrible for one agent. It might be great for a fleet.* https://eran.sandler.co.il/post/2026-04-27-batch-api-is-terrible-for-one-agent/

Square/Block. (2026). *agent-task-queue: Local task queuing for AI agents* [Computer software]. GitHub. https://github.com/block/agent-task-queue

TinyAGI. (2026). *tinyagi: Agent teams orchestrator for One Person Company* [Computer software]. GitHub. https://github.com/TinyAGI/tinyagi

West, J. (2026). *overstory: Multi-agent orchestration for AI coding agents* [Computer software]. GitHub. https://github.com/jayminwest/overstory

Whoff Agents. (2026, April 9). *AI Agent Production Failures: What Breaks and How to Build Around It*. DEV Community. https://dev.to/whoffagents/ai-agent-production-failures-what-breaks-and-how-to-build-around-it-17lj

Wu, Z., et al. (2025). *Batch Query Processing and Optimization for Agentic Workflows*. arXiv. https://arxiv.org/html/2509.02121v1

Zhang, Y., et al. (2025). *Agent.xpu: Efficient Scheduling of Agentic LLM Workloads on Heterogeneous SoC*. arXiv. https://arxiv.org/html/2506.24045v1/

AlbiDev. (2026, March 24). *Your AI Agent Is Not Broken. Your Runtime Is.* Medium. https://medium.com/@0albidev.1/your-ai-agent-is-not-broken-your-runtime-is-4ff8046758d8

Fast.io. (2026, February 10). *How to Build AI Agents for Batch Processing*. https://fast.io/resources/ai-agent-batch-processing/

MindStudio. (2026). *How to Build an AI Agent That Runs Overnight: A Practical Guide*. https://www.mindstudio.ai/blog/build-ai-agent-runs-overnight
