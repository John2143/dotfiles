// Approval hook for risky tool calls.
//
// Uses OMP's configured smol model (from ~/.omp/agent/config.yml modelRoles.smol)
// via raw fetch to the OpenAI-compatible /chat/completions endpoint. The model's
// baseUrl and API key are resolved through ctx.modelRegistry.
//
// Classification is tried in order:
//   1. Primary smol model (from config.yml modelRoles.smol)
//   2. Fallback chain (from config.yml retry.fallbackChains.smol)
//   3. Local regex classifier (ultimate fallback — no network needed)
// The LLM returns a JSON verdict { safe: boolean, reason: string }.
// Safe commands pass through; unsafe ones trigger an interactive confirm dialog.
// No response_format is sent — json_schema is rejected by DeepSeek v4,
// json_object crashes vLLM Outlines, and ollama <0.6 ignores it.
// The prompt instructs JSON-only output; parseVerdictText() handles
// markdown-fenced fallback parsing for providers that ignore it.

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

const CLASSIFY_PROMPT = `You are a safety classifier for CLI commands in a NixOS dotfiles repo. Determine if the proposed command is safe to execute automatically (safe) or requires user confirmation (unsafe).

Respond ONLY with a JSON object: { "safe": boolean, "reason": "brief explanation" }

SAFE (automatic, no confirmation needed):
- Reading files and directories (cat, ls, find, grep, head, tail, less, read, stat, file, du, df)
- Operations limited to /tmp or obviously safe temp locations
- Echo, printf, print, and other display commands
- Building without switching (nix build, nix develop, nix shell, cargo build, go build)
- Network fetches (curl, wget) that DO NOT pipe to shell
- Grepping, searching, listing
- Package queries (nix search, apt-cache, pip list)

UNSAFE (requires user confirmation):
- ANY git command (git status, git log, git diff, git add, git commit, git push, git pull, git checkout, etc.) — all git invocations require explicit user confirmation, no exceptions
- Deleting files outside /tmp (rm -rf on /etc, /nix, /boot, /home, /root, /var, /opt, /usr)
- System mutations (nixos-rebuild switch|boot|test, home-manager switch, nix-collect-garbage)
- Force-pushing or rewriting git history (git push --force, git reset --hard)
- Database schema changes (drop table, drop database, alter table, truncate)
- Piping curl/wget directly to shell
- Formatting or partitioning disks (mkfs, dd, fdisk, parted, mkswap)
- Installing/modifying system packages outside /tmp
- Writing to system config paths (/etc, /nix, /boot)

The user runs commands in a NixOS environment with home-manager. Commands touching /nix/store are sensitive. Commands inside /tmp or that just print/output are safe.`;

// We intentionally do NOT send response_format. json_schema is rejected
// by DeepSeek v4 Flash (400: "response_format type is unavailable now"),
// json_object crashes vLLM with the Outlines backend, and ollama <0.6
// ignores it anyway. The prompt already instructs "Respond ONLY with a
// JSON object" and parseVerdictText() strips markdown fences before
// JSON.parse — this is the most portable approach.
// Timeout for the classification call (ms).

const CLASSIFY_TIMEOUT_MS = 10000;

function readSmolModelSpec(): string | null {
  try {
    const cfg = path.join(os.homedir(), ".omp", "agent", "config.yml");
    const raw = fs.readFileSync(cfg, "utf-8");
    const m = raw.match(/^\s*smol:\s*(.+)$/m);
    return m ? m[1].trim() : null;
  } catch {
    return null;
  }
}
function readFallbackChain(): string[] {
  try {
    const cfg = path.join(os.homedir(), ".omp", "agent", "config.yml");
    const raw = fs.readFileSync(cfg, "utf-8");
    // Find fallbackChains block, then smol section within it.
    // Capture everything from "smol:" until the next indented key or end of string.
    const fbMatch = raw.match(/fallbackChains:[\s\S]*?smol:([\s\S]*?)(?=\n  \w|\n\w|$)/);
    if (!fbMatch) return [];
    const items = fbMatch[1].matchAll(/- "([^"]+)"/g);
    return [...items].map(m => m[1]);
  } catch {
    return [];
  }
}

function parseVerdictText(text: string): { safe: boolean; reason: string } | null {
  if (!text) return null;

  // Strip markdown code fences if present (fallback for providers that
  // ignore responseFormat)
  text = text.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "");

  try {
    const parsed = JSON.parse(text);
    if (typeof parsed?.safe !== "boolean") return null;
    return { safe: parsed.safe, reason: String(parsed.reason ?? "") };
  } catch {
    return null;
  }
}
function localClassify(cmd: string): { safe: boolean; reason: string } {
  const trimmed = cmd.trim();

  // ---- UNSAFE patterns (checked first) ----
  const unsafePatterns: Array<[RegExp, string]> = [
    [/^git\s+(add|commit|push|pull|checkout|merge|rebase|reset|clean|tag\s+(?!(-l|--list))|stash\s+(push|drop|pop|apply|save)|branch\s+(-d|-D|--delete|--move|-m|--force))\b/, "git mutation"],
    [/\bgit\s+push\s+.*(--force|-f|--delete)\b/, "git force push or branch delete"],
    [/\bnixos-rebuild\s+(switch|boot|test)\b/, "nixos-rebuild system mutation"],
    [/\bhome-manager\s+switch\b/, "home-manager switch"],
    [/\bnix-collect-garbage\b/, "nix-collect-garbage"],
    [/\brm\s+-r?f?\s+(?!\/tmp\b)\//, "recursive deletion outside /tmp"],
    [/\brm\s+-r?f?\s+\/(etc|nix|boot|home|root|var|opt|usr)\b/, "deletion of system directory"],
    [/\b(curl|wget)\b.*\|\s*(sh|bash|sudo\s+bash)\b/, "pipe network fetch to shell"],
    [/\b(mkfs\.|dd\s+if=|fdisk|parted|mkswap)\b/, "disk/partition manipulation"],
    [/\b(drop\s+(table|database)|alter\s+table|truncate(\s+table)?)\b/i, "database schema change"],
    [/\b(nix\s+profile\s+install|apt(-get)?\s+install|pip\d?\s+install)\b/, "package installation"],
    [/[>|]\s*\/+(etc|nix|boot)\//, "writing to system config path"],
  ];

  for (const [pat, reason] of unsafePatterns) {
    if (pat.test(trimmed)) {
      return { safe: false, reason: `local: UNSAFE — ${reason}` };
    }
  }

  // ---- SAFE patterns ----
  const safePatterns: Array<[RegExp, string]> = [
    [/^git\s+(status\b|log\b|diff\b|show\b|stash\s+list\b|branch(?:\s|$)|remote\b|grep\b|blame\b|ls-files\b|ls-tree\b|rev-parse\b|rev-list\b|describe\b|tag(?:\s+(-l|--list)|$))/, "git read-only"],
    [/^(cat|ls|find|grep|head|tail|less|stat|file|du|df)\b/, "file reading"],
    [/^(read|wc|sort|uniq|cut|tr|awk|sed|jq)\b/, "text processing"],
    [/^(echo|printf|print)\b/, "display"],
    [/^(nix\s+(build|develop|shell|search)|cargo\s+build|go\s+build)\b/, "build without switch"],
    [/^(curl|wget)\b/, "network fetch"],
    [/^(which|type|command\s+-v|env|printenv|pwd|whoami|id|uname|hostname|date)\b/, "system info"],
    [/^(apt-cache|pip\d?\s+(list|show|freeze))\b/, "package query"],
    [/^\/tmp\//, "operation in /tmp"],
  ];

  for (const [pat, reason] of safePatterns) {
    if (pat.test(trimmed)) {
      return { safe: true, reason: `local: SAFE — ${reason}` };
    }
  }

  // Default: unrecognized → block (conservative)
  return { safe: false, reason: "local: unrecognized command — blocking by default" };
}


async function tryModel(spec: string, cmd: string, modelRegistry: any): Promise<{ safe: boolean; reason: string } | null> {
  const slash = spec.indexOf("/");
  if (slash === -1) { console.error("[approve] invalid model spec:", spec); return null; }

  const provider = spec.slice(0, slash);
  const modelId = spec.slice(slash + 1);
  console.error("[approve] trying model:", provider, modelId);
  const model = modelRegistry.find(provider, modelId);
  if (!model) { console.error("[approve] model not found:", provider, modelId); return null; }

  const apiKey = await modelRegistry.getApiKey(model);
  if (!apiKey) { console.error("[approve] no API key for model:", model.provider, model.id); return null; }

  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), CLASSIFY_TIMEOUT_MS);

    const url = `${model.baseUrl}/chat/completions`;
    console.error("[approve] fetching:", url);
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: model.id,
        messages: [
          { role: "system", content: CLASSIFY_PROMPT },
          { role: "user", content: `Evaluate this command: ${cmd}` },
        ],
        temperature: 0.1,
        max_tokens: 256,
        // response_format omitted — DeepSeek v4 rejects json_schema;
        // the prompt already instructs "Respond ONLY with a JSON object"
        // and parseVerdictText() handles text/fenced parsing.
      }),
      signal: ac.signal,
    });

    clearTimeout(timer);

    console.error("[approve] response status:", response.status);
    if (!response.ok) {
      const errText = await response.text().catch(() => "");
      console.error("[approve] response error body:", errText.slice(0, 500));
      return null;
    }

    const data = await response.json();
    const contentText = data.choices?.[0]?.message?.content;
    console.error("[approve] verdict text:", contentText?.slice(0, 200));
    const verdict = parseVerdictText(contentText);
    if (verdict) {
      console.error("[approve] model", spec, "verdict:", verdict.safe ? "SAFE" : "UNSAFE", "-", verdict.reason);
    }
    return verdict;
  } catch (err) {
    console.error("[approve] fetch exception for", spec, ":", err?.message || err);
    return null;
  }
}

async function classifyCommand(cmd, modelRegistry) {
  const primary = readSmolModelSpec();
  if (!primary) { console.error("[approve] no smol model spec found"); return null; }

  // Try primary model
  const verdict = await tryModel(primary, cmd, modelRegistry);
  if (verdict) return verdict;

  // Try fallback chain
  const fallbacks = readFallbackChain();
  for (const spec of fallbacks) {
    if (spec === primary) continue;
    console.error("[approve] falling back to:", spec);
    const fbVerdict = await tryModel(spec, cmd, modelRegistry);
    if (fbVerdict) return fbVerdict;
  }

  return null; // all models failed
}

export default function (pi) {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("LLM safety hook loaded", "info");
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const cmd = String(event.input.command ?? "");

    let verdict = await classifyCommand(cmd, ctx.modelRegistry);

    if (!verdict) {
      // All LLM classifiers unreachable — fall back to local regex classifier
      console.error("[approve] all LLM classifiers unreachable, using local regex classifier");
      ctx.ui.notify("LLM safety classifiers unreachable — using local fallback", "warning");
      verdict = localClassify(cmd);
    }

    if (verdict.safe) return; // LLM says safe — let it through

    // LLM says unsafe — prompt user
    if (!ctx.hasUI) {
      return { block: true, reason: `Command blocked: ${verdict.reason}` };
    }

    const ok = await ctx.ui.confirm("Unsafe command", `${cmd.slice(0, 200)}\n\n${verdict.reason}\n\nAllow?`);
    if (!ok) {
      ctx.ui.notify("Command denied", "error");
      return { block: true, reason: `Denied: ${verdict.reason}` };
    }
    ctx.ui.notify("Command approved by user", "success");
  });
}
