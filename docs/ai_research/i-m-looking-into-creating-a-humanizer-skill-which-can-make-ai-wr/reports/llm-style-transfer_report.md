# LLM Prompt Engineering for Style Transfer — Research Report

## 1. Summary

Prompt engineering for authorial style transfer is an active but incomplete field. The core finding across the literature is that **few-shot prompting with unaltered writing samples** consistently outperforms zero-shot "write in the style of X" instructions. Providing even 3–5 authentic excerpts from a target author allows LLMs to capture sentence-level rhythm, pacing, and word-choice patterns that name-dropping alone cannot access. The 2025 Wang et al. study across 400+ authors and four domains found that 5-shot prompting raised authorship verification accuracy dramatically over zero-shot baselines — but even then, LLM-generated text was detected as AI-written 80–95% of the time, and models struggled especially with informal, nuanced styles (blogs, forums) compared to structured formats (news, email).

Two prompt mechanism families dominate: **instruction-based** (explicit constraints like "use short declarative sentences, avoid adjectives, employ parataxis") and **example-based** (providing concrete text samples). Bohr's 2025 "Show and Tell" study on code style transfer found that **combined approaches** — explicit directives plus concrete demonstrations — produced the strongest initial style control and the best persistence across multi-turn interactions. Neither approach alone was sufficient across all conditions. The 2024 Bhandarkar et al. study also validated this with a 4-element zero-shot prompt structure (role, task, given text, output format).

The most effective known technique for authorial style transfer is a **multi-step "analyze then write" pipeline**: first have the LLM extract and describe the target style's features (sentence length, vocabulary register, figurative language patterns, structural tendencies), then generate text using that extracted style description as a constraint. The 2024 study by Yu et al. on ToT (Tree-of-Thoughts) prompting found this approach significantly outperformed both standard zero-shot and Chain-of-Thought prompting for style imitation. The "Style Blueprint" methodology popularized in practitioner circles (eesel AI, FinancialContent) operationalizes this: feed 3–5 representative samples to an LLM, ask it to reverse-engineer a reusable one-paragraph style specification, then prepend that blueprint to all future prompts.

Failure modes are well-characterized. **Generative exaggeration** — the systematic amplification of salient stylistic traits beyond natural baselines — is the primary pathology. LLMs optimized for salience over subtlety produce caricature: emoji and hashtag frequencies 10–20× higher than human baselines in Twitter-style generation, extreme deployment of signature phrases, and an inability to modulate between foreground stylistic markers and background restraint. Models also exhibit **mid-response style drift**, where stylistic control decays over longer outputs, reverting to the model's default fluent-but-generic voice. Zero-shot style imitation is essentially non-functional — Wang et al. (2025) report accuracy below 7% across all models tested, with the verifier reporting high confidence (>95%) for its wrong predictions, indicating models produce *confidently wrong* pastiche rather than recognizable failure.

Prompt libraries and community resources exist but are predominantly oriented toward image generation and general-purpose tasks rather than authorial style transfer. **PromptBase** (270K+ prompts, 450K+ users) is primarily a marketplace for Midjourney/DALL-E prompts. **prompts.chat** (formerly Awesome ChatGPT Prompts, 162K+ GitHub stars) is the largest open-source text prompt library and does include writing-style prompts, but author-specific style transfer prompts are not a prominent category. The most actionable resources for this use case are the academic papers themselves, which provide validated prompt templates and evaluation frameworks.

## 2. Relation to Primary Question

These findings bear directly on the humanizer project: effective style transfer to a known novelist's voice requires (a) authentic, structurally intact writing samples from that author as few-shot exemplars, (b) a multi-step "analyze style, then write" pipeline, and (c) explicit negative constraints to suppress the model's tendency toward exaggeration and default-voice reversion. The multi-agent persona approach described in the user's brief — where subagents each adopt a different authorial persona — is a novel extension of established persona-prompting techniques, but it introduces the additional challenge of *style fusion*: combining outputs from multiple stylistically distinct agents without producing incoherent pastiche.

## 3. Source Evaluation

### Source 1
- **URL**: https://arxiv.org/html/2509.14543v1
- **Title**: Catch Me If You Can? Not Yet: LLMs Still Struggle to Imitate the Implicit Writing Styles of Everyday Authors
- **Credibility assessment**: Primary source. Peer-reviewed academic paper (Wang et al., 2025) from Stony Brook University and Penn State. Published September 2025 — highly recent. Rigorous methodology: 40,000+ generations per model, 400+ authors, four-domain evaluation with authorship attribution, verification, stylometric modeling, and AI detection. Open-source code and data.
- **Weighting**: This is the most comprehensive and methodologically sound evaluation of LLM style imitation available. Heavily weighted for all claims about few-shot vs. zero-shot performance, domain sensitivity, and current limitations.

### Source 2
- **URL**: https://arxiv.org/html/2410.03848v1
- **Title**: Using Prompts to Guide Large Language Models in Imitating a Real Person's Language Style
- **Credibility assessment**: Primary source. Academic paper (Yu et al., 2024) comparing GPT-4, Llama 3, and Gemini 1.5 on style imitation under zero-shot, CoT, and ToT prompting. Three evaluation methods (human, LLM-judge, automated BERT-based classifier). Published October 2024.
- **Weighting**: Provides the foundational evidence that ToT prompting significantly outperforms other methods for style imitation. Limited by small dataset (three celebrity interviews). Weighted for ToT findings; domain scope acknowledged.

### Source 3
- **URL**: https://arxiv.org/abs/2511.13972
- **Title**: Show and Tell: Prompt Strategies for Style Control in Multi-Turn LLM Code Generation
- **Credibility assessment**: Primary source. Academic paper (Bohr, 2025) under review. Rigorous paired experimental design (N=160) testing instruction-based vs. example-based vs. combined prompts across two turns.
- **Weighting**: Directly relevant to the instruction-vs-examples question. Code-generation domain limits direct applicability to prose style transfer, but the core finding — combined approaches outperform either alone — is likely transferable. Weighted for mechanism comparison.

### Source 4
- **URL**: https://dev.to/thatechmaestro/replicate-an-authors-writing-style-using-prompt-engineering-insights-from-an-experiment-with-2hfk
- **Title**: Replicate an Author's Writing Style Using Prompt Engineering
- **Credibility assessment**: Secondary source. Practitioner blog post (Abubakar, April 2025) on DEV Community. Not peer-reviewed. Provides structured experimental comparison of Claude vs. GPT-4o on Steven Pressfield style replication using multiple prompt strategies. Full prompts and responses published in a linked gist.
- **Weighting**: Lower weight than academic sources, but high practical value. The finding that flattened/paraphrased samples destroy author voice while unaltered samples preserve it is actionable and plausible. The Claude-vs-GPT-4o comparison adds model-specific insight.

### Source 5
- **URL**: https://www.sciencedirect.com/science/article/pii/S246869642500045X
- **Title**: Generative Exaggeration in LLM Social Agents: Consistency, Bias, and Toxicity
- **Credibility assessment**: Primary source. Peer-reviewed journal article (ScienceDirect, 2025). Provides the formal definition and empirical evidence for "generative exaggeration" as a systematic failure mode.
- **Weighting**: Core evidence for the caricature/pastiche failure mode. Paywalled — full text not accessed; claims verified through multiple secondary citations and the abstract. Weighted for the exaggeration mechanism.

### Source 6
- **URL**: https://arxiv.org/abs/2509.24930
- **Title**: How Well Do LLMs Imitate Human Writing Style?
- **Credibility assessment**: Primary source. Academic paper (Jemama et al., September 2025). Evaluates five LLMs across four prompting strategies. Reports that prompting strategy, not model architecture, dominates style fidelity outcomes, and that one-shot accuracy varies wildly (67.6% to 94.7%).
- **Weighting**: Strong evidence for the primacy of prompting strategy over model choice. The wide variance finding is important for expectations management.

### Source 7
- **URL**: https://www.financialcontent.com/article/worldnewswire-2025-11-4-how-to-train-an-ai-to-mimic-your-writing-style-the-end-of-the-generic-voice
- **Title**: How to Train an AI to Mimic Your Writing Style: The End of the Generic Voice
- **Credibility assessment**: Secondary/tertiary source. Syndicated press release on FinancialContent (November 2025). Promotes the "Style Blueprint" methodology. Author/organization affiliation unclear — appears to be commercially motivated content.
- **Weighting**: Low weight for claims. Included because it articulates the Style Blueprint methodology clearly, which mirrors the academically validated "analyze then write" approach. The methodology itself is plausible; the promotional framing is discounted.

### Source 8
- **URL**: https://www.eesel.ai/blog/how-to-train-ai-to-match-your-writing-style
- **Title**: How to Train AI to Match Your Writing Style
- **Credibility assessment**: Secondary source. Commercial blog (eesel AI, undated). Practitioner-oriented guide. Describes the Style Blueprint method with concrete steps.
- **Weighting**: Low weight. Included as a representative practitioner resource showing real-world adoption of the analyze-then-write pattern. Claims not independently verified.

### Source 9
- **URL**: https://prompts.chat/ and https://github.com/f/prompts.chat
- **Title**: prompts.chat — AI Prompts Community (formerly Awesome ChatGPT Prompts)
- **Credibility assessment**: Primary source for its own content. Largest open-source prompt library (162K+ GitHub stars). Community-contributed, not peer-reviewed. Referenced by Harvard, Columbia, and 40+ academic citations, lending institutional credibility. Maintained by Fatih Kadir Akin.
- **Weighting**: Authoritative for the claim that it is the largest open-source prompt library. Low weight for quality of individual style-transfer prompts (not evaluated). Relevant as evidence of community resource availability.

### Source 10
- **URL**: https://promptbase.com/
- **Title**: PromptBase — The #1 Marketplace for AI Prompts
- **Credibility assessment**: Primary source for its own content. Commercial marketplace (270K+ prompts, 450K+ users, 4.9 rating). Prompts are user-submitted and sold; quality varies. Not academically validated.
- **Weighting**: Low weight. Included to document the existence of a commercial prompt marketplace. Relevant primarily as infrastructure, not as a source of validated style-transfer techniques.

### Source 11
- **URL**: https://arxiv.org/html/2502.04362v1
- **Title**: LLMs Can Be Easily Confused by Instructional Distractions
- **Credibility assessment**: Primary source. Academic paper (2025). Reports that models achieve only 0.301 average accuracy on style transfer tasks compared to 0.526 on translation and 0.397 on rewriting, demonstrating style transfer is distinctively difficult.
- **Weighting**: Moderate weight. The comparative difficulty finding is robust. Used to contextualize why style transfer is harder than superficially similar NLP tasks.

### Source 12
- **URL**: https://arxiv.org/abs/2409.15268
- **Title**: Style Outweighs Substance: Failure Modes of LLM Judges in Alignment Benchmarking
- **Credibility assessment**: Primary source. Academic paper (2025). Finds that LLM-judges prioritize style over factuality and safety, and that LLM-judge preferences do not correlate with concrete quality measures.
- **Weighting**: Important cautionary finding for the humanizer project: if LLMs are used to evaluate style-transfer quality, they may reward surface-level stylistic markers rather than genuine voice fidelity. This directly impacts evaluation methodology.

## 4. Conclusions

### 4.1 What Prompt Structures Reliably Work

1. **Few-shot with unaltered excerpts is the baseline requirement.** Zero-shot "write in the style of X" fails consistently (accuracy <7%). At minimum, provide 3–5 authentic, structurally intact writing samples from the target author. Do not paraphrase, flatten, or summarize the samples — sentence breaks, rhythm, and pacing are part of the voice and must be preserved.

2. **The 4-element prompt structure is validated.** Bhandarkar et al. (2024) and Yu et al. (2024) converge on a structure containing: (a) a role assignment, (b) a task description, (c) the given text (writing samples), and (d) output format specification. Example: "You are a literary stylist. Using the writing samples below as your sole stylistic reference, generate text on [topic] that faithfully reproduces the author's sentence structure, vocabulary register, figurative language patterns, and paragraph rhythm. [SAMPLES]. Output the result directly with no preamble."

3. **Combined instruction + example prompts outperform either alone.** Explicit stylistic directives ("use short declarative sentences, avoid adjectives, employ parataxis") paired with concrete text examples produce stronger initial style adherence and better persistence across multi-turn interactions than either approach alone (Bohr, 2025).

4. **The "analyze then write" pipeline is the strongest known approach.** The Tree-of-Thoughts methodology (Yu et al., 2024) and the Style Blueprint approach both follow: Step 1 — have the LLM extract and describe the target style's features (sentence length distribution, vocabulary register, use of figurative language, structural patterns, most frequent words/phrases). Step 2 — generate new text constrained by that extracted style description. This significantly outperforms single-pass prompting.

### 4.2 Style Description vs. Author Naming

- Naming an author ("write in the style of Hemingway") triggers the model's internal representation of that author, which is often a **stereotyped or caricatured** version — the most salient, distinctive markers amplified at the expense of subtler features.
- **Style description prompts** — specifying concrete stylistic parameters ("use short declarative sentences, concrete nouns, avoid adjectives, employ polysyndeton") — provide more controllable style transfer because they give the model testable constraints rather than relying on its internal associations.
- The two approaches are complementary: naming the author can provide thematic and tonal orientation, while explicit style parameters constrain the execution. The Style Blueprint methodology effectively operationalizes this by having the model itself generate the style description from samples, which can then be reused.

### 4.3 Failure Modes and Mitigations

1. **Generative exaggeration (caricature):** The primary failure mode. LLMs systematically amplify salient traits — emoji/hashtag frequency 10–20× above human baselines, extreme deployment of signature phrases. Root cause: models optimized for salience over subtlety. **Mitigation:** Use negative prompting ("do not overuse [author's signature device], use it no more than once per paragraph") and temperature reduction (0–0.3 for style-consistent output).

2. **Mid-response style reversion:** Style control decays over longer outputs; the model gradually reverts to its default fluent-but-generic voice. **Mitigation:** Break long outputs into segments and re-inject the style prompt between segments. For multi-agent approaches, have a "style consistency" agent review and re-anchor the output.

3. **Zero-shot overconfidence:** Models produce confidently wrong pastiche in zero-shot settings — the verifier reports >95% confidence while accuracy is <7%. **Mitigation:** Never rely on zero-shot style transfer. Always provide samples.

4. **Style-content tradeoff:** Content preservation degrades as style strength increases. **Mitigation:** The "analyze then write" pipeline partially addresses this by separating the style extraction and content generation phases.

5. **Structured vs. informal domain gap:** Models perform significantly better on structured formats (news, email) than informal ones (blogs, forums). **Mitigation:** For the novelist-style approach, the target style is likely closer to the structured/literary domain where models perform better, which is favorable for this project.

### 4.4 Multi-Step Approaches

- **Tree-of-Thoughts (ToT)** is the most effective prompting framework tested for style imitation (Yu et al., 2024). The ToT process: (1) generate multiple plans for style imitation, (2) have the model vote on the best plan, (3) generate multiple outputs based on the best plan, (4) vote on the best output. This produced significantly higher human evaluation scores (12.80 vs. ~11.50 for CoT and standard prompting) and a 30% automatic evaluation success rate vs. 12% for CoT and 8% for standard.

- **Chain-of-Thought (CoT)** offers modest improvement over standard prompting but much less than ToT. The CoT structure tested was: Step 1 — analyze the target's word choice and phrasing; Step 2 — analyze sentence structure and figurative language; Step 3 — generate a conversation using those patterns.

- **Style Blueprint / Reverse-Engineering:** The practitioner approach of having the LLM first analyze writing samples, then summarize the style into a reusable one-paragraph specification, then prepend that to all prompts. This is essentially a manual, reusable version of the analyze-then-write pattern.

- **ZeroStylus hierarchical framework** (2025): For long-text style transfer, a dual-layer approach combining sentence-level stylistic adaptation with paragraph-level structural coherence, using template repositories extracted from reference texts.

### 4.5 Community Resources and Prompt Libraries

- **prompts.chat** (formerly Awesome ChatGPT Prompts): Largest open-source prompt library. 162K+ GitHub stars. Community-contributed. Writing style prompts exist but are not a prominent category; the platform is dominated by image-generation and general productivity prompts. Relevant primarily as infrastructure — a custom author-style prompt could be contributed here.

- **PromptBase**: Commercial marketplace with 270K+ prompts, primarily for image generation (Midjourney, DALL-E). Text-based style transfer prompts exist but are a minor category. Paywalled (prompts cost money). Low relevance for academic-style author mimicry.

- **Academic prompt templates**: The most directly usable resources are the prompt structures published in the academic papers themselves. Bhandarkar et al. (2024) and Yu et al. (2024) provide full prompt text in their appendices. These are validated and freely available.

- **Claude Custom Styles**: Anthropic's built-in feature allows uploading writing samples to create reusable style presets. Abubakar's (2025) experiment found it produces "inspiration-driven, not author-driven" output — it captures theme and tone but not sentence-level structural mimicry. Useful as a rapid prototyping tool but insufficient for faithful authorial replication.

### 4.6 Implications for the Multi-Agent Persona Approach

The user's proposed architecture — multiple subagents each writing in a different novelist's style, with a main agent combining the best elements — is novel and does not appear directly in the literature. The following design considerations emerge from the research:

1. **Each subagent needs its own few-shot exemplars.** A subagent tasked with "Hemingway style" needs 3–5 unaltered Hemingway excerpts, not just the name.

2. **Style fusion is the hardest unsolved problem.** Combining outputs from stylistically distinct agents risks producing incoherent pastiche — a text that oscillates between Hemingway's parataxis and Austen's periodic sentences. A "style consistency" pass is essential.

3. **The analyze-then-write pattern should be applied per subagent.** Each subagent should first extract the target author's style features from the provided samples, then write. This gives the main agent structured style descriptions to work with when combining.

4. **Negative prompting is critical for multi-author fusion.** Each subagent should receive explicit constraints about what NOT to do (e.g., for Hemingway: "do not use more than one adjective per sentence, do not use abstract nouns, do not use semicolons"). This reduces the caricature risk that compounds when multiple stylized outputs are merged.

5. **Temperature should be low (0–0.3) for style consistency.** Higher temperatures amplify the model's tendency toward exaggeration and stylistic drift.

## 5. Bibliography

Bohr, J. (2025). *Show and Tell: Prompt Strategies for Style Control in Multi-Turn LLM Code Generation* (arXiv:2511.13972). Under review. https://arxiv.org/abs/2511.13972

Bhandarkar, A., Wilson, R., Swarup, A., & Woodard, D. (2024). Emulating author style: A feasibility study of prompt-enabled text stylization with off-the-shelf LLMs. In *Proceedings of the 1st Workshop on Personalization of Generative AI Systems (PERSONALIZE 2024)* (pp. 76–82). Association for Computational Linguistics. https://aclanthology.org/2024.personalize-1.10/

Jemama, R., et al. (2025). *How Well Do LLMs Imitate Human Writing Style?* (arXiv:2509.24930). https://arxiv.org/abs/2509.24930

Wang, Z., Tripto, N. I., Park, S., Li, Z., & Zhou, J. (2025). *Catch Me If You Can? Not Yet: LLMs Still Struggle to Imitate the Implicit Writing Styles of Everyday Authors* (arXiv:2509.14543). https://arxiv.org/html/2509.14543v1

Yu, J., et al. (2024). *Using Prompts to Guide Large Language Models in Imitating a Real Person's Language Style* (arXiv:2410.03848). https://arxiv.org/html/2410.03848v1

Abubakar. (2025, April 12). Replicate an author's writing style using prompt engineering. *DEV Community*. https://dev.to/thatechmaestro/replicate-an-authors-writing-style-using-prompt-engineering-insights-from-an-experiment-with-2hfk

Generative exaggeration in LLM social agents: Consistency, bias, and toxicity. (2025). *ScienceDirect*, S246869642500045X. https://www.sciencedirect.com/science/article/pii/S246869642500045X

Style outweighs substance: Failure modes of LLM judges in alignment benchmarking. (2025). (arXiv:2409.15268). https://arxiv.org/abs/2409.15268

LLMs can be easily confused by instructional distractions. (2025). (arXiv:2502.04362). https://arxiv.org/html/2502.04362v1

How to train an AI to mimic your writing style: The end of the generic voice. (2025, November 4). *FinancialContent*. https://www.financialcontent.com/article/worldnewswire-2025-11-4-how-to-train-an-ai-to-mimic-your-writing-style-the-end-of-the-generic-voice

How to train AI to match your writing style. (n.d.). *eesel AI Blog*. https://www.eesel.ai/blog/how-to-train-ai-to-match-your-writing-style

prompts.chat — AI Prompts Community. (n.d.). https://prompts.chat/ and https://github.com/f/prompts.chat

PromptBase — The #1 Marketplace for AI Prompts. (n.d.). https://promptbase.com/

ZeroStylus: Implementing long text style transfer with LLMs through dual-layered sentence and paragraph structure extraction and mapping. (2025). *OpenReview*. https://openreview.net/forum?id=NoeyaHgrFX

Authorship style transfer with inverse transfer data augmentation. (2024). *ScienceDirect*, S2666651024000135. https://www.sciencedirect.com/science/article/pii/S2666651024000135
