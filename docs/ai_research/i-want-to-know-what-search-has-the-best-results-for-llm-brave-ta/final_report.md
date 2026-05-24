# Final Report

## 1. Answer

**Brave Search API produces the best-quality results for LLM web research.** It leads the only rigorous independent benchmark (AIMultiple: Agent Score 14.89 vs Tavily 13.67, the sole statistically significant gap in the study), has the lowest latency (669ms vs 998ms), and operates the only independent 30B+ page web index available through a public API — meaning it is not dependent on scraping Google or Bing. Brave's February 2026 LLM Context API, which pre-extracts and relevance-ranks content chunks optimized for LLM consumption, largely closes the "AI-readiness" gap that previously favored Tavily. Internal evaluations show that open-weight models using Brave's grounding data can match or exceed frontier models using weaker context — indicating that search context quality, not model capability, is the binding constraint for LLM-grounded answers.

**However, a full switch from Tavily to Brave is not recommended.** Tavily has the broadest integration ecosystem (first-class support in all 10 major frameworks surveyed, including Vercel AI SDK and n8n where Brave is absent), richer agent-specific features (built-in answer synthesis, full-page extraction, multi-step research), and a genuinely free tier (1,000 credits/month, no credit card required). The community best practice and evidence from all seven sub-topics converge on a **dual-provider strategy**: use Brave's LLM Context API as the primary backend for research-quality web grounding, and keep Tavily as a secondary tool for quick interactive searches, prototyping, and framework-native integrations where its zero-boilerplate setup saves engineering time.

**Google PSE is not viable** (closed to new customers Jan 2026, full discontinuation Jan 2027). **Anthropic's web search is not a standalone API** — it is a Claude-native capability that uses Brave as its backend and only works with Anthropic models. For a general-purpose LLM agent stack, Brave and Tavily are the two options that matter.

## 2. Evidence Summary

| Finding | Source |
|---|---|
| Brave leads AIMultiple benchmark: Agent Score 14.89 vs Tavily 13.67 (statistically significant) | [Quality Benchmarks](reports/quality-benchmarks_report.md), [Tavily vs Brave](reports/tavily-vs-brave_report.md) |
| Brave latency 669ms vs Tavily 998ms — compounds in multi-step agent workflows | [Quality Benchmarks](reports/quality-benchmarks_report.md), [Tavily vs Brave](reports/tavily-vs-brave_report.md) |
| Brave's LLM Context API (Feb 2026) pre-extracts relevance-ranked content chunks for LLMs | [LLM-Specific Features](reports/llm-specific-features_report.md), [Search API Landscape](reports/search-api-landscape_report.md) |
| Brave operates independent 30B+ page index — no scraper dependency or legal risk | [Search API Landscape](reports/search-api-landscape_report.md), [Pricing](reports/pricing_report.md) |
| Brave offers Zero Data Retention + SOC 2 Type II — only compliant option for regulated industries | [Pricing](reports/pricing_report.md) |
| Tavily has first-class integrations in all 10 frameworks surveyed | [Integration Ecosystem](reports/integration-ecosystem_report.md) |
| Tavily is absent from Vercel AI SDK and n8n; Brave absent from Vercel AI SDK and n8n | [Integration Ecosystem](reports/integration-ecosystem_report.md) |
| Tavily acquired by Nebius (Feb 2026) — strategic uncertainty about pricing and roadmap | [Community Sentiment](reports/community-sentiment_report.md), [Quality Benchmarks](reports/quality-benchmarks_report.md) |
| Brave eliminated free tier Feb 2026 — replaced with $5/mo credit | [Pricing](reports/pricing_report.md), [Community Sentiment](reports/community-sentiment_report.md) |
| Tavily free tier: 1,000 credits/month, no credit card required | [Pricing](reports/pricing_report.md) |
| Google PSE closed to new customers Jan 2026, full shutdown Jan 2027 | [Pricing](reports/pricing_report.md) |
| Anthropic web search uses Brave as backend, Claude-only, not standalone | [LLM-Specific Features](reports/llm-specific-features_report.md) |
| Multi-provider architecture (fast + deep) is emerging community best practice | [Community Sentiment](reports/community-sentiment_report.md) |
| Brave's context quality enables cheaper models to match frontier-model results | [Quality Benchmarks](reports/quality-benchmarks_report.md), [Tavily vs Brave](reports/tavily-vs-brave_report.md) |
| Tavily's advanced search consumes 2 credits/call — doubles costs at scale | [Pricing](reports/pricing_report.md), [LLM-Specific Features](reports/llm-specific-features_report.md) |

## 3. Confidence Assessment

**High confidence** in the core findings. Multiple independent sources agree on Brave's quality lead: the AIMultiple benchmark (the most rigorous third-party evaluation available), multiple secondary analyses, and community consensus all converge. Primary sources (official API documentation, pricing pages, integration registries) back the feature and ecosystem claims. No credible contradictory evidence was found — the one tension (Tavily's Rhumb AN Score of 8.6 vs Brave's 7.1 on API reliability/developer experience) is complementary rather than contradictory, and is resolved by the dual-provider recommendation.

**Medium confidence** in the long-term strategic projections (Nebius acquisition impact, Google PSE timeline). These rely on current announcements and historical patterns, but corporate strategy can shift.

## 4. Limitations and Open Questions

- **Single benchmark snapshot**: The AIMultiple benchmark (Dec 2025) is a single-time-point measurement. Brave's LLM Context API launched after this benchmark and has not been independently re-evaluated against Tavily.
- **Query-type coverage**: No benchmark covers the full spectrum of research queries. Brave leads on general queries; Tavily may outperform on citation-heavy RAG; Exa may outperform on semantic/discovery search. The user should benchmark on their own query distribution.
- **Tavily acquisition uncertainty**: Nebius acquired Tavily in Feb 2026. Pricing changes, roadmap shifts, or strategic repositioning are plausible but unconfirmed.
- **AI SEO contamination**: Multiple community sources report degrading search quality across all providers due to AI-generated SEO spam. This is a systemic problem not addressed by any current search API.
- **Framework integration latency**: Integration support data is current as of May 2026. Framework ecosystems move fast — Brave may close the integration gap in the Vercel AI SDK and n8n within months.
- **No hands-on testing**: This research is based on published benchmarks, documentation, and community reports — not direct API testing with the user's specific research queries.
- **Serper.dev not deeply evaluated**: While identified as cheapest at scale, its Google-scraping dependency and legal risk were not researched as thoroughly as the Brave/Tavily comparison.

## 5. Bibliography

- AIMultiple. (2026). *Agentic search in 2026: Benchmark 8 search APIs for agents*. https://aimultiple.com/agentic-search
- Anthropic. (2026). *Web search tool*. https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool
- Awesome Agents. (2026). *Search API pricing compared 2026*. https://awesomeagents.ai/pricing/search-api-pricing/
- Brave Software. (2026, February 12). *Brave launches most powerful search API for AI to date*. https://brave.com/blog/most-powerful-search-api-for-ai
- Brave Software. (2026). *Brave Search API — LLM Context API documentation*. https://api-dashboard.search.brave.com/documentation/services/llm-context
- Brave Software. (2026, January 26). *Brave is the only search API offering true Zero Data Retention*. https://brave.com/blog/search-api-zero-data-retention/
- Composio. (2026). *Best AI search engine API tools for agents in 2026*. https://composio.dev/content/9-top-ai-search-engine-tools
- CrewAI. (2026). *Brave search tools*. https://docs.crewai.com/en/tools/search-research/bravesearchtool
- CrewAI. (2026). *Tavily search tool*. https://docs.crewai.com/en/tools/search-research/tavilysearchtool
- FindSkill.ai. (2026). *Web infrastructure for AI agents: Parallel vs Exa vs Tavily vs Brave*. https://findskill.ai/blog/web-infrastructure-for-ai-agents-parallel-vs-exa-tavily-brave
- Firecrawl. (2026). *Best web search APIs for AI applications in 2026*. https://www.firecrawl.dev/blog/best-web-search-apis
- Google. (2026). *Custom Search JSON API overview*. https://developers.google.com/custom-search/v1/overview
- LangChain. (2026). *Tavily search integration*. https://docs.langchain.com/oss/javascript/integrations/tools/tavily_search
- LangChain. (2026). *Brave search integration*. https://docs.langchain.com/oss/python/integrations/tools/brave_search
- LiteLLM. (2026). *Brave search*. https://docs.litellm.ai/docs/search/brave
- LiteLLM. (2026). *Tavily search*. https://docs.litellm.ai/docs/search/tavily
- Meneses González, K. (2026). *Comparing 10 AI-native search APIs and crawlers for LLM agents*. Towards Dev. https://medium.com/towardsdev/comparing-10-ai-native-search-apis-and-crawlers-for-llm-agents-ed4130d22c67
- Open WebUI. (2026). *Brave — Web search provider*. https://docs.openwebui.com/features/chat-conversations/web-search/providers/brave/
- Open WebUI. (2026). *Tavily — Web search provider*. https://docs.openwebui.com/features/chat-conversations/web-search/providers/tavily/
- Rhumb / supertrained. (2026, March 30). *Exa vs Tavily vs Serper vs Brave Search for AI agents — AN Score comparison*. https://dev.to/supertrained/exa-vs-tavily-vs-serper-vs-brave-search-for-ai-agents-an-score-comparison-2l1g
- Schuler, M. (2026, February 12). *Brave kills free Search API tier, shifts to metered billing*. The Implicator. https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing
- ScrapingBee. (2026). *8 best web search APIs for AI agents in 2026*. https://www.scrapingbee.com/blog/best-ai-search-api
- Tavily. (2026). *API documentation — Search endpoint*. https://docs.tavily.com/documentation/api-reference/endpoint/search
- Tavily. (2026). *Pricing*. https://www.tavily.com/pricing
- Vercel. (2026). *AI SDK tools registry*. https://ai-sdk.dev/resources/tools
- WebSearchAPI.ai. (2026). *Compare Tavily, Perplexity API, Google Search Grounding, Exa with LLM-as-Judge in LangSmith*. https://websearchapi.ai/blog/compare-tavily-google-search-exa-perplexity
- Webscraft. (2026, May 23). *Tavily vs Brave vs Exa: Which search API should you use for AI agents in 2026?* https://webscraft.org/blog/search-api-dlya-ai-agentiv-scho-obirayut-rozrobniki-i-de-pomilyayutsya?lang=en
- Zhang, Y., McKeown, K., & Muresan, S. (2026). *LiveNewsBench: Evaluating LLM Web Search Capabilities with Freshly Curated News*. arXiv:2602.13543. https://arxiv.org/abs/2602.13543
