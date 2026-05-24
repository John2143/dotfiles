# Pricing Models, Free Tiers, Rate Limits, and Quota Structures Across LLM Search APIs

## 1. Summary

The landscape of search APIs for LLM grounding shifted dramatically between Q4 2025 and Q2 2026. Brave Search API eliminated its traditional free tier (previously 2,000–5,000 free queries/month) in February 2026, replacing it with $5/month in credits (~1,000 queries) that require public attribution and a credit card on file. Google closed its Custom Search JSON API to new customers entirely as of January 2026, with full discontinuation set for January 2027. Microsoft retired the Bing Search API in March 2025. These closures leave Brave as the only provider operating its own independent, full-scale Western web index available through a public API — a position that gives it significant pricing power.

For raw cost-per-query at scale, Serper.dev dominates: $0.30–$1.00 per 1,000 queries depending on volume tier, with a generous 2,500 free monthly queries. Tavily — purpose-built for AI agents with relevance scoring and answer synthesis — charges $0.008/credit (approximately $8/1,000 queries for basic search), but its credit model is more complex: a single search consumes 1–2 credits, while multi-step research tasks consume 4–250 credits. Anthropic's web search tool is not a standalone API; it is embedded in Claude's tool-use system and billed solely through token consumption at standard model rates with no separate per-search charge — making its effective cost highly variable depending on model choice and search complexity. Perplexity's Sonar API charges both per-request ($5–$14/1k depending on context depth) and per-token, creating a combined cost structure that is among the most expensive of the group.

The key structural divide is between providers that operate their own web index (only Brave at scale) and those that scrape Google/Bing results (Tavily, Serper, SerpAPI, ValueSerp). Scraper-based APIs carry latent legal risk — Google has already sued SerpAPI — and cannot offer true Zero Data Retention (ZDR) because user queries transit through Big Tech infrastructure. Brave offers ZDR for enterprise customers and SOC 2 Type II compliance, making it the only search API suitable for regulated-industry deployments (healthcare, finance, legal) where query privacy is a compliance requirement. Tavily, acquired by Nebius in 2026, offers GDPR-compliant practices but relies on scraped data, so its ZDR guarantees are inherently limited.

Free tier rankings for development work: Serper (2,500 queries/month) and Brave ($5 credit ≈ 1,000 queries/month) lead, followed by Tavily (1,000 credits/month) and Exa (1,000 queries/month). SerpAPI (100/month) and ValueSerp (100/month) free tiers are too small for meaningful development.

## 2. Relation to Primary Question

The choice between Brave and Tavily hinges on whether cost predictability, data sovereignty, and query privacy matter more than Tavily's pre-processed, agent-optimized result format. For sensitive or high-volume research use, Brave's flat $5/1k pricing, independent index, and ZDR capability make it the stronger long-term choice; for rapid prototyping where agent-native result filtering reduces engineering time, Tavily's SDK integrations and relevance scoring justify its 1.6× cost premium over Brave's base rate.

## 3. Source Evaluation

### Primary Sources (Official Provider Documentation)

1. **Brave Search API Blog — "Brave launches most powerful search API for AI to date"**
   - URL: https://brave.com/blog/most-powerful-search-api-for-ai/
   - Credibility: Primary. Official Brave company blog post dated February 12, 2026, announcing the pricing restructure and LLM Context API launch. Contains the exact pricing tiers, rate limits, and terms. Authored by Brave Software, the API operator. High credibility for factual pricing claims; note the inherent promotional framing of benchmark comparisons (Brave's own Ask Brave vs. competitors).
   - Weight: High for Brave-specific pricing and features. The evaluation methodology for quality benchmarks is described but should be considered vendor-produced.

2. **Brave Search API — Zero Data Retention Blog**
   - URL: https://brave.com/blog/search-api-zero-data-retention/
   - Credibility: Primary. Official Brave blog post dated January 26, 2026. Explains the architecture enabling ZDR and contrasts with scraper-based APIs. Verifiable against Brave's Data Processing Addendum. High credibility for architecture claims; the competitive claims about scrapers are factual but framed adversarially.
   - Weight: High for data retention and privacy architecture.

3. **Tavily Pricing Page**
   - URL: https://www.tavily.com/pricing
   - Credibility: Primary. Official Tavily pricing page, retrieved May 2026. Shows current tiers (Free: 1,000 credits/month, Pay As You Go: $0.008/credit, Project plan, Enterprise). Some plan details (exact rate limits per tier) are not fully enumerated on the public page; the "Project" plan slider UI obscures specific price points.
   - Weight: High for free tier and credit pricing. Medium for rate limits (not fully disclosed on pricing page — requires documentation or API testing).

4. **Tavily Documentation — Welcome/API Reference**
   - URL: https://docs.tavily.com/
   - Credibility: Primary. Official Tavily API documentation. Contains endpoint details, credit consumption rules (1-2 credits per search, 4-250 for research), and SDK integration patterns.
   - Weight: High for API mechanics and credit consumption.

5. **Anthropic — Web Search Tool Documentation**
   - URL: https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool
   - Credibility: Primary. Official Anthropic API documentation (docs.anthropic.com). Describes web search tool versions (`web_search_20260209` with dynamic filtering, `web_search_20250305` basic). Confirms no separate per-search fee; all costs are token-based. Current as of 2026.
   - Weight: High for Anthropic web search mechanics and pricing model.

6. **Anthropic — Rate Limits Documentation**
   - URL: https://docs.anthropic.com/en/api/rate-limits
   - Credibility: Primary. Official Anthropic API rate limits page. Documents the 4-tier system with exact RPM/ITPM/OTPM limits per model class and spend limit thresholds. Current as of 2026.
   - Weight: High for Anthropic rate limits and tier structure.

7. **Google Custom Search JSON API — Overview**
   - URL: https://developers.google.com/custom-search/v1/overview
   - Credibility: Primary. Official Google Developers documentation. States explicitly: "The following pricing applies only to existing Custom Search JSON API customers until the service discontinuation on January 1, 2027. This API is not available for new customers." Pricing: 100 free queries/day, $5/1,000 additional, up to 10k/day.
   - Weight: High for Google PSE pricing and discontinuation status.

8. **Perplexity API — Pricing Documentation**
   - URL: https://docs.perplexity.ai/docs/getting-started/pricing
   - Credibility: Primary. Official Perplexity API documentation. Contains full pricing tables for Sonar, Sonar Pro, Sonar Deep Research, Search API ($5/1k), and tool invocation costs ($0.005 per web_search call).
   - Weight: High for Perplexity pricing.

### Secondary Sources (Aggregator/Comparison)

9. **Awesome Agents — "Search API Pricing Compared 2026"**
   - URL: https://awesomeagents.ai/pricing/search-api-pricing/
   - Credibility: Secondary. Independent comparison site, prices verified April 19, 2026. Provides normalized per-1k-query costs across 11+ providers and cost-at-scale projections (10k/100k/1M queries/month). Author credibility is moderate (no named author; appears to be an editorial team). The analysis is thorough and cross-referenced with provider pages. Contains editorial opinion on "best fit" recommendations.
   - Weight: High for normalized cost comparisons. The cross-provider normalization is valuable but should be verified against primary sources for any single provider's numbers.

10. **The Implicator — "Brave Kills Free Search API Tier, Shifts to Metered Billing"**
    - URL: https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing/
    - Credibility: Secondary. Independent tech journalism outlet, authored by Marcus Schuler (Editor-in-Chief, former ARD correspondent). Published February 12, 2026. Provides historical context on Brave's pricing changes (2023 free tier → August 2025 AI Grounding update → February 2026 restructure) and documents community forum complaints about billing issues.
    - Weight: High for the timeline of Brave's pricing changes and billing system critique. The critical framing of Brave's move should be noted as editorial stance.

### Supplementary Sources

11. **Brave Search API Pricing (TrustRadius)**
    - URL: https://www.trustradius.com/products/brave-search-api/pricing
    - Credibility: Secondary. Third-party software review aggregator. Lists Brave's plan tiers and pricing. Less authoritative than Brave's own documentation but useful for corroborating plan structure.
    - Weight: Medium. Used for corroboration only.

12. **"Tavily Alternatives in 2026 (After the Nebius Acquisition)" — Medium**
    - URL: https://medium.com/@unicodeveloper/tavily-alternatives-in-2026-after-the-nebius-acquisition-9de526780686
    - Credibility: Secondary. Individual developer perspective on Medium. Authored by "unicodeveloper" (Prosper Otemuyiwa, identifiable developer advocate). Notes Tavily's acquisition by Nebius as a factor in provider evaluation. Contains rate limit observations.
    - Weight: Low-medium. Useful for community perspective on Tavily; not authoritative for pricing facts.

## 4. Conclusions

### 4.1 Cost Rankings at Scale

For a production agent running frequent web searches, the cost hierarchy (cheapest to most expensive per 1,000 queries at mid-volume) is:

| Rank | Provider | $/1k Queries | Type |
|------|----------|:-----------:|------|
| 1 | Serper.dev | $0.30–$1.00 | Google-scraped SERP |
| 2 | ValueSerp | $0.75–$1.90 | Google-scraped SERP |
| 3 | Exa (neural) | $1.00–$5.00 | Semantic search, own index |
| 4 | Brave Search | $5.00 | Independent index |
| 5 | Tavily | ~$8.00 ($0.008/credit, 1 credit/search) | Scraped, agent-optimized |
| 6 | SerpAPI | $10.00 | Google-scraped SERP |
| 7 | Perplexity Sonar | $8.00–$15.00+ | LLM-synthesized answers |
| 8 | Firecrawl | $15.00–$19.00 | Crawl + scrape |

Anthropic's web search cannot be ranked per-query because costs are entirely token-driven and vary by model. A single search using Claude Sonnet 4.x at Tier 1 may consume roughly 2,000–10,000 tokens total (query formulation + result processing), costing approximately $0.006–$0.15 per search — but this is highly variable.

### 4.2 Free Tier Survivability for Development

- **Serper.dev**: 2,500 free queries/month — the most generous ongoing free tier, sufficient for building and testing an agent pipeline.
- **Brave Search API**: $5 monthly credit (~1,000 queries) — requires credit card at signup and public attribution. Card is charged once credit is exceeded with no hard spending cap visible on the public pricing page. This is a paid plan with a credit, not a true free tier.
- **Tavily**: 1,000 free API credits/month — no credit card required. Simplest onboarding but credits deplete fast if research endpoints are used (4–250 credits per call).
- **Google PSE**: 100 free queries/day — but closed to new customers. Irrelevant unless you already have an active project.
- **Anthropic**: No free search quota specifically; Tier 1 has token limits but no dedicated free search calls. Search is just another tool invocation billed at standard token rates.

### 4.3 Privacy and Data Retention

This is where Brave has a structural advantage over every other provider except Anthropic:

- **Brave Search API**: Operates its own index; queries never touch Google or Bing. ZDR available for enterprise customers. SOC 2 Type II attested. No use of customer queries to train models. This is the only provider that can credibly claim end-to-end query privacy.
- **Anthropic Claude Web Search**: ZDR available for enterprise API customers. Anthropic's commercial terms prevent use of customer data for model training. However, the web search tool itself may route through third-party infrastructure for result retrieval — Anthropic has not published a detailed architecture diagram for the search backend.
- **Tavily**: GDPR-compliant. Retains usage logs and IP addresses for up to 12 months for analytics/advertising. Shares data with analytics providers and ad networks. Privacy policy acknowledges "sale/share" of internet activity data. As a scraper-based service, user queries ultimately reach Google/Bing infrastructure. Not suitable for regulated-industry use cases where query privacy is mandatory.
- **Google PSE**: Google's standard data practices apply. Queries are logged and subject to Google's retention policies.
- **Scraper-based providers (Serper, SerpAPI, ValueSerp)**: User queries are forwarded to Google or Bing in real-time. Even if the API provider itself promises no logging, the Big Tech search engine receiving the query operates under its own data collection regime. ZDR is architecturally impossible.

### 4.4 Rate Limits and Concurrency

| Provider | Free Tier Limit | Base Paid Limit | Max (Public) |
|----------|:--------------:|:---------------:|:------------:|
| Brave Search | ~1,000/mo (credit) | 50 QPS (Search plan) | 50 QPS |
| Tavily | 1,000 credits/mo | 5 QPS (300 RPM, Project) | Custom (Enterprise) |
| Anthropic (Tier 1) | 50 RPM (Sonnet 4.x) | 1,000 RPM (Tier 2) | 4,000 RPM (Tier 4) |
| Anthropic (Tier 1 Opus) | 50 RPM | 1,000 RPM (Tier 2) | 4,000 RPM (Tier 4) |
| Google PSE | 100/day (~4/hr) | 10,000/day | 10,000/day |
| Serper.dev | 2,500/mo | 50 QPS (Starter) | Not publicly capped |
| Perplexity | $5 one-time credit | Not clearly documented per plan | Not clearly documented |
| Exa | 60 RPM (Free) | 300 RPM (Starter) | 1,000 RPM (Pro) |

Note that Anthropic's rate limits apply to all API requests, not just search — if you're using Claude for both search and reasoning, they draw from the same RPM/ITPM/OTPM pool.

### 4.5 Recent Pricing Changes (2024–2026)

- **Brave Search API (Feb 2026)**: Eliminated free tier. Replaced 2,000–5,000 free monthly queries with $5/month credit requiring attribution. Launched LLM Context API. Simplified plan structure from Free/Free AI/Base AI/Pro AI to Search, Answers, Spellcheck, Auto-suggest.
- **Google PSE (Jan 2026)**: Closed Custom Search JSON API to new customers. Existing customers can use the API until January 1, 2027, after which it will be fully discontinued.
- **Microsoft Bing Search API (Mar 2025)**: Fully retired. No replacement API announced.
- **Tavily (2026)**: Acquired by Nebius. No pricing restructure announced post-acquisition as of research date, but the acquisition introduces uncertainty about future pricing direction.
- **Anthropic (2025–2026)**: Added web search tool to Claude API; introduced dynamic filtering (`web_search_20260209`) requiring code execution tool. No separate per-search pricing — remained token-only billing. Consumer data retention policy changed in August 2025 (opt-out required to avoid 5-year retention for model training), but this does not apply to API/commercial customers.

### 4.6 Actionable Recommendation

For the user's use case — LLM-driven web research where both Brave and Tavily are already enabled:

1. **If query privacy or regulatory compliance matters**: Brave is the only viable choice among the two. Tavily scrapes Google/Bing and shares data with analytics providers. Brave operates its own index and offers ZDR.

2. **If cost predictability matters**: Brave's flat $5/1,000 queries is simpler to budget than Tavily's credit model, where research calls consume 4–250 credits unpredictably ($0.032–$2.00 per research call).

3. **If agent integration speed matters**: Tavily's purpose-built SDK and relevance-scored results reduce engineering time. The 10× cost premium over Serper may be worth it if agent pipeline development is the bottleneck.

4. **If results are for sensitive topics**: Brave's independent index means queries are not observable by Google or Microsoft. Tavily routes queries through scrapers to Big Tech infrastructure.

5. **For pure research quality comparison**: This report does not evaluate result quality; see sibling reports from the broader research project. However, Brave's February 2026 benchmark (1,500 queries, Claude-as-judge) showed its LLM Context API + open-weights Qwen3 matching Grok and outperforming ChatGPT and Perplexity on answer quality, suggesting the grounding data quality is competitive.

**Default recommendation**: Prefer Brave for any research where query privacy, independence from Big Tech, or compliance matters. The $5/month credit with attribution covers 1,000 queries at no cost — adequate for moderate research use. For high-volume cost-sensitive use, layer Serper.dev ($0.30–$1.00/1k) as the primary SERP fetcher and reserve Brave or Tavily for cases requiring deeper content extraction or agent-optimized results.

## 5. Bibliography

Anthropic. (2026). *Rate limits*. Claude API Docs. https://docs.anthropic.com/en/api/rate-limits

Anthropic. (2026). *Web search tool*. Claude API Docs. https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool

Awesome Agents. (2026, April 19). *Search API pricing compared 2026*. https://awesomeagents.ai/pricing/search-api-pricing/

Brave Software. (2026, January 26). *Brave is the only search API offering true Zero Data Retention, unlocking growth and privacy compliance for AI companies*. Brave Blog. https://brave.com/blog/search-api-zero-data-retention/

Brave Software. (2026, February 12). *Brave launches most powerful search API for AI to date*. Brave Blog. https://brave.com/blog/most-powerful-search-api-for-ai/

Google. (2026). *Custom Search JSON API overview*. Google for Developers. https://developers.google.com/custom-search/v1/overview

Perplexity AI. (2026). *Pricing*. Perplexity API Docs. https://docs.perplexity.ai/docs/getting-started/pricing

Schuler, M. (2026, February 12). *Brave kills free Search API tier, shifts to metered billing*. The Implicator. https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing/

Tavily Inc. (2026). *Find a plan to power your AI agents*. Tavily. https://www.tavily.com/pricing

Tavily Inc. (2026). *Welcome*. Tavily Documentation. https://docs.tavily.com/

Tavily Inc. (2026). *Platform terms of service*. https://www.tavily.com/terms

Tavily Inc. (2026). *Privacy policy*. https://www.tavily.com/privacy

TrustRadius. (2026). *Brave Search API pricing 2026*. https://www.trustradius.com/products/brave-search-api/pricing

Unicodeveloper. (2026). *Tavily alternatives in 2026 (after the Nebius acquisition)*. Medium. https://medium.com/@unicodeveloper/tavily-alternatives-in-2026-after-the-nebius-acquisition-9de526780686
