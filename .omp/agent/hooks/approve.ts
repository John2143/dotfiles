// Approval hook for risky tool calls.
//
// Uses OMP's configured smol model (from ~/.omp/agent/config.yml modelRoles.smol)
// via raw fetch to the OpenAI-compatible /chat/completions endpoint. The model's
// baseUrl and API key are resolved through ctx.modelRegistry.
//
// If the smol model is unreachable, blocks by default (fail-closed).
//
// The LLM returns a JSON verdict { safe: boolean, reason: string }.
// Safe commands pass through; unsafe ones trigger an interactive confirm dialog.
//
// json_schema is the safe default that works everywhere (OpenAI, DeepSeek,
// vLLM, ollama ≥0.6). We also keep a text-parsing fallback for providers
// that ignore responseFormat.

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

// json_schema is the safe default that works everywhere (OpenAI, DeepSeek,
// vLLM, ollama ≥0.6). vLLM with the Outlines backend rejects
// { type: "json_object" } — sending the schemaless form crashes EngineCore.
const VERDICT_SCHEMA = {
  name: "verdict",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["safe", "reason"],
    properties: {
      safe: { type: "boolean" },
      reason: { type: "string" },
    },
  },
};

const RESPONSE_FORMAT = { type: "json_schema", json_schema: VERDICT_SCHEMA };

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

async function classifyCommand(cmd, modelRegistry) {
  const spec = readSmolModelSpec();
  if (!spec) return null;

  const slash = spec.indexOf("/");
  if (slash === -1) return null;

  const provider = spec.slice(0, slash);
  const modelId = spec.slice(slash + 1);
  const model = modelRegistry.find(provider, modelId);
  if (!model) return null;

  const apiKey = await modelRegistry.getApiKey(model);
  if (!apiKey) return null;

  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), CLASSIFY_TIMEOUT_MS);

    const url = `${model.baseUrl}/chat/completions`;
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
        response_format: RESPONSE_FORMAT,
      }),
      signal: ac.signal,
    });

    clearTimeout(timer);

    if (!response.ok) return null;

    const data = await response.json();
    const contentText = data.choices?.[0]?.message?.content;
    return parseVerdictText(contentText);
  } catch {
    return null;
  }
}

export default function (pi) {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("LLM safety hook loaded", "info");
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const cmd = String(event.input.command ?? "");

    const verdict = await classifyCommand(cmd, ctx.modelRegistry);

    if (!verdict) {
      // Smol model unreachable — block by default (fail-closed)
      ctx.ui.notify("Safety classifier unreachable — command blocked", "error");
      return { block: true, reason: "Command blocked: unable to reach safety classifier (smol model unreachable)" };
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
