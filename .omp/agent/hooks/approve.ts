// @ts-nocheck
// Approval hook for risky tool calls.
//
// Triggers an interactive confirm dialog before executing:
//   - bash commands matching known-risky patterns
//   - write/edit calls (optional; comment out if too noisy)
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

function isRisky(toolName: string, args: Record<string, unknown>): boolean {
  if (toolName === "bash") {
    const cmd = String(args?.command ?? "");
    return RISKY_BASH.some((re) => re.test(cmd));
  }
  // Uncomment to also gate writes:
  // if (toolName === "write" || toolName === "edit") return true;
  return false;
}

function summarize(toolName: string, args: Record<string, unknown>): string {
  if (toolName === "bash") return String(args?.command ?? "").slice(0, 200);
  if (toolName === "write" || toolName === "edit") return String(args?.path ?? args?.file ?? "");
  try { return JSON.stringify(args).slice(0, 200); } catch { return ""; }
}

export default function approveDangerous(pi: { on: (event: string, handler: (...args: unknown[]) => void) => void }) {
  pi.on("tool_call", async (event: { toolName: string; args: Record<string, unknown> }, ctx: { ui?: { confirm?: (opts: { title: string; message: string; timeout: number }) => Promise<boolean> } }) => {
    if (!isRisky(event.toolName, event.args)) return;

    const ok = await ctx?.ui?.confirm?.({
      title: "Approve tool call?",
      message: `${event.toolName}: ${summarize(event.toolName, event.args)}`,
      timeout: 60_000,
    });

    if (!ok) {
      // DRAFT: rejection shape is unverified. Throw is a reasonable
      // first guess given how OMP wraps tool errors elsewhere
      // (`ToolError` thrown -> tool result marked isError). Adjust
      // after running once if this doesn't actually block execution.
      throw new Error("Denied by approval hook");
    }
  });
}
