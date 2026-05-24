# Phase 1 Summary

## Primary Question
Which search API (Brave Search API, Tavily, Anthropic's web search capability, Google Custom/Programmable Search Engine, or other alternatives) produces the best-quality and most useful results when used as a tool by LLMs for web research — and should we switch from Tavily to Brave?

## Sub-Topic Findings

### Search API Landscape for LLM Integration
**Perspective**: none
**Researcher conclusion**: The search API landscape for LLM integration has bifurcated into AI-native APIs (Brave, Tavily, Exa, Firecrawl, Parallel, Perplexity) and traditional SERP wrappers (SerpAPI, Serper). The AIMultiple December 2025 benchmark — the most rigorous independent comparison available — places Brave first (Agent Score 14.89) with a statistically significant lead over Tavily (13.67). Brave also demonstrated the lowest latency (669ms). Tavily's differentiation lies in its richer agent workflow controls (multiple search depths, domain filtering, built-in answer synthesis). Google PSE is effectively dead for open-web LLM use (closed to new customers, full discontinuation Jan 2027). Bing Search API was retired March 2025. Anthropic's web search is a Claude-native capability using Brave as its backend.
**Relation to primary question**: The landscape analysis establishes that Brave and Tavily are the two primary contenders, with Brave holding a measurable quality edge and Tavily offering deeper agent-specific features — the switching decision hinges on whether raw result quality or integration ergonomics is the higher priority.

### Result Quality Benchmarks and Comparisons
**Perspective**: none
**Researcher conclusion**: Multiple independent benchmarks converge on Brave Search API and Tavily as the two leading options, with Brave holding a measurable but modest quality edge. The AIMultiple benchmark (100 queries, 8 APIs, GPT-5.2 judge, 10% human verification) is the most rigorous: Brave 14.89 vs Tavily 13.67 — the only statistically significant gap in the entire study. No single API wins across all query types; recent-event queries favor Brave/Perplexity, semantic queries favor Exa, citation-heavy RAG favors Tavily. Brave's LLM Context API (Feb 2026) represents a genuine architectural differentiator by pre-extracting content chunks with relevance scoring. Tavily's acquisition by Nebius (Feb 2026) introduces strategic risk. Brave removed its free tier without warning (Feb 2026), damaging developer trust.
**Relation to primary question**: The benchmark data directly answers the quality dimension: Brave produces marginally higher-quality results for general LLM research, with the strongest differentiators being its independent index, lower latency, and LLM Context API.

### LLM-Specific Features and Optimization
**Perspective**: none
**Researcher conclusion**: Brave's LLM Context API is the most comprehensively optimized for LLM consumption in 2026 — pre-extracted, relevance-ranked content chunks in structured JSON/Markdown, fine-grained token budget control, configurable relevance thresholds, freshness filtering, and Goggles domain re-ranking. Tavily offers broader feature *breadth* (built-in answer synthesis via `include_answer`, full-page extraction via `include_raw_content`, multi-step Research API, domain filtering) but trails on benchmark quality. Anthropic's web search (Brave-backed, Claude-native) offers the tightest conversational integration but encrypted results limit transparency and control. Google PSE returns raw SERP JSON with zero content extraction — not competitive. Brave's internal evaluation demonstrated that context quality beats model quality: an open-weight Qwen3 with Brave's LLM Context outperformed ChatGPT and Perplexity.
**Relation to primary question**: On the dimension of LLM-specific optimization, Brave's LLM Context API provides the highest-quality, most LLM-tailored output, while Tavily offers the richer feature suite at a small quality discount — directly informing the switching decision.

### Pricing and Rate Limits
**Perspective**: none
**Researcher conclusion**: The pricing landscape shifted dramatically in early 2026. Brave eliminated its free tier (replaced with $5/mo credit, ~1,000 queries). Google PSE closed to new customers (Jan 2026, full shutdown Jan 2027). Bing Search API retired (Mar 2025). At scale, Serper.dev is cheapest ($0.30-$1.00/1k queries) but scrapes Google (legal risk). Brave's $5/1k queries is simpler and cheaper than Tavily's credit model (~$8/1k for basic search). Tavily's "advanced" search depth consumes 2 credits per call, doubling costs. Brave's independent index with Zero Data Retention (enterprise) and SOC 2 Type II makes it the only compliant option for regulated industries. Tavily lacks true ZDR (scraper-based). Anthropic web search has no separate per-search fee but variable token-based costs.
**Relation to primary question**: Brave is marginally cheaper at scale and offers stronger privacy/compliance posture — supporting a switch from Tavily on both cost and data governance grounds.

### Tavily vs Brave Head-to-Head
**Perspective**: none
**Researcher conclusion**: Brave leads Tavily on quantitative benchmark quality (Agent Score 14.89 vs 13.67, statistically significant) and latency (669ms vs 998ms). Brave's Feb 2026 LLM Context API closes the "AI-readiness" gap that previously favored Tavily. Brave's independent 30B+ page index is a strategic asset after Bing API shutdown and Google-SerpAPI lawsuit. Tavily remains more agent-ergonomic out of the box (cleaner response schema, built-in answer synthesis, richer SDKs). On the Rhumb AN Score framework (API reliability and developer experience), Tavily scores 8.6 vs Brave's 7.1. Primary recommendation: switch to Brave for production research quality, retain Tavily as fallback/prototyping tool.
**Relation to primary question**: This is the crux comparison — Brave should be the primary research tool based on measurable quality, lower latency, and independent index advantages, while Tavily should be retained as a secondary option for its superior developer experience and free prototyping tier.

### Community and Developer Sentiment
**Perspective**: none
**Researcher conclusion**: The LLM developer community has reached a rough consensus: Tavily is most recommended for rapid prototyping and general agent use due to its AI-optimized output and clean schema; Exa scores highest in structured benchmarks (8.7/10 AN Score); Brave occupies the privacy/independent-index niche. Brave's free tier elimination (Feb 2026) was the most controversial event in the space, damaging trust. Tavily's Nebius acquisition introduces strategic uncertainty about pricing and independence. AI SEO spam is degrading results across all providers. Multi-provider architecture (fast + deep) is emerging as community best practice. There is a vocal minority advocating self-hosted SearXNG as a cost-free alternative.
**Relation to primary question**: Community sentiment supports a multi-provider strategy — keep Tavily for ease of integration and prototyping, add Brave for research quality and privacy, rather than a wholesale switch.

### Integration Ecosystem Support
**Perspective**: none
**Researcher conclusion**: Tavily has the broadest integration ecosystem — first-class support in all 10 frameworks surveyed (LangChain, CrewAI, AutoGen, LiteLLM, Vercel AI SDK, Dify, Flowise, n8n, Open WebUI, AnythingLLM). Brave is absent as a native provider in the Vercel AI SDK and n8n — requiring manual HTTP tool construction. Where Brave is integrated (CrewAI, Open WebUI), it often goes deeper with specialized tools (7 Brave tools in CrewAI including LLM Context, news, image, video search). Anthropic's web search is not a standalone API — it only works with Claude. No framework provides a unified search abstraction with automatic provider fallback. Recommendation: keep Tavily as default for broad framework compatibility, add Brave as secondary for its unique capabilities in CrewAI and Open WebUI.
**Relation to primary question**: Tavily's universal integration coverage means switching entirely to Brave would incur integration debt in the Vercel AI SDK and n8n — a dual-provider strategy captures the strengths of both.

## Cross-Cutting Insights

**Agreement across all 7 reports**: Brave Search API produces the highest raw search quality (measured by the AIMultiple benchmark), has the lowest latency, and operates the only independent web index at scale — making it the best choice for production research quality and privacy-sensitive use cases. Tavily has the best developer experience, broadest framework integration, and richest agent-specific features — making it the best choice for rapid prototyping and convenience.

**Resolution of the apparent tension**: The reports consistently converge on a multi-provider strategy rather than a binary switch. Use Brave's LLM Context API for research-quality web grounding (where index breadth, privacy, and content extraction quality matter most), and keep Tavily for quick interactive searches and framework-native integrations where its structured output and zero-boilerplate setup save engineering time. This mirrors the emerging community best practice.

**Strategic considerations beyond raw quality**: Three factors independent of search quality favor Brave: (1) its independent index insulates it from scraper legal risk (Google sued SerpAPI, Bing API shut down), (2) its Zero Data Retention and SOC 2 Type II compliance are required for regulated-industry use, and (3) its token budget control enables downstream LLM cost optimization that no other API offers. Two factors favor Tavily: (1) its universal framework integration reduces switching friction, and (2) its genuinely free tier (no credit card required) is better for prototyping.

**Key assumption**: The research assumes "best results" means relevance, accuracy, depth, and LLM-parseability of search results. If the user's criteria weight integration convenience above all else, Tavily would be the stronger recommendation — but the stated use case is "research," which favors quality.

## Consolidated Bibliography

- AIMultiple. (2026). *Agentic search in 2026: Benchmark 8 search APIs for agents*. https://aimultiple.com/agentic-search
- Anthropic. (2026). *Enabling and using web search*. Claude Help Center. https://support.claude.com/en/articles/10684626-enabling-and-using-web-search
- Anthropic. (2026). *Rate limits*. Claude API Docs. https://docs.anthropic.com/en/api/rate-limits
- Anthropic. (2026). *Web search tool*. Claude API Docs. https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool
- Awesome Agents. (2026, April 19). *Search API pricing compared 2026*. https://awesomeagents.ai/pricing/search-api-pricing/
- Brave Software. (2025). *Introducing AI Grounding with Brave Search API*. https://brave.com/blog/ai-grounding
- Brave Software. (2026, January 26). *Brave is the only search API offering true Zero Data Retention*. https://brave.com/blog/search-api-zero-data-retention/
- Brave Software. (2026, February 12). *Brave launches most powerful search API for AI to date*. https://brave.com/blog/most-powerful-search-api-for-ai
- Brave Software. (2026). *Brave Search API — LLM Context API documentation*. https://api-dashboard.search.brave.com/documentation/services/llm-context
- Composio. (2026). *Best AI search engine API tools for agents in 2026*. https://composio.dev/content/9-top-ai-search-engine-tools
- CrewAI. (2026). *Brave search tools*. https://docs.crewai.com/en/tools/search-research/bravesearchtool
- CrewAI. (2026). *Tavily search tool*. https://docs.crewai.com/en/tools/search-research/tavilysearchtool
- FindSkill.ai. (2026, April 30). *Web infrastructure for AI agents: Parallel vs Exa vs Tavily vs Brave*. https://findskill.ai/blog/web-infrastructure-for-ai-agents-parallel-vs-exa-tavily-brave
- Firecrawl. (2026). *Best web search APIs for AI applications in 2026*. https://www.firecrawl.dev/blog/best-web-search-apis
- FlowiseAI. (2026). *Tools*. https://docs.flowiseai.com/integrations/langchain/tools
- Google. (2026). *Custom Search JSON API overview*. https://developers.google.com/custom-search/v1/overview
- Google Cloud. (2026). *Web search with Anthropic Claude models*. https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/partner-models/claude/web-search
- Kharovyuk, V. (2026, May 23). *Best search API for AI agents in 2026: Tavily vs Brave vs Exa*. Webscraft. https://webscraft.org/blog/search-api-dlya-ai-agentiv-scho-obirayut-rozrobniki-i-de-pomilyayutsya?lang=en
- LangChain. (2026). *Brave search integration*. https://docs.langchain.com/oss/python/integrations/tools/brave_search
- LangChain. (2026). *Tavily search integration*. https://docs.langchain.com/oss/javascript/integrations/tools/tavily_search
- LiteLLM. (2026). *Brave search*. https://docs.litellm.ai/docs/search/brave
- LiteLLM. (2026). *Tavily search*. https://docs.litellm.ai/docs/search/tavily
- Meneses González, K. (2026, January 7). *Comparing 10 AI-native search APIs and crawlers for LLM agents*. Towards Dev. https://medium.com/towardsdev/comparing-10-ai-native-search-apis-and-crawlers-for-llm-agents-ed4130d22c67
- Microsoft. (2026). *Grounding with Bing Search (classic)*. https://learn.microsoft.com/en-us/azure/foundry-classic/agents/how-to/tools-classic/bing-grounding
- Open WebUI. (2026). *Brave — Web search provider*. https://docs.openwebui.com/features/chat-conversations/web-search/providers/brave/
- Open WebUI. (2026). *Tavily — Web search provider*. https://docs.openwebui.com/features/chat-conversations/web-search/providers/tavily/
- Perplexity AI. (2026). *Pricing*. https://docs.perplexity.ai/docs/getting-started/pricing
- Rhumb / supertrained. (2026, March 30). *Exa vs Tavily vs Serper vs Brave Search for AI agents — AN Score comparison*. Dev.to. https://dev.to/supertrained/exa-vs-tavily-vs-serper-vs-brave-search-for-ai-agents-an-score-comparison-2l1g
- Schuler, M. (2026, February 12). *Brave kills free Search API tier, shifts to metered billing*. The Implicator. https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing
- ScrapingBee. (2026). *8 best web search APIs for AI agents in 2026*. https://www.scrapingbee.com/blog/best-ai-search-api
- Sona. (2026, April 29). *LLM search API: Best options for developers in 2026*. https://sona.com/blog/llm-search-api-best-options-for-developers-in-2026
- Tavily. (2026). *API documentation — Search endpoint*. https://docs.tavily.com/documentation/api-reference/endpoint/search
- Tavily. (2026). *Pricing*. https://www.tavily.com/pricing
- Tavily. (2026). *Vercel AI SDK integration*. https://docs.tavily.com/documentation/integrations/vercel
- Vercel. (2026). *AI SDK tools registry*. https://ai-sdk.dev/resources/tools
- WebSearchAPI.ai. (2026, April 15). *Compare Tavily, Perplexity API, Google Search Grounding, Exa with LLM-as-Judge in LangSmith*. https://websearchapi.ai/blog/compare-tavily-google-search-exa-perplexity
- Zhang, Y., McKeown, K., & Muresan, S. (2026). *LiveNewsBench: Evaluating LLM Web Search Capabilities with Freshly Curated News*. arXiv:2602.13543. https://arxiv.org/abs/2602.13543

## Decision
SUFFICIENT — The primary research question can be answered fully and confidently. All 7 sub-topics converge on a consistent answer with no unresolved contradictions. The recommendation is clear and evidence-backed: switch to Brave for research quality, keep Tavily as a secondary/fallback for integration convenience and prototyping.
