// Approval hook for risky tool calls.
//
// Calls an LLM to classify whether each bash command is safe before execution.
// Primary: vast-vllm at http://localhost:8001 (DeepSeek V4 Flash)
// Fallback: office ollama at http://office:11434 (Qwen 3.6 27B)
// If neither endpoint responds, blocks by default (fail-closed).
//
// The LLM returns a JSON verdict { safe: boolean, reason: string }.
// Safe commands pass through; unsafe ones trigger an interactive confirm dialog.

const PRIMARY_API = "http://localhost:8001/v1/chat/completions";
const PRIMARY_MODEL = "deepseek-v4-flash";
const FALLBACK_API = "http://office:11434/v1/chat/completions";
const FALLBACK_MODEL = "qwen3.6:27b";

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

// vLLM with the Outlines backend rejects { type: "json_object" } — it requires
// a schema. Sending the schemaless form crashes EngineCore.
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

const PRIMARY_RESPONSE_FORMAT = { type: "json_schema", json_schema: VERDICT_SCHEMA };
const FALLBACK_RESPONSE_FORMAT = { type: "json_object" };

async function tryEndpoint(url, model, responseFormat, timeoutMs, cmd) {
  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), timeoutMs);

    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: CLASSIFY_PROMPT },
          { role: "user", content: `Evaluate this command: ${cmd}` },
        ],
        response_format: responseFormat,
        temperature: 0.1,
        max_tokens: 256,
      }),
      signal: ac.signal,
    });

    clearTimeout(timer);
    if (!resp.ok) return null;

    const data = await resp.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) return null;

    const parsed = JSON.parse(content);
    if (typeof parsed?.safe !== "boolean") return null;
    return { safe: parsed.safe, reason: String(parsed.reason ?? "") };
  } catch {
    return null;
  }
}

async function classifyCommand(cmd, onPrimaryFail) {
  const result = await tryEndpoint(PRIMARY_API, PRIMARY_MODEL, PRIMARY_RESPONSE_FORMAT, 5000, cmd);
  if (result) return result;

  onPrimaryFail?.();
  return tryEndpoint(FALLBACK_API, FALLBACK_MODEL, FALLBACK_RESPONSE_FORMAT, 8000, cmd);
}

export default function (pi) {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("LLM safety hook loaded", "info");
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const cmd = String(event.input.command ?? "");

    const verdict = await classifyCommand(cmd, () => {
      ctx.ui.notify("primary classifier unavailable, using fallback", "warn");
    });

    if (!verdict) {
      // No endpoint reachable — block by default (fail-closed)
      ctx.ui.notify("Safety classifier unreachable — command blocked", "error");
      return { block: true, reason: "Command blocked: unable to reach safety classifier (vast-vllm and office both unreachable)" };
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
