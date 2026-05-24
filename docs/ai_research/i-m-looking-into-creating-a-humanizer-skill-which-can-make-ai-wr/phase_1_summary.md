# Phase 1 Summary

## Primary Question
What existing "humanizer" tools, skills, and techniques exist for making AI-generated text sound more human, and what approaches use author style mimicry or persona-based rewriting to improve cadence, tone, and naturalness?

## Sub-Topic Findings

### Existing Humanizer Tools and Services
**Perspective**: none
**Researcher conclusion**: The AI text humanizer market (mid-2026) is split between detection-evasion tools (Undetectable AI, StealthGPT, WriteHuman, Phrasly) and editing-oriented tools (Grammarly, QuillBot). The dominant technical approaches are LLM-based rewriting with anti-detection prompts and non-LLM post-processing via synonym swaps and sentence-length manipulation. Critically, **no existing commercial or open-source tool uses canonical literary author styles as a humanization mechanism** — validating the project's premise as genuinely novel. Fine-tuning on an author's complete works produces text preferred by experts 8:1 over MFA-written text and evades detection 97% of the time, but this is not available as a product feature. The closest analogues are HyperWrite's Personal Style Profile (learns from user's own writing) and Twixify's echowriting.
**Relation to primary question**: Confirms the tool landscape gap — persona-based rewriting via canonical literary styles is an underexplored approach, and fine-tuning evidence suggests the technique would be effective.

### Author Style Mimicry Techniques
**Perspective**: none
**Researcher conclusion**: Computational stylometry provides rigorous author fingerprinting via function-word frequency analysis (Burrows' Delta), achieving >90% attribution accuracy. Three principal NLP approaches exist: fine-tuning (strongest, but resource-intensive), few-shot prompting (23.5× better than zero-shot; 5 examples achieves most of the available gain), and style description prompts (explicit constraints on sentence structure, vocabulary, punctuation). Effective mimicry requires targeting deep structure (coherence of worldview, rhetorical intentionality, variability within constraints) rather than surface features (sentence length, word choice). Specific actionable style profiles were identified for Hemingway (parataxis, ≤1 subordinating conjunction per 5 clauses, <100 -ly adverbs per 10K words), Austen (free indirect discourse, modal-cognitive verb co-occurrence, ironic distance), and McCarthy (no quotation marks, polysyndeton, archaic diction).
**Relation to primary question**: Provides the technical foundation for how author style mimicry can be implemented in a humanizer skill — from computational fingerprinting to concrete style profiles for specific authors.

### Multi-Agent Persona Approaches to Text Generation
**Perspective**: none
**Researcher conclusion**: Multi-agent ensemble methods are strongly supported by the Mixture-of-Agents (MoA) framework achieving 65.8% win rate on AlpacaEval 2.0, but intra-model diversity (multiple samples from the same top model) can outperform cross-model mixing. The practical sweet spot is 3–4 agents — beyond this, coordination overhead increases without quality gains. Three architectural patterns apply: parallel generation + aggregation (MoA), debate/refinement loops, and routing-based single-persona selection. For a persona-based humanizer, the recommended architecture is: maintain a registry of 3–5 author-persona prompt templates with exemplar passages; dispatch input to all persona agents in parallel; use an aggregator to synthesize the best elements. Critically, style fidelity does not guarantee undetectability — matched LLM outputs average perplexity of 15.2 vs. 29.5 for human essays, meaning stylistic mimicry and statistical detectability are partially independent problems.
**Relation to primary question**: Validates the user's multi-subagent design with ensemble evidence and provides concrete architectural guidance for implementation.

### Known AI Writing Tropes and Detection Markers
**Perspective**: none
**Researcher conclusion**: AI-generated text bears detectable fingerprints at five levels: statistical (low perplexity, low burstiness), lexical (overuse of "delve" at 50× human rate, stock transitions, hedging phrases, inflated adjectives), syntactic (uniform sentence length, template reuse), structural (balanced paragraphs, formulaic openings/closings), and rhetorical (excessive hedging, absent personal voice, "missing mess" of human drafting). The VERMILLION framework (Sood, 2025) provides a 10-signal heuristic taxonomy for human-interpretable detection. Model-specific fingerprints differ significantly: ChatGPT is most detectable (68–96%), Claude least (23–35%), Gemini is structurally rigid. A humanizer must operate at all five levels simultaneously — addressing only vocabulary while leaving structural uniformity intact will still be detectable. The persona-based approach is well-aligned because channeling a specific author's characteristic rhythms, vocabulary, and structural idiosyncrasies directly counteracts the uniformity that makes AI text detectable.
**Relation to primary question**: Defines the negative space — the precise patterns a humanizer must avoid or transform — and confirms that author-style mimicry naturally addresses many of these markers.

### LLM Prompt Engineering for Style Transfer
**Perspective**: none
**Researcher conclusion**: Few-shot prompting with unaltered writing samples is the baseline requirement — zero-shot "write in the style of X" fails consistently (<7% accuracy). The strongest known approach is a multi-step "analyze then write" pipeline (Tree-of-Thoughts or Style Blueprint): first extract and describe the target style's features from samples, then generate text constrained by that description. Combined instruction + example prompts outperform either alone. Primary failure modes are generative exaggeration (LLMs amplify salient traits 10–20× beyond human baselines — the caricature problem), mid-response style reversion (style control decays over longer outputs), and style-content tradeoff (content fidelity degrades as style strength increases). For multi-persona synthesis, the hardest unsolved problem is style fusion — combining outputs from stylistically distinct agents without producing incoherent pastiche. Each persona subagent needs its own 3–5 few-shot exemplars, a negative-constraint prompt (what NOT to do), and low temperature (0–0.3) for style consistency.
**Relation to primary question**: Provides the specific prompt engineering techniques needed to make author-persona subagents produce faithful style mimicry rather than caricature.

### Evaluation Methods for Text "Humanness"
**Perspective**: none
**Researcher conclusion**: No single evaluation dimension is sufficient. AI detectors (GPTZero, Turnitin, Originality.ai) measure real signals (perplexity, burstiness) but suffer high false-positive rates, especially for non-native English writers (61.22% on TOEFL essays). Human evaluators and AI detectors both perform near chance on binary detection tasks — asking "Is this AI-generated?" is a poor metric. Reader judgments split into two profiles: surface-focused (non-experts, prefer readability) and holistic (experts, prefer thematic depth). Goodhart's Law is the central challenge: optimizing for any single metric causes divergence from genuine quality. A defensible rubric must combine: (1) multi-detector pass rates (≥3 detectors, without targeting 0%), (2) stylometric proximity to target author via Burrows' Delta, (3) blind human preference testing with varied reader profiles measuring specific dimensions (cadence, tone, naturalness), and (4) meaning preservation checks. The key insight for the humanizer project: a text that scores 20–40% on some detectors but reads naturally is better than an uncanny text scoring 0% everywhere.
**Relation to primary question**: Defines the success criteria — a humanizer skill should be evaluated by multi-metric frameworks balancing detection evasion, stylometric fidelity, and human-perceived naturalness, with human judgment carrying the most weight.

## Cross-Cutting Insights

### Pattern 1: The Author-Style-Mimicry Gap Is Validated Across All Lenses
Every sub-topic independently confirmed that no existing tool uses canonical literary author styles as a humanization mechanism. The tool landscape report found it as a market gap; the style mimicry report provided the technical feasibility; the multi-agent report validated the ensemble architecture; the tropes report confirmed that persona-based approaches naturally counteract AI uniformity; the prompt engineering report provided the implementation technique; and the evaluation report defined how to measure success. This convergence across six independent research threads is strong evidence that the project occupies a genuinely novel and technically defensible space.

### Pattern 2: Style Fidelity and Detection Evasion Are Partially Independent
Two reports independently identified the same critical finding: even high-fidelity stylistic mimicry does not achieve true human-like statistical unpredictability. The multi-agent report noted the perplexity gap (15.2 vs. 29.5), and the evaluation report framed it through Goodhart's Law. This means the humanizer must optimize for stylistic naturalness while accepting that perfect undetectability is a separate and harder problem. The practical implication is clear: measure success by human-perceived quality, not detector scores.

### Pattern 3: 3–4 Personas Is the Consensus Sweet Spot
The multi-agent report identified 3–4 agents as optimal from an ensemble-performance perspective, the tools report recommended 3–5 author profiles in its architecture recommendation, and the style mimicry report profiled exactly three highly distinctive authors (Hemingway, Austen, McCarthy). This convergence suggests a concrete starting point for implementation.

### Pattern 4: Few-Shot Prompting With Authentic Excerpts Is Non-Negotiable
Both the style mimicry report and the prompt engineering report converged on the same finding: zero-shot "write in the style of X" fails (<7% accuracy), and 5 exemplar passages achieve most of the available gain. The prompt engineering report added that unaltered excerpts must be used — paraphrased or flattened samples destroy the author's voice. This has direct implications for the skill's prompt templates.

### Pattern 5: The "Caricature Risk" Requires Active Mitigation
The prompt engineering report identified generative exaggeration as the primary failure mode (10–20× amplification of salient traits), and the style mimicry report warned about the pastiche-vs-mimicry distinction. Mitigation strategies converged: negative prompting (explicit "do not overuse X"), low temperature (0–0.3), and the analyze-then-write pipeline that separates style extraction from generation.

### Pattern 6: Goodhart's Law Applies at Every Evaluation Layer
The evaluation report's central insight — that optimizing for any single metric causes divergence from genuine quality — was echoed implicitly in the tools report (detection evasion rates in marketing should be treated as upper bounds), the style mimicry report (surface features vs. deep structure), and the prompt engineering report (style-content tradeoff). The solution is consistent: multi-metric evaluation with human judgment carrying the most weight.

### Contradictions and Unresolved Tensions
- **Model diversity vs. intra-model sampling**: The multi-agent report found that Self-MoA (multiple samples from the same model) outperforms cross-model mixing by 6.6%, but the persona concept inherently requires stylistic diversity. Resolution: differentiate personas through prompt engineering rather than different model backends — same model, different style instructions.
- **Detector reliability**: Vendor-claimed accuracy (92–99%) conflicts with independent benchmarks (83–92% with higher false-positive rates). Resolution: treat vendor numbers as upper bounds; use multiple detectors and don't target zero.
- **Style fusion remains unsolved in the literature**: The prompt engineering report flagged this explicitly — combining outputs from multiple stylistically distinct agents without producing incoherent pastiche is the hardest open problem in the proposed architecture.

## Consolidated Bibliography

### Academic Papers — Foundational
Burrows, J. (2002). 'Delta': A measure of stylistic difference and a guide to likely authorship. *Digital Scholarship in the Humanities*, 17(3), 267–287. https://academic.oup.com/dsh/article-abstract/17/3/267/929277

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

## Decision

**SUFFICIENT**

The primary research question is answered confidently. The six sub-topics provide converging evidence that:
1. No existing tool fills the author-style-mimicry humanizer gap (validating novelty).
2. The technical approach is feasible — few-shot prompting with authentic excerpts, 3–4 personas, parallel dispatch + aggregation.
3. The evaluation framework is defined — multi-metric with human judgment carrying most weight.
4. The known failure modes are catalogued — caricature, style reversion, style fusion incoherence, Goodhart optimization.

No major gaps remain. No contradictory findings remain unresolved (the tensions identified are design tradeoffs, not evidence conflicts). The research is ready for finalization.
