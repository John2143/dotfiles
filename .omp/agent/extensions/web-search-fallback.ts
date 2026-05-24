// Web Search fallback extension — chains providers with automatic retry.
//
// Order: Brave → Tavily
// When the primary provider returns a rate-limit (429) or network error,
// the next provider in the chain is tried automatically. The model sees
// the final result as if it came from the first successful provider.
// Supported values: "brave", "tavily"
//
// Model-directed engine selection: prefix your query with [ENGINE: name],
// e.g. [ENGINE: tavily] latest research on LLM search quality. The tag is
// stripped before the query reaches the search API.

export default function (pi: any) {
  const PROVIDER_CHAIN = ["brave", "tavily"];

  pi.on("tool_call", async (event: any, ctx: any) => {
    if (event.tool !== "web_search") return;

    // Guard against recursion: skip if we're already inside a fallback retry.
    if (ctx.__wsf_active) return;
    ctx.__wsf_active = true;
    // Model-directed engine selection: [ENGINE: name] prefix override.
    // When present, overrides the fallback chain with the requested engine.
    const engineTag = event.args?.query?.match(/\[ENGINE:\s*(\w+)\]/i);
    let targetChain = PROVIDER_CHAIN;
    if (engineTag) {
      const requestedEngine = engineTag[1].toLowerCase();
      // Strip the tag from the query so the search API never sees it.
      event.args.query = event.args.query.replace(engineTag[0], "").trimStart();
      // If the requested engine is one we support, use it exclusively.
      if (PROVIDER_CHAIN.includes(requestedEngine)) {
        targetChain = [requestedEngine];
      }
      // Unknown engine: strip tag but fall through to normal chain.
    }

    let lastError: string | null = null;
    const cfg = ctx.config ?? ctx.settings ?? {};

    try {
      for (const provider of targetChain) {
        try {
          // Switch the search provider for this attempt
          const patchedCfg = { ...cfg };
          if (!patchedCfg.providers) patchedCfg.providers = {};
          patchedCfg.providers.webSearch = provider;

          // Run the native web_search with this provider
          const result = await ctx.tools.web_search.call(event.args, {
            ...ctx,
            config: patchedCfg,
          });

          // Success — return result to the model
          return { result };
        } catch (err: any) {
          const msg = err?.message ?? String(err);
          // Only fall through on rate limits or transient errors
          if (msg.includes("429") || msg.includes("rate") || msg.includes("limit") ||
              msg.includes("ETIMEDOUT") || msg.includes("ECONNREFUSED") ||
              msg.includes("ENOTFOUND") || msg.includes("fetch failed")) {
            lastError = msg;
            continue; // try next provider
          }
          // Hard error — rethrow so the model sees it
          throw err;
        }
      }

      // All providers failed — return error to model
      throw new Error(`web_search: all providers exhausted. Last error: ${lastError}`);
    } finally {
      delete ctx.__wsf_active;
    }
  });
}
