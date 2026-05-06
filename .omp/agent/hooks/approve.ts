// Approval hook for risky tool calls.
//
// Triggers an interactive confirm dialog before executing:
//   - bash commands matching known-risky patterns
//   - write/edit calls (optional; uncomment if too noisy)
//
// Everything else runs uninterrupted.

const RISKY_BASH = [
  /\brm\s+-rf?\b/i,
  /\bnixos-rebuild\s+(switch|boot|test)\b/i,
  /\bhome-manager\s+switch\b/i,
  /\bnix-collect-garbage\b/i,
  /\bgit\s+push.*--force\b/i,
  /\bgit\s+reset\s+--hard\b/i,
  /\bdrop\s+(table|database|schema)\b/i,
  /\bcurl[^|]*\|\s*(ba)?sh\b/i,
  /\bwget[^|]*\|\s*(ba)?sh\b/i,
  /\bdd\s+if=/i,
  /\bmkfs\b/i,
];

export default function (pi) {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("Approval hook loaded", "info");
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const cmd = String(event.input.command ?? "");
    if (!RISKY_BASH.some((re) => re.test(cmd))) return;

    // No UI available (e.g. piped/non-interactive) -- block by default for safety.
    if (!ctx.hasUI) return { block: true, reason: "Risky command blocked: no UI available for confirmation" };

    const ok = await ctx.ui.confirm("Approve tool call?", `${event.toolName}: ${cmd.slice(0, 200)}`);
    if (!ok) {
      ctx.ui.notify("Command denied by approval hook", "error");
      return { block: true, reason: "Denied by approval hook" };
    }
    ctx.ui.notify("Command approved by approval hook", "success");
  });
}
