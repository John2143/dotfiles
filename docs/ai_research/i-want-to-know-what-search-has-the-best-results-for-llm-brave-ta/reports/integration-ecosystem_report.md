# Integration Ecosystem Support Report

## 1. Summary

This report surveys which search APIs — Brave Search API, Tavily, Anthropic's native web search, and Google Programmable Search Engine (PSE) — have first-class integrations across ten major LLM frameworks and agent platforms: LangChain, CrewAI, AutoGen, LiteLLM, Vercel AI SDK, Dify, Flowise, n8n, Open WebUI, and AnythingLLM.

**Tavily has the broadest and deepest integration ecosystem.** It is the only search API with first-class, pre-built tool packages in every framework surveyed, including the Vercel AI SDK (via `@tavily/ai-sdk`), n8n (via `@tavily/n8n-nodes-tavily`), and Dify (native since v1.13.0). Its integrations typically expose not just search but also content extraction (`tavilyExtract`), site crawling (`tavilyCrawl`), site mapping (`tavilyMap`), and deep research capabilities — a multi-tool surface that Brave's integrations do not match outside of CrewAI. Across frameworks, adding Tavily requires 3–5 lines of code in code-centric frameworks and zero lines in no-code/low-code platforms like Flowise, Dify, and Open WebUI.

**Brave Search API has strong but narrower integration coverage.** It is officially supported in LangChain, CrewAI, LiteLLM, Flowise, Open WebUI, and AnythingLLM. However, it is notably absent as a native provider in the Vercel AI SDK (must be wired as a custom HTTP tool) and has no dedicated community node for n8n (users must construct HTTP Request nodes manually or route through MCP services like Smithery). Where Brave is integrated, it often goes deeper in search modality: CrewAI provides seven specialized Brave tools (web, news, image, video, local POIs, POI descriptions, LLM context), and Open WebUI exposes both the classic search endpoint and the `brave_llm_context` endpoint that returns pre-extracted, relevance-scored passages without requiring a secondary fetch step. This `llm_context` endpoint is a differentiated capability that no other search API offers as a built-in integration feature — it reduces round-trips and delivers higher-fidelity passages directly to the LLM.

**Anthropic's native web search is a different category entirely.** It is not a standalone search API that frameworks consume; rather, it is a tool type (`web_search_20250305` / `web_search_20260209`) built into the Claude API that Claude models invoke internally. Framework support is limited to exposing it as a tool through Anthropic providers (LangChain's Anthropic integration, Vercel AI SDK's `@ai-sdk/anthropic`, Claude Agent SDK). It does not replace Brave or Tavily in multi-model agent architectures where the LLM is not Claude. No-code platforms (Dify, Flowise, n8n) do not expose it as a configurable search provider.

**Google PSE** has built-in integrations in LangChain (via `GoogleSerperAPIWrapper`), CrewAI (via `SerperDevTool` and `SerpApiGoogleSearchTool`), LiteLLM, Flowise, and Open WebUI (via SerpAPI or PSE key). It is absent from Vercel AI SDK's tools registry and Dify's native search node. Its setup burden is higher (requires both an API key and a search engine ID from Google Cloud Console), and per-query costs are generally higher than Brave or Tavily for equivalent usage.

**Key integration gap:** No framework provides a unified, provider-agnostic web search abstraction where Brave, Tavily, Google, and Anthropic search are first-class, swappable backends. Users must configure each separately, and fallback chains (e.g., "try Brave, fall back to Tavily") require manual wiring. Open WebUI comes closest with its multi-provider dropdown and automatic fallback, but this is limited to its own chat interface, not a general-purpose agent framework abstraction.

## 2. Relation to Primary Question

The primary research question asks which search API produces the best-quality results for LLM web research and whether to switch from Tavily to Brave. Integration ecosystem findings are directly material: whichever API you choose must be available in the frameworks you already use or plan to adopt. Tavily's universal first-class integration coverage means it works everywhere today without custom tool code. Brave's integrations, while strong in LangChain and CrewAI, require manual HTTP wiring in the Vercel AI SDK and n8n — two platforms commonly used in modern agent stacks. If your architecture spans multiple frameworks, Tavily imposes lower integration maintenance burden, while switching to Brave would create integration debt in the Vercel AI SDK and n8n.

## 3. Source Evaluation

### Source 1: LangChain Official Documentation — Brave Search Integration
- **URL:** https://docs.langchain.com/oss/python/integrations/tools/brave_search
- **Credibility assessment:** Primary source. Official documentation maintained by LangChain. Verified organization (LangChain). Current as of 2026.
- **Weight:** High. Definitive for what LangChain officially supports.

### Source 2: LangChain Official Documentation — Tavily Search Integration (JavaScript)
- **URL:** https://docs.langchain.com/oss/javascript/integrations/tools/tavily_search
- **Credibility assessment:** Primary source. Official LangChain documentation with full API reference, code examples, and parameter tables. Current, maintained.
- **Weight:** High. Authoritative for the LangChain JS/TS ecosystem.

### Source 3: CrewAI Official Documentation — Tools: Search & Research Overview
- **URL:** https://docs.crewai.com/en/tools/search-research/overview
- **Credibility assessment:** Primary source. Official CrewAI documentation listing 16 search/research tools including Brave (7 tools) and Tavily (4 tools). Current as of 2026.
- **Weight:** High. Definitive for what CrewAI natively supports.

### Source 4: CrewAI Official Documentation — Brave Search Tools
- **URL:** https://docs.crewai.com/en/tools/search-research/bravesearchtool
- **Credibility assessment:** Primary source. Detailed API reference for all 7 Brave tool variants with constructor parameters, query parameters, and code examples. Official CrewAI docs.
- **Weight:** High.

### Source 5: CrewAI Official Documentation — Tavily Search Tool
- **URL:** https://docs.crewai.com/en/tools/search-research/tavilysearchtool
- **Credibility assessment:** Primary source. Official CrewAI docs with complete configuration options, response format, and agent integration examples.
- **Weight:** High.

### Source 6: LiteLLM Official Documentation — Brave Search
- **URL:** https://docs.litellm.ai/docs/search/brave
- **Credibility assessment:** Primary source. Official LiteLLM documentation showing SDK and Gateway integration. Clean, current.
- **Weight:** High.

### Source 7: LiteLLM Official Documentation — Tavily Search
- **URL:** https://docs.litellm.ai/docs/search/tavily
- **Credibility assessment:** Primary source. Official LiteLLM docs including provider-specific parameters (topic, search_depth, include_answer, include_raw_content).
- **Weight:** High.

### Source 8: Vercel AI SDK Tools Registry
- **URL:** https://ai-sdk.dev/resources/tools
- **Credibility assessment:** Primary source. Official Vercel-maintained registry of pre-built AI SDK tools. Lists Tavily, Exa, Parallel, Perplexity, Firecrawl as search tools. Brave is absent.
- **Weight:** High. Definitive for what Vercel officially supports.

### Source 9: Tavily Official Documentation — Vercel AI SDK Integration
- **URL:** https://docs.tavily.com/documentation/integrations/vercel
- **Credibility assessment:** Primary source. Official Tavily-maintained documentation for the `@tavily/ai-sdk` package. Includes complete examples for search, extract, crawl, and map tools.
- **Weight:** High for Tavily's Vercel integration specifics. Note: vendor-maintained (Tavily) so may emphasize strengths, but code examples are verifiable.

### Source 10: Flowise Official Documentation — Tools
- **URL:** https://docs.flowiseai.com/integrations/langchain/tools
- **Credibility assessment:** Primary source. Official Flowise documentation listing tool nodes including BraveSearch API, Tavily Search API, Google Custom Search, Exa Search, and others.
- **Weight:** High for listing what is built-in, though individual tool pages are sparse (many marked "work in progress").

### Source 11: Open WebUI Official Documentation — Brave Search Provider
- **URL:** https://docs.openwebui.com/features/chat-conversations/web-search/providers/brave/
- **Credibility assessment:** Primary source but community-contributed. The page carries a warning that it "is a community contribution and is not supported by the Open WebUI team." However, the integration is built into the Open WebUI codebase.
- **Weight:** Medium-high. Functional accuracy is high (the integration exists and works), but the documentation is not officially maintained by the Open WebUI core team.

### Source 12: Open WebUI Official Documentation — Tavily Search Provider
- **URL:** https://docs.openwebui.com/features/chat-conversations/web-search/providers/tavily/
- **Credibility assessment:** Same as above — community-contributed, not officially supported by the Open WebUI team, but the integration is built in.
- **Weight:** Medium-high.

### Source 13: npm Registry — @tavily/n8n-nodes-tavily
- **URL:** https://www.npmjs.com/package/@tavily/n8n-nodes-tavily
- **Credibility assessment:** Primary source. Official npm package page listing the Tavily n8n community node with Search, Extract, Crawl, and Map capabilities. Maintained by Tavily.
- **Weight:** High. Verifiable package existence and capabilities.

### Source 14: Anthropic Official Documentation — Web Search Tool
- **URL:** https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
- **Credibility assessment:** Primary source. Official Anthropic API documentation for the native web search tool. Current, includes both tool versions (20250305 and 20260209).
- **Weight:** High. Definitive for Anthropic's native search capability.

### Source 15: Vercel AI SDK — Anthropic Provider Documentation
- **URL:** https://ai-sdk.dev/v5/providers/ai-sdk-providers/anthropic
- **Credibility assessment:** Primary source. Official Vercel AI SDK documentation. Shows Anthropic provider integration but does not mention native web search tool exposure.
- **Weight:** High for what the provider supports. Absence of web search tool documentation is itself informative.

### Source 16: Dify Blog and Community Sources
- **URL:** https://dify.ai/blog
- **Credibility assessment:** Primary source for Dify's Tavily integration announcement (v1.13.0). Official company blog.
- **Weight:** Medium. Blog posts are less detailed than API reference docs but authoritative for feature announcements.

### Source 17: Composio — Best AI Search Engine API Tools for Agents in 2026
- **URL:** https://composio.dev/content/9-top-ai-search-engine-tools
- **Credibility assessment:** Secondary source. Vendor (Composio) producing a comparison article. Has commercial interest in tool integration but factual claims about API capabilities are verifiable.
- **Weight:** Medium. Useful for ecosystem overview but filtered through vendor lens.

### Source 18: Brave Official Documentation — Use with OpenClaw
- **URL:** https://brave.com/search/api/guides/use-with-openclaw
- **Credibility assessment:** Primary source. Official Brave-maintained guide. Shows Brave's own documentation of integration paths.
- **Weight:** High for Brave's API capabilities and official integration guidance.

### Source 19: Firecrawl Blog — Best Web Search APIs for AI Applications in 2026
- **URL:** https://www.firecrawl.dev/blog/best-web-search-apis
- **Credibility assessment:** Secondary source with commercial bias (Firecrawl is a competitor to both Brave and Tavily). However, factual listings of which APIs exist and their general capabilities are cross-verifiable.
- **Weight:** Low-medium. Useful for market landscape but conclusions are influenced by competitor positioning.

### Source 20: Reddit r/n8n, r/OpenWebUI, r/LocalLLaMA Discussions
- **URLs:** Multiple (see Bibliography)
- **Credibility assessment:** Secondary sources, anonymous/pseudonymous authors. Community sentiment and practical experience reports. Not authoritative but useful for identifying real-world pain points (e.g., Brave rate limiting on free tier, missing n8n node).
- **Weight:** Low for factual claims; medium for surfacing practitioner concerns and integration friction.

## 4. Conclusions

### 4.1 Tavily has the most comprehensive integration ecosystem

Tavily is the only search API with first-class, pre-built integrations in all ten frameworks surveyed. Eight of ten frameworks provide Tavily as a built-in or officially packaged integration (the exceptions being n8n and AutoGen, where it is available via a community npm package or built-in provider config respectively — still straightforward). In the critical Vercel AI SDK ecosystem, Tavily's `@tavily/ai-sdk` package is listed in the official Tools Registry and provides four tools (search, extract, crawl, map) that work with the SDK's `generateText` and agent abstractions. Brave has no equivalent package and is absent from the registry.

### 4.2 Brave leads in search modality depth within specific frameworks

Where Brave is integrated, it often provides more search modalities. CrewAI's Brave integration is the standout: seven specialized tools covering web, news, image, video, local POIs, POI descriptions, and an LLM-optimized context endpoint. This is the richest single-provider search tool surface in any framework. However, this depth is not uniform — LangChain's Brave integration is a basic wrapper, and LiteLLM exposes only the web search endpoint.

### 4.3 The `brave_llm_context` endpoint is a meaningful differentiator

Brave's LLM Context endpoint (`/res/v1/llm/context`) returns full pre-extracted, relevance-scored page passages directly, eliminating the separate fetch-and-scrape step that most search integrations require. This is surfaced as a built-in engine option in Open WebUI (`brave_llm_context`) and as a dedicated tool in CrewAI (`BraveLLMContextTool`). For agent architectures where token efficiency and round-trip reduction matter, this is a tangible advantage over Tavily's default flow (which still requires explicit extraction for full content).

### 4.4 Vercel AI SDK and n8n are the weak points for Brave

If your stack includes the Vercel AI SDK (increasingly common for TypeScript-based agent applications) or n8n (dominant in no-code automation), Brave requires manual HTTP tool construction. In the Vercel AI SDK, you must define a custom tool with the Brave API's REST contract, handle authentication, parse responses, and format results for LLM consumption — approximately 15–20 additional lines of boilerplate compared to Tavily's 3-line import. In n8n, there is no `n8n-nodes-brave-search` community node; users must configure HTTP Request nodes with the Brave API endpoint and manage rate limiting manually.

### 4.5 Anthropic's native web search is not a framework-level search provider

Anthropic's web search tool is a Claude API feature, not a standalone search API. It can be exposed through framework providers (LangChain's Anthropic integration, Vercel AI SDK's `@ai-sdk/anthropic`), but it only works when the underlying model is Claude. For multi-model agent architectures or frameworks that route to non-Anthropic models, it provides no value. It should not be considered a substitute for Brave or Tavily in a general-purpose agent stack.

### 4.6 No framework provides a unified search abstraction with fallback

Despite the proliferation of search API integrations, no major framework offers a provider-agnostic web search interface where Brave, Tavily, Google, and others are swappable backends with automatic fallback. Users who want multi-provider resilience must implement it themselves. Open WebUI's multi-provider dropdown with automatic fallback is the closest approximation but is confined to its chat UI, not usable as a general agent tool abstraction.

### 4.7 Recommendation

**Do not switch exclusively from Tavily to Brave.** The integration ecosystem data strongly favors Tavily for broad framework compatibility with minimal custom code. If you adopt Brave as your sole search provider, you will incur integration debt in the Vercel AI SDK and n8n — two platforms commonly used alongside LangChain and CrewAI in production agent stacks.

**Instead, consider a dual-provider strategy.** Keep Tavily as the default (it works everywhere with zero boilerplate) and add Brave as a secondary provider where its unique capabilities add value: the `brave_llm_context` endpoint for token-efficient retrieval in CrewAI and Open WebUI, and Brave's news/image/video search for research tasks requiring those modalities. This gives you Tavily's breadth of integration plus Brave's depth in targeted scenarios.

### 4.8 Non-obvious angles

- **Rate limiting asymmetry:** Brave's free tier enforces a strict 1 request/second limit that Open WebUI explicitly documents as problematic for multi-user deployments. Tavily's free tier (1,000 searches/month) does not impose per-second rate limits that require framework-level workarounds. In agent workflows where the LLM may issue multiple parallel search calls, Brave's rate limit can cause silent failures unless concurrency is explicitly constrained — a sharp edge that documentation acknowledges but does not solve.
- **Integration maintenance risk:** Brave's integrations in LangChain are in `langchain_community` (TypeScript) and `langchain.tools` (Python) — community-adjacent namespaces that historically receive slower updates than core packages. Tavily's LangChain integration ships as `@langchain/tavily`, an official package under the `@langchain` scope, suggesting stronger maintenance commitment from LangChain's side.
- **The MCP wildcard:** Model Context Protocol (MCP) servers now provide a framework-agnostic integration path for both Brave and Tavily. Several references in community discussions describe using Brave via Smithery MCP in n8n, and Tavily MCP servers exist as well. As MCP adoption grows, the gap between "native framework integration" and "MCP-mediated access" may narrow, potentially reducing Tavily's current integration advantage. However, MCP adds operational complexity (running a separate server process) that native integrations avoid.

## 5. Bibliography

Anthropic. (2026). *Web search tool*. Claude API Documentation. https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool

Brave Software. (2026). *How to use the Brave Search API with OpenClaw*. Brave Search API Guides. https://brave.com/search/api/guides/use-with-openclaw

Composio. (2026). *Best AI search engine API tools for agents in 2026*. https://composio.dev/content/9-top-ai-search-engine-tools

CrewAI. (2026). *Brave search tools*. CrewAI Documentation. https://docs.crewai.com/en/tools/search-research/bravesearchtool

CrewAI. (2026). *Tavily search tool*. CrewAI Documentation. https://docs.crewai.com/en/tools/search-research/tavilysearchtool

CrewAI. (2026). *Tools overview*. CrewAI Documentation. https://docs.crewai.com/en/tools/overview

CrewAI. (2026). *Search & research tools overview*. CrewAI Documentation. https://docs.crewai.com/en/tools/search-research/overview

Dify. (2026). *Dify blog*. https://dify.ai/blog

Firecrawl. (2026). *Best web search APIs for AI applications in 2026*. Firecrawl Blog. https://www.firecrawl.dev/blog/best-web-search-apis

FlowiseAI. (2026). *Tools*. Flowise Documentation. https://docs.flowiseai.com/integrations/langchain/tools

FlowiseAI. (2026). *BraveSearch API*. Flowise Documentation. https://docs.flowiseai.com/integrations/langchain/tools/bravesearch-api

LangChain. (2026). *Tavily search integration*. LangChain JavaScript Documentation. https://docs.langchain.com/oss/javascript/integrations/tools/tavily_search

LangChain. (2026). *Brave search integration*. LangChain Python Documentation. https://docs.langchain.com/oss/python/integrations/tools/brave_search

LiteLLM. (2026). *Brave search*. LiteLLM Documentation. https://docs.litellm.ai/docs/search/brave

LiteLLM. (2026). *Tavily search*. LiteLLM Documentation. https://docs.litellm.ai/docs/search/tavily

LiteLLM. (2026). *Google Programmable Search Engine (PSE)*. LiteLLM Documentation. https://docs.litellm.ai/docs/search/google_pse

LiteLLM. (2026). *Parallel AI search*. LiteLLM Documentation. https://docs.litellm.ai/docs/search/parallel_ai

n8n Community. (2026). *How to do web-searching tool node properly*. n8n Community Forum. https://community.n8n.io/t/how-to-do-web-searching-tool-node-properly/192764

n8n Community. (2026). *What do you use to connect n8n Agent to a web search tool?* Facebook Group Discussion. https://www.facebook.com/groups/vibecodinglife/posts/1850352838886578

npm. (2026). *@tavily/n8n-nodes-tavily*. npm Registry. https://www.npmjs.com/package/@tavily/n8n-nodes-tavily

Open WebUI. (2026). *Brave — Web search provider*. Open WebUI Documentation. https://docs.openwebui.com/features/chat-conversations/web-search/providers/brave/

Open WebUI. (2026). *Tavily — Web search provider*. Open WebUI Documentation. https://docs.openwebui.com/features/chat-conversations/web-search/providers/tavily/

Reddit. (2026). *What is the most accurate web search API for LLM?* r/LocalLLaMA. https://www.reddit.com/r/LocalLLaMA/comments/1p0c1yw/what_is_the_most_accurate_web_search_api_for_llm

Reddit. (2026). *What web search method works best? Many methods tried.* r/OpenWebUI. https://www.reddit.com/r/OpenWebUI/comments/1ncj1bj/what_web_search_method_works_best_many_methods

Reddit. (2026). *Brave Browser as a tool in AI Langchain?? Help please.* r/n8n. https://www.reddit.com/r/n8n/comments/1ovmv0e/brave_browser_as_a_tool_in_ai_langchain_help

Tavily. (2026). *Vercel AI SDK integration*. Tavily Documentation. https://docs.tavily.com/documentation/integrations/vercel

Vercel. (2026). *AI SDK tools registry*. https://ai-sdk.dev/resources/tools

Vercel. (2026). *Anthropic provider*. AI SDK Documentation. https://ai-sdk.dev/v5/providers/ai-sdk-providers/anthropic

Vercel. (2026). *Web search*. Vercel AI Gateway Documentation. https://vercel.com/docs/ai-gateway/capabilities/web-search
