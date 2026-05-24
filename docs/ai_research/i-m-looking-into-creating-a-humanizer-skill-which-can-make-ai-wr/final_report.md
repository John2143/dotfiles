# Final Report

**Date:** 2026-05-18
**Research Question:** What existing "humanizer" tools, skills, and techniques exist for making AI-generated text sound more human, and what approaches use author style mimicry or persona-based rewriting to improve cadence, tone, and naturalness?

---

## 1. Answer

Dozens of commercial and open-source humanizer tools exist as of mid-2026 (Undetectable AI, StealthGPT, WriteHuman, Phrasly, QuillBot, Grammarly, and others), but their technical repertoire is narrow: LLM-based rewriting with anti-detection prompts, synonym swaps, sentence-length manipulation, and burstiness injection. They optimize for detection evasion, not for genuine stylistic naturalness. **No existing commercial or open-source tool uses canonical literary author styles as a humanization mechanism.** The market is entirely focused on statistical fingerprint disruption — making text not look like AI — rather than making it sound like a specific human writer.

Author style mimicry and persona-based rewriting are technically viable but underexplored in the humanizer space. The strongest evidence comes from author-specific fine-tuning (Chakrabarty et al., 2025): models fine-tuned on as few as two books produce prose that experts prefer 8:1 over MFA-written text for style, while evading detection 97% of the time. For practical deployment without per-author fine-tuning costs, few-shot prompting with 3–5 authentic author excerpts is the proven baseline — it yields 23.5× better style fidelity than zero-shot (Wang et al., 2025). The recommended architecture for a persona-based humanizer is: 3–4 stylistically distinct author-persona subagents (e.g., Hemingway, Austen, McCarthy), each armed with few-shot exemplars and a multi-step "analyze then write" prompt pipeline, generating in parallel with a synthesis aggregator combining outputs. This approach directly counteracts the five levels of AI detectability — statistical, lexical, syntactic, structural, and rhetorical — by replacing uniform AI fingerprints with the coherent stylistic signatures of real human authors.

The central challenge is not feasibility but evaluation. Goodhart's Law is the governing constraint: optimizing for any single metric (detector scores, perplexity, stylometric distance) causes divergence from genuine human-perceived quality. The only defensible evaluation framework combines multi-detector pass rates, stylometric proximity to target authors, blind human preference testing across varied reader profiles, and meaning-preservation checks — with human judgment carrying the most weight.

---

## 2. Evidence Summary

### Finding 1: No existing humanizer tool uses author-style mimicry — this is a genuine market and research gap.
Every sub-topic independently confirmed this. The tools landscape is dominated by detection-evasion products operating at the statistical/lexical level; none implement persona-driven rewriting through canonical literary voices.
- **Phase 1, Sub-Topic 1:** [Existing Humanizer Tools and Services](reports/existing-humanizer-tools_report.md) — Comprehensive catalog of 15+ commercial and open-source tools. None use author styles as rewrite targets. HyperWrite's Personal Style Profile and Twixify's echowriting learn from user-submitted samples but do not target established literary authors.
- **Phase 1, Sub-Topic 2:** [Author Style Mimicry Techniques](reports/author-style-mimicry_report.md) — Computational stylometry provides rigorous author fingerprinting, but this capability has not been productized in humanizer tools.
- **Phase 1, Sub-Topic 3:** [Multi-Agent Persona Approaches](reports/multi-agent-persona_report.md) — Multi-agent ensemble methods exist for general text generation but have not been applied to author-style-based humanization.

### Finding 2: Few-shot prompting with unaltered author excerpts is the pragmatic implementation path.
Zero-shot "write in the style of X" fails consistently (<7% accuracy). Five exemplar passages achieve most available gain; beyond eight yields diminishing returns. Combined instruction + example prompts outperform either alone.
- **Phase 1, Sub-Topic 2:** [Author Style Mimicry Techniques](reports/author-style-mimicry_report.md) — Wang et al. (2025) found 5-shot prompting raised verification accuracy dramatically over zero-shot across 400+ authors and four domains.
- **Phase 1, Sub-Topic 5:** [LLM Prompt Engineering for Style Transfer](reports/llm-style-transfer_report.md) — Bohr (2025) demonstrated that combined explicit directives + concrete examples produce the strongest initial style adherence and persistence across multi-turn interactions. Jemama & Kumar (2025) found prompting strategy dominates model size for style fidelity.

### Finding 3: 3–4 personas is the consensus sweet spot for multi-agent architecture.
Parallel generation with aggregation (MoA pattern) is the recommended architecture. More than 4 agents increases coordination overhead without quality gains. Intra-model diversity (same model, different style instructions) often outperforms cross-model mixing.
- **Phase 1, Sub-Topic 3:** [Multi-Agent Persona Approaches](reports/multi-agent-persona_report.md) — MoA framework achieves 65.8% win rate on AlpacaEval 2.0; Self-MoA (multiple samples from same top model) outperforms cross-model mixing by 6.6%. Coordination saturates at ~0.39 messages/second.
- **Phase 1, Sub-Topic 1:** [Existing Humanizer Tools and Services](reports/existing-humanizer-tools_report.md) — Architecture recommendation independently converges on 3–5 author profiles with parallel dispatch and synthesis pass.
- **Phase 1, Sub-Topic 2:** [Author Style Mimicry Techniques](reports/author-style-mimicry_report.md) — Three highly distinctive and computationally tractable author profiles identified: Hemingway (parataxis, low Flesch-Kincaid), Austen (free indirect discourse), McCarthy (minimal punctuation, polysyndeton).

### Finding 4: AI-generated text has detectable fingerprints at five levels — a humanizer must address all simultaneously.
Statistical (low perplexity, low burstiness), lexical (50× overuse of "delve," stock transitions, inflated adjectives), syntactic (uniform sentence length), structural (balanced paragraphs, formulaic openings/closings), and rhetorical (excessive hedging, absent personal voice).
- **Phase 1, Sub-Topic 4:** [Known AI Writing Tropes and Detection Markers](reports/ai-writing-tropes_report.md) — Kobak et al. (2024) identified 379 "excess vocabulary" words from 15M PubMed abstracts. VERMILLION framework (Sood, 2025) provides 10-signal heuristic taxonomy. ChatGPT detected 68–96%, Claude 23–35%, Gemini 52–70%.
- **Phase 1, Sub-Topic 5:** [LLM Prompt Engineering for Style Transfer](reports/llm-style-transfer_report.md) — Generative exaggeration is the primary failure mode (10–20× amplification of salient traits). Mitigation: negative prompting, low temperature (0–0.3), analyze-then-write pipeline.

### Finding 5: Goodhart's Law applies at every evaluation layer — multi-metric frameworks are essential.
Optimizing for any single metric (detector scores, perplexity, burstiness) causes divergence from genuine quality. Detection tools have high false-positive rates, especially for non-native English writers (61.22% on TOEFL essays). Human evaluators and AI detectors both perform near chance on binary detection tasks.
- **Phase 1, Sub-Topic 6:** [Evaluation Methods for Text "Humanness"](reports/humanness-evaluation_report.md) — Definitive evaluation must combine multi-detector pass rates (≥3 detectors, without targeting 0%), stylometric proximity (Burrows' Delta to target author), blind human preference testing across reader profiles, and meaning-preservation checks.
- **Phase 1, Sub-Topic 3:** [Multi-Agent Persona Approaches](reports/multi-agent-persona_report.md) — Even high-fidelity stylistic mimicry does not close the perplexity gap (15.2 LLM vs. 29.5 human). Style fidelity and detection evasion are partially independent goals.

### Finding 6: The "analyze then write" pipeline is the strongest known prompt engineering technique for style transfer.
Multi-step approach: first extract and describe target style features from samples, then generate text constrained by that description. Tree-of-Thoughts (ToT) prompting significantly outperforms Chain-of-Thought and standard zero-shot for style imitation.
- **Phase 1, Sub-Topic 5:** [LLM Prompt Engineering for Style Transfer](reports/llm-style-transfer_report.md) — Yu et al. (2024) ToT produced 30% automatic evaluation success rate vs. 12% for CoT and 8% for standard. Style Blueprint methodology operationalizes this for reuse.

### Finding 7: Style fusion — combining outputs from multiple author-persona agents — is unsolved in the literature.
This is the hardest open problem in the proposed multi-persona architecture. Combining Hemingway's parataxis with Austen's periodic sentences risks producing incoherent pastiche. Mitigation strategies exist (style consistency pass, negative prompting, low temperature) but have not been empirically validated for this specific use case.
- **Phase 1, Sub-Topic 5:** [LLM Prompt Engineering for Style Transfer](reports/llm-style-transfer_report.md) — Flagged explicitly as an unsolved problem.
- **Phase 1, Cross-Cutting Insight 6:** [Phase 1 Summary](phase_1_summary.md) — Identified as an unresolved tension in the proposed architecture.

---

## 3. Confidence Assessment

### High Confidence

- **No existing tool uses author-style mimicry for humanization.** Six independent research threads converge on this finding. The tools market has been systematically catalogued (15+ tools, both commercial and open-source). Negative findings are inherently harder to prove, but the thoroughness of the search — spanning product pages, independent benchmarks, GitHub repositories, and academic literature — makes false negatives unlikely for the English-language market as of mid-2026.

- **Few-shot prompting is required for any non-trivial style mimicry.** Multiple independent academic studies (Wang et al., 2025; Jemama & Kumar, 2025; Bhandarkar et al., 2024) all converge on <7% zero-shot accuracy with 23.5× improvement from few-shot. The evidence is primary, peer-reviewed, and mutually corroborating.

- **AI-generated text has consistent, quantifiable lexical fingerprints.** The Kobak et al. (2024) *Science Advances* study on 15M PubMed abstracts is large-scale, peer-reviewed, and definitive for academic prose. The specific word lists (379 excess vocabulary words) have been cross-validated by independent practitioner sources (Cherryleaf, Pangram Labs, Decrypt).

- **Goodhart's Law is the central evaluation challenge.** This is a well-established principle (OpenAI's own research, 2022) whose application to AI text detection is corroborated by both academic evaluation research and practical experience with metric gaming in humanizer tools. The evidence is conceptual rather than empirical for this specific domain, but the underlying principle is robust.

### Medium Confidence

- **3–4 personas is optimal for multi-agent systems.** The MoA framework (ICLR 2025) and industry deployment reports converge on this range, but the specific number depends on task characteristics not yet tested for style-focused humanization. The Self-MoA finding (Li et al., 2025) that intra-model diversity can outperform cross-model mixing is a preprint and not yet peer-reviewed.

- **Fine-tuning on author corpora produces human-preferred text.** The Chakrabarty et al. (2025) finding (8:1 expert preference, 97% evasion) is striking but comes from a single study, is a preprint, and has not been independently replicated. The effect size is large enough to be credible, but the finding should be treated as promising rather than settled.

- **The "analyze then write" pipeline is the strongest approach.** Supported by Yu et al. (2024) and practitioner sources (Style Blueprint), but the academic study used only three celebrity interviews — a narrow domain. Generalizability to literary author styles is plausible but not directly tested.

### Low Confidence

- **Style fusion from multiple author-persona agents can produce coherent output.** This is the architecture's central unsolved problem. No direct evidence exists. The mitigation strategies proposed (consistency pass, negative prompting, low temperature) are extrapolated from single-style transfer research and have not been tested in multi-style fusion scenarios.

- **Humanizer detection-evasion rates in vendor marketing (94–99%) reflect real-world performance.** Independent benchmarks consistently find lower rates (80–95% in best cases). The adversarial arms race means today's numbers are not tomorrow's. Vendor claims should be treated as upper bounds.

---

## 4. Limitations and Open Questions

### What This Research Did Not Cover

- **Non-English language humanization.** All tools and academic sources examined focus on English-language text. Stylistic markers, AI writing tropes, and detection methods differ across languages. The author personas profiled (Hemingway, Austen, McCarthy) are all English-language writers.

- **Real-time or streaming humanization.** The research assumes batch processing. Latency requirements, streaming text scenarios, and interactive humanization (user-in-the-loop refinement) were not investigated.

- **Copyright and legal implications.** Chakrabarty et al. (2025) explicitly studied AI trained on copyrighted books. The legal landscape around author-style mimicry — particularly whether few-shot prompting with copyrighted excerpts constitutes fair use — was not researched.

- **Domain-specific humanization (legal, medical, technical).** The research focuses on general prose and creative writing. Domain-specific conventions (legal boilerplate, medical terminology, technical precision) interact with humanization goals in ways not investigated.

- **Cost optimization for production deployment.** Token costs, API pricing, and latency budgets for multi-agent architectures were noted as considerations but not systematically analyzed.

### Assumptions Made

- That literary author styles (Hemingway, Austen, McCarthy) map coherently to the types of text a humanizer would process. A Hemingway-style technical report or an Austen-style incident postmortem may not be appropriate for all use cases.
- That the five levels of AI detectability (statistical, lexical, syntactic, structural, rhetorical) are comprehensive. Future detection methods may identify additional markers.
- That improving human-perceived naturalness is more valuable than achieving undetectability. This is a design philosophy, not an empirically validated tradeoff.

### Open Questions

1. **Style fusion feasibility:** Can outputs from stylistically distinct persona agents be combined into a single coherent text without producing pastiche? This is the single most important question for the proposed architecture and has zero direct evidence in the literature.

2. **Persona-context matching:** Which author persona is appropriate for which type of input text? Should the system auto-select personas based on content analysis, or should the user choose? What happens when an author's style is fundamentally mismatched to the content domain?

3. **Model-specific persona performance:** Different base models (GPT-4, Claude, Gemini) have different strengths for style mimicry. The research identified Claude as producing the most human-like statistical fingerprints, but this was for general text, not author-specific style transfer. Is there an interaction between base model and target author?

4. **Long-text style persistence:** Style control decays over longer outputs. The "re-inject prompts between segments" mitigation is proposed but untested for multi-author fusion across document-length text.

5. **Evaluation benchmark:** No standardized benchmark exists for evaluating humanizer tools on style fidelity. The four-metric framework from Wang et al. (2025) is the closest analogue but was designed for authorship impersonation detection, not humanization quality. Building and validating such a benchmark is prerequisite work for any rigorous humanizer evaluation.

6. **Detector arms race trajectory:** If author-style-based humanization proves effective, detectors will adapt. Will they develop author-specific detection (e.g., "this sounds like Hemingway but wasn't written by him")? The Nini et al. (2026) finding that LLM impersonations are actually *more* detectable than random human text is concerning.

7. **Minimum viable persona count:** Is a single well-executed author persona sufficient for humanization, or does the ensemble effect require multiple? The MoA evidence suggests ensembles help, but the effect may be smaller for style tasks than for reasoning tasks.

---

## 5. Bibliography

### Academic Papers — Foundational

Burrows, J. (2002). 'Delta': A measure of stylistic difference and a guide to likely authorship. *Digital Scholarship in the Humanities*, 17(3), 267–287. https://academic.oup.com/dsh/article-abstract/17/3/267/929277

Evert, S., Proisl, T., Jannidis, F., Reger, I., Pielström, S., Schöch, C., & Vitt, T. (2017). Understanding and explaining delta measures for authorship attribution. *Digital Scholarship in the Humanities*, 32(suppl_2), ii4–ii16. https://doi.org/10.1093/llc/fqx023

### Academic Papers — AI Style Mimicry

Bhandarkar, A., Wilson, R., Swarup, A., & Woodard, D. (2024). Emulating author style: A feasibility study of prompt-enabled text stylization with off-the-shelf LLMs. In *Proceedings of PERSONALIZE 2024* (pp. 76–82). ACL. https://aclanthology.org/2024.personalize-1.10/

Chakrabarty, T., Ginsburg, J., Dhillon, P., et al. (2025). Readers prefer outputs of AI trained on copyrighted books over expert human writers. *arXiv preprint* arXiv:2510.13939. https://arxiv.org/html/2510.13939v1

Jemama, L., & Kumar, R. (2025). How well do LLMs imitate human writing style? *arXiv:2509.24930*. Presented at IEEE UEMCON 2025. https://arxiv.org/abs/2509.24930

Mikros, G. (2025). Beyond the surface: Stylometric analysis of GPT-4o's capacity for literary style imitation. *Digital Scholarship in the Humanities*, 40(2), 587. https://academic.oup.com/dsh/article/40/2/587/8118784

Nini, A., et al. (2026). Authorship impersonation via LLM prompting does not evade authorship verification methods. *arXiv:2603.29454*. https://arxiv.org/html/2603.29454v1

O'Sullivan, J. (2025). Stylometric comparisons of human versus AI-generated creative writing. *Humanities and Social Sciences Communications*, Nature. https://www.nature.com/articles/s41599-025-05986-3

Wang, Z., Tripto, N. I., Park, S., Li, Z., & Zhou, J. (2025). Catch me if you can? Not yet: LLMs still struggle to imitate the implicit writing styles of everyday authors. *Findings of EMNLP 2025*. arXiv:2509.14543. https://arxiv.org/html/2509.14543v1

Yu, J., et al. (2024). Using prompts to guide large language models in imitating a real person's language style. *arXiv:2410.03848*. https://arxiv.org/html/2410.03848v1

### Academic Papers — Multi-Agent and Ensemble Methods

Arbore, G., Sillano, A., & De Russis, L. (2026). Building persona-based agents on demand. *arXiv:2604.27882*. https://arxiv.org/abs/2604.27882

Ashiga, M., et al. (2025). Ensemble learning for large language models in text and code generation: A survey. *arXiv:2503.13505*. https://arxiv.org/abs/2503.13505

Li, W., Lin, Y., Xia, M., & Jin, C. (2025). Rethinking Mixture-of-Agents: Is mixing different large language models beneficial? *arXiv:2502.00674*. https://arxiv.org/abs/2502.00674

Schoenegger, P., et al. (2024). Wisdom of the silicon crowd: LLM ensemble prediction capabilities rival human crowd accuracy. *Science Advances*, 10(10), eadp1528. https://www.science.org/doi/10.1126/sciadv.adp1528

Suzgun, M., Melas-Kyriazi, L., & Jurafsky, D. (2022). Follow the wisdom of the crowd: Effective text generation via minimum Bayes risk decoding. *Findings of ACL 2023*. https://arxiv.org/abs/2211.07634

Wang, J., Wang, J., Athiwaratkun, B., Zhang, C., & Zou, J. (2024). Mixture-of-Agents enhances large language model capabilities. *ICLR 2025*. arXiv:2406.04692. https://arxiv.org/abs/2406.04692

### Academic Papers — AI Detection and Writing Tropes

Bitton, Y., Bitton, E., & Nisan, S. (2025). Detecting stylistic fingerprints of large language models. *arXiv:2503.01659*. https://arxiv.org/abs/2503.01659

Kobak, D., González-Márquez, R., Horvát, E.-Á., & Lause, J. (2024). Delving into LLM-assisted writing in biomedical publications through excess vocabulary. *Science Advances*. https://doi.org/10.1126/sciadv.adt3813

Liang, W., Yuksekgonul, M., Mao, Y., Wu, E., & Zou, J. (2023). GPT detectors are biased against non-native English writers. *PMC*. https://pmc.ncbi.nlm.nih.gov/articles/PMC10382961/

Sood, S. (2025). The disappearing author: Linguistic and cognitive markers of AI-generated communication. *Journal of Entrepreneurship and Business Development*, 5(1), 7–25. https://doi.org/10.18775/ijmsba.1849-5664-5419.2014.51.7001

### Academic Papers — Prompt Engineering and Style Transfer

Bohr, J. (2025). Show and tell: Prompt strategies for style control in multi-turn LLM code generation. *arXiv:2511.13972*. https://arxiv.org/abs/2511.13972

Thillainathan, S., Lee, J.-U., Sullivan, M., & Koller, A. (2026). AuthorMix: Modular authorship style transfer via layer-wise adapter mixing. *arXiv:2603.23069*. https://arxiv.org/abs/2603.23069

Toshevska, M., & Gievska, S. (2025). LLM-based text style transfer: Have we taken a step forward? *Natural Language Engineering*. https://www.cambridge.org/core/journals/natural-language-engineering/article/from-theories-on-styles-to-their-transfer-in-text-bridging-the-gap-with-a-hierarchical-survey/C2C386DEEB83B6281280ACD899AA1A3F

### Academic Papers — Evaluation Methods

Marco, G., Gonzalo, J., & Fresno, V. (2025). The reader is the metric: How textual features and reader profiles explain conflicting evaluations of AI creative writing. *Findings of ACL 2025*. arXiv:2506.03310. https://arxiv.org/abs/2506.03310

Memon, A. R., et al. (2025). Can we trust academic AI detective? Accuracy and limitations of AI-output detectors. *PMC/Springer Nature*. https://pmc.ncbi.nlm.nih.gov/articles/PMC12331776/

Rashidi, H. H., et al. (2025). Do humans identify AI-generated text better than machines? *ScienceDirect*. https://www.sciencedirect.com/science/article/pii/S1477388025000131

### Open-Source Projects

brandonwise. (2026). Humanizer: OpenClaw skill that detects and removes signs of AI-generated writing. GitHub. https://github.com/brandonwise/humanizer

rudra496. (2026). StealthHumanizer: Free open-source AI text humanizer. GitHub. https://github.com/rudra496/StealthHumanizer

### Commercial Tools

Grammarly, HIX Bypass, HyperWrite AI, Phrasly, QuillBot, StealthGPT, Twixify, Undetectable AI, WriteHuman — official product pages (URLs in individual reports).

### Industry and Testing Sources

Cherryleaf. (2026). Indicators that suggest something was written by AI. https://www.cherryleaf.com/2026/02/indicators-that-suggest-something-was-written-by-ai/

Decrypt. (2025). The 5 biggest 'tells' that something was written by AI. https://decrypt.co/348923/5-biggest-tells-something-written-ai

EyeSift. (2026). AI detector accuracy benchmarks 2026. https://www.eyesift.com/blog/ai-detector-accuracy-benchmarks-2026/

GPTZero. (2025–2026). Perplexity & burstiness documentation; Phrasly AI review. https://gptzero.me/

HumanizerAI.com. (2026). Best AI humanizer in 2026: 15 tools tested against 5 detectors. https://humanizerai.com/blog/best-ai-humanizer-2026

OpenAI. (2022). Measuring Goodhart's law. https://openai.com/index/measuring-goodharts-law/

Originality.AI. (2025–2026). Multiple tool reviews. https://originality.ai/blog/

Pangram Labs. (2026). Comprehensive guide to spotting AI writing patterns. https://www.pangram.com/blog/comprehensive-guide-to-spotting-ai-writing-patterns

prompts.chat. (n.d.). AI prompts community. https://prompts.chat/

The Algorithmic Bridge. (2026). 10 signs of AI writing that 99% of people miss. https://www.thealgorithmicbridge.com/p/10-signs-of-ai-writing-that-99-of

### Literary Analysis and Practitioner Sources (Style Profiles)

BookAnalysis.com. (2024). Understanding Ernest Hemingway's incredible writing style. https://bookanalysis.com/ernest-hemingway/writing-style/

Enchanting Marketing. (2023). How to write like Hemingway (with examples of his writing style). https://www.enchantingmarketing.com/write-like-hemingway/

JASNA (Jane Austen Society of North America). (2016). Discerning voice through Austen Said. *Persuasions On-Line*, 37(1). https://jasna.org/publications-2/persuasions-online/vol37no1/white-smith/

Open Culture. (2013). The three punctuation rules of Cormac McCarthy (RIP), and how they all go back to James Joyce. https://www.openculture.com/2013/08/cormac-mccarthys-punctuation-rules.html

The Decoder. (2025). AI models can mimic famous authors' writing styles using just two books for training. https://the-decoder.com/ai-models-can-mimic-famous-authors-writing-styles-using-just-two-books-for-training/
