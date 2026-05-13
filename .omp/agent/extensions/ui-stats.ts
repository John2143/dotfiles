// UI stats extension — timestamps in chat, timing in widget, tokens/sec in footer.
//
// Chat: injects timestamp banners via `before_agent_start`.
// Widget: shows turn timing + token speed below the editor via `setWidget`.
// Footer: registers a segment showing live tokens/sec via OMP's built-in computation.

export default function (pi: any) {
  let turnStartMs = 0;
  let currentTurn = 0;
  let agentStartMs = 0;
  let totalAgentTurns = 0;
  let widgetText = "";

  // ============================================================
  // Helpers
  // ============================================================

  function isoNow(): string {
    return new Date().toISOString().replace("T", " ").slice(0, 19);
  }

  function formatDuration(ms: number): string {
    if (ms < 1000) return Math.round(ms) + "ms";
    const s = ms / 1000;
    if (s < 60) return s.toFixed(1) + "s";
    const min = Math.floor(s / 60);
    return min + "m " + (s % 60).toFixed(0) + "s";
  }

  function formatTokens(n: number): string {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
    if (n >= 1000) return (n / 1000).toFixed(1) + "k";
    // Round small floats to avoid 29.77605404729138/s
    return n < 10 ? n.toFixed(1) : String(Math.round(n));
  }

  function extractUsage(obj: any): { input: number; output: number } | null {
    if (!obj) return null;
    const u = obj.usage ?? obj.usage_ ?? obj.tokenUsage ?? obj.token_usage;
    if (u) {
      const input = u.inputTokens ?? u.input_tokens ?? u.promptTokens ?? u.prompt_tokens ?? u.input ?? 0;
      const output = u.outputTokens ?? u.output_tokens ?? u.completionTokens ?? u.completion_tokens ?? u.output ?? 0;
      if (input + output > 0) return { input, output };
    }
    const input = obj.inputTokens ?? obj.input_tokens ?? obj.promptTokens ?? obj.prompt_tokens ?? 0;
    const output = obj.outputTokens ?? obj.output_tokens ?? obj.completionTokens ?? obj.completion_tokens ?? 0;
    if (input + output > 0) return { input, output };
    return null;
  }

  function updateWidget(ctx: any): void {
    if (!widgetText) {
      ctx.ui.setWidget("ui-stats", undefined);
      return;
    }
    const dim = "\x1b[2m";
    const reset = "\x1b[0m";
    ctx.ui.setWidget("ui-stats", [`${dim}${widgetText}${reset}`], { placement: "belowEditor" });
  }

  // ============================================================
  // Hook handlers
  // ============================================================

  pi.on("session_start", async (_event: any, ctx: any) => {
    // Footer segment — live tokens/sec from OMP's built-in computation
    if (typeof ctx.ui.registerStatusLineSegment === "function") {
      ctx.ui.registerStatusLineSegment("ext-tps", {
        render(_ctx: any) {
          const tps = _ctx?.usageStats?.tokensPerSecond;
          if (!tps || tps <= 0) return { content: "", visible: false };
          const dim = "\x1b[2m";
          const reset = "\x1b[0m";
          return { content: `${dim}⏱ ${formatTokens(tps)}/s${reset}`, visible: true };
        }
      });
    }
    // No widget until a turn starts
  });

  pi.on("turn_start", async (event: any, ctx: any) => {
    turnStartMs = event.timestamp ?? Date.now();
    currentTurn = event.turnIndex ?? 0;
    widgetText = `turn ${currentTurn + 1} · thinking…`;
    updateWidget(ctx);
  });

  pi.on("turn_end", async (event: any, ctx: any) => {
    const elapsed = Date.now() - turnStartMs;
    const usage = extractUsage(event.message) ?? extractUsage(event);

    let extra = "";
    if (usage && usage.input + usage.output > 0) {
      const total = usage.input + usage.output;
      const tps = elapsed > 0 ? Math.round(total / (elapsed / 1000)) : 0;
      extra = ` · ${formatTokens(tps)} tok/s`;
    }

    widgetText = `turn ${currentTurn + 1} · ${formatDuration(elapsed)}${extra}`;
    updateWidget(ctx);
  });

  pi.on("agent_start", async (_event: any, _ctx: any) => {
    agentStartMs = Date.now();
    totalAgentTurns = 0;
  });

  pi.on("agent_end", async (event: any, ctx: any) => {
    const elapsed = Date.now() - agentStartMs;
    totalAgentTurns = currentTurn + 1;

    let totalInput = 0;
    let totalOutput = 0;
    if (Array.isArray(event?.messages)) {
      for (const msg of event.messages) {
        const u = extractUsage(msg);
        if (u) { totalInput += u.input; totalOutput += u.output; }
      }
    }

    let tokText = "";
    if (totalInput + totalOutput > 0) {
      const tps = elapsed > 0 ? Math.round((totalInput + totalOutput) / (elapsed / 1000)) : 0;
      tokText = ` · ${formatTokens(totalInput + totalOutput)} tok (${formatTokens(tps)}/s)`;
    }

    widgetText = `${totalAgentTurns} turns · ${formatDuration(elapsed)}${tokText}`;
    updateWidget(ctx);
  });

  pi.on("session_shutdown", async (_event: any, ctx: any) => {
    ctx.ui.setWidget("ui-stats", undefined);
  });
}
