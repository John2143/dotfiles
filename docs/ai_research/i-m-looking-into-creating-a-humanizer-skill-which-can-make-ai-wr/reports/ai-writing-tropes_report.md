# AI Writing Tropes and Detection Markers: A Systematic Report

## 1. Summary

AI-generated text bears a constellation of detectable linguistic fingerprints that distinguish it from human writing. These markers operate at multiple levels: statistical (perplexity, burstiness), lexical (overused vocabulary and transition phrases), syntactic (uniform sentence length, template reuse), structural (balanced paragraphs, formulaic introductions and conclusions), and rhetorical (excessive hedging, lack of personal voice, absence of lived experience). Detection tools such as GPTZero, Turnitin, and Originality.ai combine these signals into composite probability scores, with reported accuracy ranging from 85% to 99% on raw AI output — though rates drop sharply when text is paraphrased or human-edited.

The most systematically catalogued AI stylistic tics include: overuse of transition words ("Furthermore," "Moreover," "In conclusion"), hedging language ("It is important to note," "It is worth mentioning"), adjective inflation ("robust," "pivotal," "comprehensive," "holistic," "nuanced"), balanced-sentence constructions (relentless tricolons and antitheses), and meta-commentary ("Let me explain," "This means several things"). Large-scale corpus analyses have quantified these patterns: a 2024 study of 15 million PubMed abstracts identified 379 "excess vocabulary" words whose frequency surged after ChatGPT's release — with "delve" used roughly 50 times more by AI than by human academic writers. The VERMILLION framework (Sood, 2025) provides the most structured human-interpretable taxonomy, organizing ten detection heuristics: Vague "their," Echoed sentence structures, Rigid transitions, Mechanical punctuation, Inflexible paragraphing, Lack of short paragraphs, Lack of personal voice, Imprecise abstraction, Overuse of hedging, and No lived experience.

Different models exhibit distinct stylistic fingerprints. ChatGPT output is the most detectable (flagged 68–96% of the time across detectors), characterized by low perplexity, narrow sentence-length bands, and heavy reliance on stock transitions and hedging. Claude produces text with higher burstiness and vocabulary diversity, evading detection more effectively (23–35% flagged), though its sustained thoughtfulness and measured tone are themselves subtle tells. Gemini favors rigid list-heavy organization and claim-evidence-conclusion paragraphing that detectors increasingly flag on structural grounds. Copyleaks research (Bitton et al., 2025) demonstrates that LLM-specific classifiers can identify which model family generated a text with precision exceeding 0.998 — confirming that each model leaves a stable, detectable stylistic fingerprint.

Critically, detection is not a solved problem. False positives disproportionately affect non-native English writers, for whom simplified vocabulary and consistent grammar can produce perplexity scores resembling AI output. The adversarial arms race between generators and detectors continues: humanizer tools now achieve 94–99% pass rates against GPTZero, while detectors respond with specialized paraphrase-detection layers. No single marker guarantees AI authorship; the co-occurrence of multiple signals across a document provides the strongest inference.

## 2. Relation to Primary Question

Understanding the specific linguistic patterns, tropes, and markers that make AI text detectable directly informs the design of humanizer tools, persona-based rewriting, and author-style mimicry systems. A humanizer that cannot recognize and systematically address these markers — from perplexity and burstiness at the statistical level to transition overuse and hedging at the stylistic level — will fail to produce output that evades detection or reads as authentically human. These findings define the negative space: the patterns a humanizer must learn to avoid or transform.

## 3. Source Evaluation

### Primary Academic Sources

**Source 1: Sood, S. (2025). "The Disappearing Author: Linguistic and Cognitive Markers of AI-Generated Communication." *Journal of Entrepreneurship and Business Development*, 5(1), 7–25.**
URL: https://doi.org/10.18775/ijmsba.1849-5664-5419.2014.51.7001

- **Credibility assessment:** Primary source. Peer-reviewed journal article by an Industry/Professional Fellow at the Australian Artificial Intelligence Institute, University of Technology Sydney. Published November 2025. Introduces the VERMILLION framework — the most structured heuristic taxonomy of AI writing markers currently available. Grounded in stylometry, cognitive linguistics, and AI interpretability literature. Applied to a real-world policy document (White House MAHA report).
- **Weighting:** High. This is the most directly relevant primary framework for cataloguing AI writing markers. Its heuristic approach (ten named, defined signals with detection rules of thumb) is directly actionable for humanizer tool design.

**Source 2: Bitton, Y., Bitton, E., & Nisan, S. (2025). "Detecting Stylistic Fingerprints of Large Language Models." arXiv:2503.01659.**
URL: https://arxiv.org/abs/2503.01659

- **Credibility assessment:** Primary source. Preprint by Copyleaks researchers presenting a novel ensemble classification method. Achieves precision of 0.9988 and false-positive rate of 0.0004 on distinguishing outputs from Claude, Gemini, Llama, and OpenAI model families. Demonstrates that models from the same family share fingerprints, and that fingerprint similarities reveal relationships (e.g., DeepSeek-R1 strongly resembles OpenAI). Validated on 200,000 test texts plus 52,000 texts from unseen models.
- **Weighting:** High for the claim that each LLM has a stable, detectable stylistic fingerprint. The empirical rigor (three diverse classifiers, unanimous voting, cost-sensitive design, generalization testing on unseen models) is strong. As a preprint, it has not completed peer review, but the Copyleaks affiliation and methodological transparency are credible.

**Source 3: Kobak, D., González-Márquez, R., Horvát, E.-Á., & Lause, J. (2024). "Delving into LLM-assisted writing in biomedical publications through excess vocabulary." *Science Advances*. DOI: 10.1126/sciadv.adt3813.**
URL: https://www.science.org/doi/10.1126/sciadv.adt3813

- **Credibility assessment:** Primary source. Peer-reviewed in *Science Advances*, a high-impact journal. Analyzed 15+ million PubMed abstracts (2010–2024) to quantify vocabulary shifts after ChatGPT's release. Identified 379 "excess vocabulary" style words with statistically elevated frequencies. Found that at least 13.5% of 2024 biomedical abstracts showed LLM processing.
- **Weighting:** High. This is the gold-standard empirical source for quantifying which specific words AI overuses relative to humans. The large-scale, unbiased methodology using excess-word analysis is robust. The specific word lists provide concrete targets for any humanizer tool.

### Secondary Technical Sources

**Source 4: GPTZero. (2025). "What is perplexity & burstiness for AI detection?"**
URL: https://gptzero.me/news/perplexity-and-burstiness-what-is-it/

- **Credibility assessment:** Secondary source. Official documentation from a leading commercial AI detection vendor. Explains their core metrics (perplexity, burstiness) with clear definitions and examples. Reports their own 2026 detection statistics: 92.4% accuracy, 0.24% false positive rate; Paraphraser Shield at 93.5% recall against humanizer tools. Clearly biased toward promoting their own product. Technical definitions are sound and consistent with academic literature.
- **Weighting:** Medium-high for technical definitions and detection methodology. Medium for accuracy claims (vendor self-reporting). Cross-referenced with independent benchmarks.

**Source 5: Turnitin. (2024–2026). AI writing detection documentation.**
URL: https://guides.turnitin.com/hc/en-us/articles/28294949544717-AI-writing-detection-model

- **Credibility assessment:** Secondary source. Official documentation from the dominant academic integrity platform. Describes 300-word segment analysis, dual detection categories (AI-generated only vs. AI-paraphrased), and asterisk flagging for scores 0–20%. Acknowledges higher false positive incidence below 20% probability. Independent reviews note the gap between vendor-claimed accuracy (98% confidence) and real-world conditions.
- **Weighting:** Medium-high for understanding detection pipeline architecture. Claims are vendor-authored and should be weighed against independent benchmarks.

**Source 6: Originality.ai. (2025). "How Does AI Content Detection Work?"**
URL: https://originality.ai/blog/how-does-ai-content-detection-work

- **Credibility assessment:** Secondary source. Vendor documentation describing their modified BERT model, multi-signal approach (perplexity + burstiness + proprietary classifier), and three detection model tiers (Lite, Turbo, Academic). Independent benchmarks (GPTZero RAID, CyberNews 2026) report 83–92% accuracy with 4.79–5.7% false positive rates — notably higher than the vendor's claimed 0.5–1.5%.
- **Weighting:** Medium for technical architecture description. Claims should be evaluated against independent benchmarks; the gap between vendor and independent false-positive rates is substantial.

### Journalistic and Industry Sources

**Source 7: Decrypt. (2025). "The 5 Biggest 'Tells' That Something Was Written By AI."**
URL: https://decrypt.co/348923/5-biggest-tells-something-written-ai

- **Credibility assessment:** Secondary source. Crypto/tech journalism outlet. Article synthesizes stylometric research and practitioner observations. Detailed, well-structured taxonomy of AI tells: tricolons, antithesis, lexical fingerprints, structural balance, and the "missing mess" of human drafting. Written with strong stylistic personality. No named author or specific empirical methodology. References academic stylometry research but does not provide formal citations. Contains a deliberately self-demonstrating structure (the article uses the very tics it criticizes in its examples).
- **Weighting:** Medium. Excellent taxonomy and readability. Useful as a synthesis of practitioner knowledge. Not a primary research source. The author's stylistic sophistication (Cherryleaf, a technical communications consultancy) adds credibility to the observational claims.

**Source 8: Cherryleaf. (2026). "Indicators That Suggest Something Was Written by AI."**
URL: https://www.cherryleaf.com/2026/02/indicators-that-suggest-something-was-written-by-ai/

- **Credibility assessment:** Secondary source. Technical communications consultancy blog. The article is itself a meta-exercise: the authors researched AI writing indicators and then instructed Claude to write about them in that style. The result is an extensive catalog organized by category: rhetorical patterns (tricolon, antithesis, rhetorical questions), verbal fingerprints (specific overused words and phrases), structural tells (relentless balance, generic specificity), and tonal problems (uniform register, risk aversion, enthusiasm gap). Provides the most comprehensive single-source lexicon of AI verbal tics.
- **Weighting:** Medium-high for comprehensiveness of the lexical catalog. The meta-demonstrative structure (AI writing about AI writing patterns) adds analytical depth. Not peer-reviewed research, but the systematic categorization and specific phrase lists are directly actionable.

**Source 9: SEOteric / Search Engine Land. (2026). "Which AI Writing 'Tics' Actually Hurt Engagement."**
URL: https://www.seoteric.com/which-ai-writing-tics-actually-hurt-engagement-and-what-marketers-should-do-about-it/

- **Credibility assessment:** Secondary source. SEO agency blog summarizing Adam Gnuse's Search Engine Land study analyzing 1,000+ content marketing pages. Key empirical finding: em dashes (often cited as an AI tell) show a slight *positive* correlation with engagement, while repetitive concessive phrases ("not only… but also") and explicit "Conclusion" headers show the strongest *negative* correlation.
- **Weighting:** Medium. Provides the only engagement-correlated data in the source set. Important corrective to the assumption that all AI tics harm readability equally. The underlying Search Engine Land study should be accessed directly for full methodology.

**Source 10: HumanizeThisAI. (2026). "ChatGPT vs Claude vs Gemini: Writing Quality Compared."**
URL: https://humanizethisai.com/blog/chatgpt-vs-claude-vs-gemini-writing

- **Credibility assessment:** Secondary source with acknowledged commercial bias (published by an AI humanizer tool vendor). Blind test with 134 participants across 8 writing tasks. Detection rates from GPTZero, Turnitin, Originality.ai, and Copyleaks compared. Key findings: ChatGPT detected 68–96% of the time, Claude 23–35%, Gemini 52–70%. Vendor self-discloses their product relationship. Detection rates draw from independent testing.
- **Weighting:** Medium. Useful for the comparative detection-rate table and model-specific writing characterizations. The blind test (n=134) provides some empirical grounding, though methodology details are limited. Model-specific tells align with other sources.

**Source 11: Pangram Labs. (2025–2026). "Comprehensive Guide to Spotting AI Writing Patterns."**
URL: https://www.pangram.com/blog/comprehensive-guide-to-spotting-ai-writing-patterns

- **Credibility assessment:** Secondary source. AI detection vendor blog. Provides the most extensive published word/phrase list: hundreds of nouns, verbs, adjectives, adverbs, and multi-word phrases that appear disproportionately in AI text. Categories span phrasing patterns, spelling/grammar, organization, tone, creativity, specificity, repetition, and style shifts. Organization-level observations (AI uses Oxford commas, avoids semicolons, maintains perfect grammar) complement word-level catalogs.
- **Weighting:** Medium. The word lists are observational/empirical but methodology is not documented. Useful as a comprehensive reference catalog. The claim that "60–70% of names in AI-generated articles are 'Emily' or 'Sarah'" is striking but unverified — treat as indicative not definitive.

**Source 12: SearchAtlas. (2026). "How to Detect AI Patterns in Writing?"**
URL: https://searchatlas.com/blog/ai-patterns-in-writing/

- **Credibility assessment:** Secondary source. SEO tool vendor blog. Provides clear explanations of burstiness as a structural metric, hedging categories (modal verbs, probabilistic verbs, qualifying adjectives, approximation adverbs), and the ESL false-positive problem (citing the Stanford/GPT detectors bias study from PMC).
- **Weighting:** Medium. Useful for hedging taxonomy and ESL bias discussion. References to PMC-hosted research (Liang et al., 2023) are credible secondary citations.

**Source 13: Hastewire. (2026). "Uncover Linguistic Patterns of AI Writing: Key Tells."**
URL: https://hastewire.com/blog/uncover-linguistic-patterns-of-ai-writing-key-tells

- **Credibility assessment:** Secondary source. AI detection blog. Synthesizes research on perplexity scoring, stylometric analysis, and computational techniques. References the SSRN comparative analysis by Kujur (2025), the ScienceDirect comprehensive review, and the Springer hand-crafted vs. deep learning comparison.
- **Weighting:** Low-medium. Useful as a secondary synthesis but adds little beyond what primary sources provide directly.

## 4. Conclusions

### 4.1 Statistical-Level Markers: The Core of Automated Detection

AI detection tools converge on two primary statistical signals:

**Perplexity** measures how "surprised" a language model is by a text. AI-generated text scores low perplexity by construction — the model chose the most statistically probable words at each step. Human writing contains unexpected word choices that spike perplexity. Detection tools train classifiers on these probability profiles.

**Burstiness** measures variation in sentence length and syntactic complexity across a document. Human writers alternate between short declarative sentences and longer complex constructions. AI maintains more uniform sentence lengths and structural rhythm. Low burstiness (narrow standard deviation of sentence lengths) is one of the strongest detection signals.

**Actionable insight for humanizer design:** A humanizer must deliberately introduce perplexity (unexpected word choices, non-obvious phrasings) and burstiness (genuine variation in sentence length from 3–4 words to 40+ words). Simply rewriting vocabulary while maintaining uniform rhythm will not defeat statistical detection.

### 4.2 Lexical Markers: The Most Actionable Category

Multiple sources converge on a consistent catalog of AI-overused words:

**Transition words:** Furthermore, Moreover, Additionally, In conclusion, In summary, Overall, Consequently, Thus, Hence, Notably, Crucially.

**Hedging phrases:** It is important to note, It is worth mentioning, It is worth noting, Generally speaking, One might argue, There are several factors to consider, Research suggests, Evidence indicates.

**Inflated adjectives:** Robust, pivotal, comprehensive, holistic, nuanced, multifaceted, paramount, essential, crucial, critical, profound, vibrant, seamless, meticulous.

**AI-favorite verbs:** Delve (50× more than humans), underscore, navigate, leverage, foster, showcase, unveil, highlight, explore, embrace, empower, facilitate, cultivate, drive (innovation), unlock, unleash, resonate, transcend, elevate.

**Abstract nouns favored by AI:** Landscape, realm, tapestry, paradigm, ecosystem, interplay, complexities, nuances, testament, implications, insights, significance, era, journey, quest.

**Structural tics:** Em dashes for dramatic pauses (—), Oxford commas, avoidance of semicolons, avoidance of sentence fragments, avoidance of sentences beginning with "And" or "But."

**Actionable insight:** A humanizer needs a concrete "forbidden words" list — or rather, a density threshold. One "moreover" in a 5,000-word text is unremarkable; five "moreovers," three "delves," and two "tapestries" in the same document will trigger detectors and human reviewers alike.

### 4.3 Rhetorical and Structural Markers: The Human-Readable Tells

Beyond word-level patterns, AI text exhibits characteristic rhetorical structures:

**Tricolon obsession:** Grouping ideas in threes ("time, resources, and attention"; "identify, evaluate, and recommend") appears with mechanical consistency.

**Perfect antithesis:** "Not just X, but Y" constructions used relentlessly, paragraph after paragraph.

**Meta-commentary and signposting:** "This means several things." "This requires three approaches." "Let me break this down." AI announces every logical connection rather than trusting readers to follow.

**Balanced coverage:** Every section gets equal treatment. Four factors → four paragraphs of nearly identical length. Pros and cons presented with perfect symmetry. Humans show bias — they spend three paragraphs on what fascinates them and one sentence on what doesn't.

**Formulaic conclusions:** Long conclusions that begin with "In conclusion" or "Overall," then restate the introduction nearly verbatim.

**The "missing mess":** Human first drafts contain false starts, redundancies, tangents. AI produces clean, error-free prose on the first try. This perfection is itself a tell.

**Generic specificity:** AI provides examples that feel specific without being specific ("A procurement policy that made sense for a manufacturing business might not work for a software division"). Human experts cite actual cases, name companies, reference specific failures.

### 4.4 Model-Specific Fingerprints

**ChatGPT (GPT-4, GPT-4o):** Most detectable model. Highest density of stock transitions and hedging. Sentence lengths cluster at 15–25 words. Low burstiness. Overuses "delve," "robust," "pivotal," "moreover." Conclusions restate introductions. Market leader → detectors have the most training data on its output.

**Claude (3.5/4.5 Sonnet):** Hardest to detect. Higher natural burstiness. Uses contractions naturally. Broader vocabulary distribution. Avoids ChatGPT's stock phrases. Its tell: consistently thoughtful and measured in a way humans rarely sustain. Almost "too" good. Leans on em dashes.

**Gemini:** Most structurally rigid. Heavy reliance on bullet points and numbered lists. Strict claim-evidence-conclusion paragraphing. List-heavy structure makes it detectable through organizational patterns even when individual sentences sound human.

**DeepSeek-R1:** Copyleaks research shows strong stylistic similarity to OpenAI models — 74.2% of DeepSeek texts classified as OpenAI by their ensemble. Suggests possible training-data relationship or architectural convergence.

**Actionable insight:** A humanizer strategy effective against one model's fingerprints may be ineffective against another's. A persona-based approach (channeling specific author styles) inherently addresses this by replacing model-specific fingerprints with human-author-specific ones.

### 4.5 The VERMILLION Framework: A Complete Heuristic Taxonomy

Sood (2025) provides the most structured detection framework, with ten named signals:

| Signal | Description | Detection Rule |
|--------|-------------|---------------|
| V — Vague "their" | Frequent possessive pronouns without clear antecedents | Search for "their"; check antecedent clarity |
| E — Echoed sentence structures | Template reuse, uniform clause rhythm | Read aloud; listen for "drumbeat" cadence |
| R — Rigid transitions | Formulaic connectors at paragraph openings | >30% of sentences begin with same 3 transition words |
| M — Mechanical punctuation | Uniform punctuation patterns or em-dash overload | Count em dashes; check for rhythm uniformity |
| I — Inflexible paragraphing | Paragraphs of uniform length/pacing | Highlight paragraph lengths; check for variation |
| L — Lack of short paragraphs | No one-line paragraphs for emphasis | Search for 1-sentence paragraphs; if absent, flag |
| L — Lack of personal voice | Absence of subjective tone, anecdotes, opinion | Ask: "Could anyone have written this?" |
| I — Imprecise abstraction | Cascades of abstract nouns masking agency | Replace nominalizations with active verbs |
| O — Overuse of hedging | Excessive modal verbs and qualifiers | Count "might," "may," "could" density |
| N — No lived experience | Absence of anecdotes, personal narratives, concrete provenance | Check for personal examples, quotes, named specifics |

A composite VERMILLION score of 7+ out of 10 flags suggests probable AI authorship. The framework is designed to be both human-applicable (forensic reading) and machine-automatable (NLP rule-based detection).

### 4.6 Critical Limitations and Caveats

**False positives and ESL bias:** Non-native English writers face elevated false-positive rates because simplified vocabulary and consistent grammar produce low perplexity scores resembling AI output. Stanford research (Liang et al., 2023, PMC) documented false-positive rates as high as 70% for ESL students in perplexity-based systems.

**The arms race:** Humanizer tools now achieve 94–99% pass rates against GPTZero. Detectors respond with paraphrase-detection layers (GPTZero's Paraphraser Shield: 93.5% recall). The adversarial cycle means no detection methodology is permanently reliable.

**Convergence risk:** As LLMs improve at mimicking human variation, the statistical gap between human and AI text narrows. Detection based on early-model artifacts (GPT-3.5/4 patterns) may not generalize to future models.

**No single marker is conclusive:** The accumulation of multiple signals across a document is what provides reliable inference. Any humanizer that addresses only one category (e.g., vocabulary) while leaving others intact (e.g., structural uniformity, hedging density) will still be detectable.

### 4.7 Synthesis: What This Means for a Humanizer Skill

A humanizer that can produce detection-resistant, human-sounding text must operate at multiple levels simultaneously:

1. **Statistical level:** Introduce burstiness (variable sentence lengths) and controlled perplexity (unexpected but contextually appropriate word choices).
2. **Lexical level:** Maintain a density-thresholded "AI vocabulary" filter. Replace stock transitions with varied, context-appropriate alternatives. Remove inflated adjectives. Eliminate formulaic hedging.
3. **Rhetorical level:** Break tricolons. Avoid perfect antithesis. Trust the reader to follow logical connections without explicit signposting. Allow asymmetry in coverage.
4. **Structural level:** Vary paragraph lengths. Include one-sentence paragraphs for emphasis. Write short conclusions that don't restate the introduction.
5. **Voice level:** Introduce personal perspective, concrete examples, named specifics, and genuine opinion. Anchor claims in lived-experience language where genre-appropriate.
6. **Model-aware:** Recognize that different base models leave different fingerprints. A Claude-based humanizer faces different challenges than a ChatGPT-based one. Persona-driven approaches that route through specific authorial styles inherently address this by supplanting model fingerprints with human-author fingerprints.

The persona-based, multi-author approach described in the project brief is well-aligned with these findings. Channeling a specific author's style — with that author's characteristic sentence rhythms, vocabulary preferences, structural idiosyncrasies, and tonal register — directly counteracts the uniformity that makes AI text detectable.

## 5. Bibliography

Bitton, Y., Bitton, E., & Nisan, S. (2025). Detecting stylistic fingerprints of large language models. *arXiv preprint*. https://arxiv.org/abs/2503.01659

Cherryleaf. (2026, February 13). Indicators that suggest something was written by AI. https://www.cherryleaf.com/2026/02/indicators-that-suggest-something-was-written-by-ai/

Decrypt. (2025, November 17). The 5 biggest 'tells' that something was written by AI. https://decrypt.co/348923/5-biggest-tells-something-written-ai

GPTZero. (2025, October 14). What is perplexity & burstiness for AI detection? https://gptzero.me/news/perplexity-and-burstiness-what-is-it/

Gnuse, A. (2026, February 25). The AI writing tics that hurt engagement: A study. *Search Engine Land*. https://searchengineland.com/ai-writing-tics-engagement-study-470051 (Summarized by SEOteric: https://www.seoteric.com/which-ai-writing-tics-actually-hurt-engagement-and-what-marketers-should-do-about-it/)

Hastewire. (2026, January 27). Uncover linguistic patterns of AI writing: Key tells. https://hastewire.com/blog/uncover-linguistic-patterns-of-ai-writing-key-tells

HumanizeThisAI. (2026, March 18). ChatGPT vs Claude vs Gemini: Writing quality compared. https://humanizethisai.com/blog/chatgpt-vs-claude-vs-gemini-writing

Kobak, D., González-Márquez, R., Horvát, E.-Á., & Lause, J. (2024). Delving into LLM-assisted writing in biomedical publications through excess vocabulary. *Science Advances*. https://doi.org/10.1126/sciadv.adt3813

Kujur, A. (2025). A comparative analysis of AI-generated and human-written text: Linguistic patterns, detection accuracy, and implications for modern communication. *SSRN*. https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5833302

Liang, W., Yuksekgonul, M., Mao, Y., Wu, E., & Zou, J. (2023). GPT detectors are biased against non-native English writers. *PMC*. https://pmc.ncbi.nlm.nih.gov/articles/PMC10382961/

Originality.ai. (2025, October 17). How does AI content detection work? https://originality.ai/blog/how-does-ai-content-detection-work

Pangram Labs. (2026). Comprehensive guide to spotting AI writing patterns. https://www.pangram.com/blog/comprehensive-guide-to-spotting-ai-writing-patterns

SearchAtlas. (2026). How to detect AI patterns in writing? https://searchatlas.com/blog/ai-patterns-in-writing/

Sood, S. (2025). The disappearing author: Linguistic and cognitive markers of AI-generated communication. *Journal of Entrepreneurship and Business Development*, 5(1), 7–25. https://doi.org/10.18775/ijmsba.1849-5664-5419.2014.51.7001

Turnitin. (2024–2026). AI writing detection model. *Turnitin Guides*. https://guides.turnitin.com/hc/en-us/articles/28294949544717-AI-writing-detection-model
