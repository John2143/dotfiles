# Humanness Evaluation Methods for AI-Generated Text

## 1. Summary

Evaluating how "human" a text sounds is a multi-dimensional problem with no single definitive solution. Current approaches fall into four broad categories: AI detection tools that measure statistical text properties (perplexity, burstiness, structural patterns); human evaluation methods (blind A/B testing, Turing-style tests, expert judgment, reader preference studies); computational stylometry (Burrows' Delta, authorship attribution, stylometric distance metrics); and hybrid frameworks that combine multiple approaches.

AI detection tools — GPTZero, Turnitin, Originality.ai, and others — rely primarily on two core signals: **perplexity** (how "surprised" a language model is by word choices; human text averages 80–100 units vs. GPT-4's 20–30) and **burstiness** (variance in sentence structure and perplexity across a document; humans score 0.6–1.2 vs. GPT's 0.2–0.4). These metrics exploit the fact that LLMs produce text with unnaturally consistent predictability and uniform sentence patterns. However, these tools have critical limitations: a Stanford study found 61.22% false-positive rates on TOEFL essays by non-native English speakers, and at least 12 elite universities have disabled Turnitin's AI detection specifically because of this bias. Modern humanizer tools can reduce detection rates from 92.4% to 55–65% on the same text, demonstrating the ongoing arms-race dynamic.

Human evaluation methods offer complementary strengths but reveal surprising complexity. Recent research (Marco et al., 2025, arXiv:2506.03310) analyzing 1,471 stories with 101 annotators found that reader judgments cluster into two profiles: "surface-focused readers" (mainly non-experts) who prioritize readability and textual richness, and "holistic readers" (mainly experts) who value thematic depth and rhetorical variety. Expert readers prefer human-authored text in blind settings, but lay readers often prefer AI-generated text because it communicates more unambiguously. Both human evaluators and AI detectors perform only slightly better than chance (humans: 57% for AI texts, 64% for human texts), with no statistically significant difference between human and machine performance on detection tasks. This creates a fundamental challenge for evaluation: there is no single "ground truth" of humanness, only reader-relative judgments.

Computational stylometry provides a more objective lens. Burrows' Delta — which measures stylistic distance between texts using standardized frequencies of the most frequent function words — has been validated in distinguishing AI-generated text from human-authored text. O'Sullivan (2025, *Humanities and Social Sciences Communications*) applied Burrows' Delta to creative writing corpora and found clear, statistically significant stylistic clusters separating human texts from GPT-3.5, GPT-4, and Llama outputs, with human texts showing consistently broader, more dispersed clusters reflecting genuine stylistic diversity. The StyloAI system uses 31 stylometric features and a random forest classifier to distinguish AI from human text with high accuracy. Stylometry is particularly useful because it operates on function words — prepositions, particles, determiners — which are less consciously controlled and resistant to intentional manipulation, making them harder to "game" than perplexity/burstiness scores.

The core evaluation challenge is captured by Goodhart's Law: "When a measure becomes a target, it ceases to be a good measure." A humanizer optimized to minimize detector scores will find the mathematically optimal path to evade detection — often producing text that passes detectors but sounds uncanny or degraded. The solution is multi-metric diversification: no single evaluation dimension should drive optimization. A robust rubric must balance detector evasion (multiple detectors, not one), stylometric proximity to target author styles, and qualitative human judgment — while recognizing that effective detection evasion often correlates inversely with naturalness and readability.

## 2. Relation to Primary Question

The primary research question asks what humanizer tools exist for making AI-generated text sound more human through author style mimicry and persona-based rewriting. All evaluation methods surveyed here bear directly on this question because they define the success criteria any humanizer skill must optimize against. A humanizer that mimics author style must be evaluated not only by whether it evades detectors (a trap that leads to Goodhart-style metric gaming) but also by whether its output is stylometrically close to the target author, reads naturally to human judges across reader profiles, and preserves meaning while introducing the controlled "imperfection" — variance in sentence rhythm, idiosyncratic word choice, structural unpredictability — that characterizes genuine human prose.

## 3. Source Evaluation

### Source 1
- **URL:** https://gptzero.me/news/perplexity-and-burstiness-what-is-it/
- **Title:** "What is perplexity & burstiness for AI detection?" — GPTZero (October 14, 2025)
- **Assessment:** Primary source from the vendor itself. Explains GPTZero's own methodology directly. Credible for understanding what the tool claims to measure, but carries vendor bias — it presents the tool's capabilities favorably. Recent (2025). Weighted as authoritative on GPTZero's own methodology but insufficient as an independent accuracy assessment.

### Source 2
- **URL:** https://pmc.ncbi.nlm.nih.gov/articles/PMC12331776/
- **Title:** "Can we trust academic AI detective? Accuracy and limitations of AI-output detectors" — PMC/Springer Nature (2025)
- **Assessment:** Peer-reviewed primary research published in a PubMed Central-indexed journal. Analyzed 1,000 texts (250 human, 750 ChatGPT-generated across three model versions) using GPTZero, ZeroGPT, and Corrector App. Provides ROC analysis with AUC, sensitivity, and specificity values. Highly credible: peer-reviewed, quantitative methodology, clear statistical reporting. Recency is good (2025). One of the strongest sources in this report.

### Source 3
- **URL:** https://www.tryleap.ai/learn/perplexity-vs-burstiness
- **Title:** "Perplexity vs Burstiness — The Two Metrics That Flag AI Text" — Leap AI (2026)
- **Assessment:** Secondary source — a commercial AI tool vendor's educational blog. Provides useful quantitative benchmarks (human perplexity ~80–100, GPT-4 ~20–30; burstiness spreads 0.6–1.2 vs. 0.2–0.4) but these numbers are attributed to "GPTZero's public methodology" rather than independently verified. Moderate credibility: useful for framing but not independently validated.

### Source 4
- **URL:** https://www.eyesift.com/blog/ai-detector-accuracy-benchmarks-2026/
- **Title:** "AI Detector Accuracy Benchmarks 2026: GPTZero vs Turnitin vs Originality vs EyeSift — Tested" — EyeSift (2026)
- **Assessment:** Secondary source — a commercial AI detection vendor's benchmark comparison. Contains specific performance data (Originality.ai 94% detection rate, 2–3% false positive rate; humanizer tools reduce GPTZero detection from 92.4% to 55–65%). Also reports that 12 elite universities disabled Turnitin AI detection and the Stanford TOEFL bias study (61.22% false positives). Vendor bias exists (EyeSift is a competitor) but the specific claims are corroborated by academic literature. Weighted as useful for industry benchmarks with the caveat of commercial interest.

### Source 5
- **URL:** https://arxiv.org/abs/2506.03310
- **Title:** "The Reader is the Metric: How Textual Features and Reader Profiles Explain Conflicting Evaluations of AI Creative Writing" — Marco, Gonzalo, Fresno (2025)
- **Assessment:** Primary research (preprint, accepted at ACL 2025 Findings). Peer-reviewed by a top computational linguistics venue. Analyzes 1,471 stories and 101 annotators using 17 reference-less textual features. Identifies two reader profiles (surface-focused vs. holistic). Strong methodology with clear quantitative results. Highly credible — peer-reviewed, published at a top venue, specific methodology. Recency is excellent (June 2025).

### Source 6
- **URL:** https://www.nature.com/articles/s41599-025-05986-3
- **Title:** "Stylometric comparisons of human versus AI-generated creative writing" — O'Sullivan, *Humanities and Social Sciences Communications* (2025)
- **Assessment:** Primary peer-reviewed research published in a Nature Portfolio journal. Applies Burrows' Delta and MDS to compare human-authored and LLM-generated (GPT-3.5, GPT-4, Llama 70b) creative texts. Provides clear methodology with reproducible scripts (GitHub). Highly credible: Nature Portfolio journal, transparent methodology, reproducible. Includes important ethical caveat that stylometry should not be used for academic integrity enforcement. One of the strongest sources.

### Source 7
- **URL:** https://academic.oup.com/dsh/article-abstract/17/3/267/929277
- **Title:** "'Delta': a Measure of Stylistic Difference and a Guide to Likely Authorship" — Burrows, *Digital Scholarship in the Humanities* (2002)
- **Assessment:** The foundational primary source for Burrows' Delta. Peer-reviewed, published in an Oxford University Press journal. Seminal work that established the method. Though from 2002, it remains the canonical reference — its age reflects foundational status, not obsolescence. Highly credible.

### Source 8
- **URL:** https://zenodo.org/records/18177
- **Title:** "Towards a better understanding of Burrows's Delta in literary authorship attribution" — Evert, Proisl, et al. (2015/2024)
- **Assessment:** Primary research providing empirical evaluation of Delta variants. Concludes that no proposed variant constitutes a major improvement over the original. Important corrective to claims of superior Delta variants. Published via Zenodo (open access). Credible: rigorous empirical methodology by established computational linguists.

### Source 9
- **URL:** https://www.sciencedirect.com/science/article/pii/S1477388025000131
- **Title:** "Do humans identify AI-generated text better than machines? Evidence based on excerpts from German theses" — ScienceDirect (2025)
- **Assessment:** Peer-reviewed primary research. Directly compares human and machine detection performance, finding both perform near chance (humans: 57% AI, 64% human; no statistically significant difference). Provides evidence for the StyloAI system's 31 stylometric features. Credible: peer-reviewed journal publication, direct comparison methodology.

### Source 10
- **URL:** https://matthopkins.com/business/goodharts-law-ai-agents/
- **Title:** "AI agents will game any metric you give them: Goodhart's law explained" — Matt Hopkins (January 2026)
- **Assessment:** Secondary source — a professional blog post by a technologist. Not peer-reviewed. However, it articulates the Goodhart's Law dynamics with unusual clarity for the specific AI agent context, including the critical insight that "every additional constraint is just another optimisation target." Weighted as a well-articulated secondary explanation of a well-established principle, not as original research.

### Source 11
- **URL:** https://www.unitary.ai/articles/applying-goodharts-law-to-ai-generated-content-detection-misuse-innovation
- **Title:** "Applying Goodhart's Law to AI generated content detection: Misuse & Innovation" — Unitary (September 2023)
- **Assessment:** Secondary source from an AI safety company's blog. Applies Goodhart's Law specifically to AI content detection, arguing for multi-metric diversification. Vendor context (Unitary builds content moderation AI) provides domain expertise but also commercial interest. Weighted as a useful domain-specific framing.

### Source 12
- **URL:** https://gpt.gekko.de/goodhart-ai-alignment/
- **Title:** "When Metrics Go Wrong: A Tale of Goodhart's Law and AI Misalignment" (December 2025)
- **Assessment:** Secondary educational blog post. Not peer-reviewed but provides a clear synthesis of Goodhart's Law dynamics including goal misgeneralization and proxy hacking. Weighted as a pedagogical secondary source.

### Source 13
- **URL:** https://openai.com/index/measuring-goodharts-law/
- **Title:** "Measuring Goodhart's Law" — OpenAI (April 2022)
- **Assessment:** Primary research blog post from a leading AI research organization. While not a formal paper, it represents OpenAI's research findings on quantifying Goodhart effects in RL training. Authoritative given the source, though from 2022 (pre-LLM era for most practical purposes). Weighted as foundational reference for Goodhart dynamics in AI systems.

### Source 14
- **URL:** https://dl.acm.org/doi/full/10.1145/3708889
- **Title:** "Human vs. Machine: A Comparative Study on the Detection of AI-Generated Content" — *ACM Transactions on Asian and Low-Resource Language Information Processing* (2024)
- **Assessment:** Peer-reviewed primary research in a reputable ACM journal. Argues for hybrid systems combining automated detection and human expertise. Credible: ACM publication, rigorous comparative methodology.

### Source 15
- **URL:** https://arxiv.org/abs/2510.24011
- **Title:** "Understanding Reader Perception Shifts upon Disclosure of AI Authorship" (2025)
- **Assessment:** Primary research preprint. Documents how disclosing AI authorship negatively affects reader perceptions (loss of human touch, questioned expertise, inferred lack of effort). Also identifies AI literacy as a mitigating factor. Credible: systematic qualitative and quantitative methodology, though pre-peer-review as a preprint.

## 4. Conclusions

### 4.1 AI Detection Tools as Evaluation: Useful but Insufficient Alone

- GPTZero, Turnitin, and Originality.ai all measure some combination of perplexity, burstiness, and model-specific structural patterns. Their core signal is real — AI text is statistically more uniform — but their practical reliability is compromised by high false-positive rates (especially for non-native English writers and technical/legal prose) and vulnerability to humanizer tools.
- **Actionable insight:** Detection scores from multiple independent detectors should be part of a humanizer evaluation rubric, but never the sole criterion. A text that scores 0% on all detectors has likely been over-optimized and may read unnaturally.

### 4.2 Human Evaluation: Essential but Reader-Relative

- Human judgment is not a single standard. Surface-focused readers (non-experts) and holistic readers (experts) evaluate texts on fundamentally different dimensions. Any human evaluation protocol must specify the reader profile being targeted and include both expert and lay judges.
- Both humans and machines perform near chance on detection tasks. The implication for humanizer evaluation is that asking humans "Is this AI-generated?" is not a reliable metric. Instead, humans should be asked to rate specific qualities: naturalness of cadence, authenticity of voice, consistency of persona, overall preference in blind A/B comparisons.
- **Actionable insight:** Blind A/B preference testing (humanized vs. original AI output, humanized vs. genuine human text) with varied reader profiles is the most defensible human evaluation method. Include AI authorship disclosure as a variable to control for bias effects.

### 4.3 Computational Stylometry: The Most Objective but Not a Silver Bullet

- Burrows' Delta and related stylometric measures can reliably distinguish AI text from human text at the corpus level, particularly when analyzing the ~100 most frequent function words. LLM outputs form tight, distinct stylistic clusters while human texts show broad, dispersed patterns.
- Stylometry is harder to "game" than perplexity/burstiness because function word frequencies are less consciously controlled. However, stylometric methods are validated at the corpus level, not for individual short texts, and should never be used as the sole basis for authorship judgments.
- **Actionable insight:** For a humanizer skill using author style mimicry, the stylometric distance between the humanized output and the target author's genuine corpus (measured via Burrows' Delta or Cosine Delta) is a powerful evaluation metric. Lower Delta scores to the target author indicate more successful style transfer. This metric resists Goodhart-style gaming better than perplexity optimization alone.

### 4.4 Hybrid Frameworks: The Only Viable Approach

- No single evaluation dimension is sufficient. The most defensible frameworks combine:
  1. **Multi-detector pass rates** (at least 3 detectors: GPTZero, Originality.ai, Turnitin or equivalent) — measuring evasion without over-optimizing
  2. **Stylometric proximity** to target author (Burrows' Delta, Cosine Delta, function word frequency comparison)
  3. **Blind human preference testing** with varied reader profiles, measuring specific dimensions (cadence, tone, naturalness, voice authenticity) rather than binary "AI or human?" judgments
  4. **Meaning preservation checks** — does the humanized text retain the semantic content of the original? Over-aggressive humanization often degrades meaning.
- **Actionable insight:** A composite score weighting these dimensions (with human judgment carrying the most weight, detector scores the least) provides the most robust evaluation.

### 4.5 Building a Humanizer-Specific Evaluation Rubric

A defensible evaluation rubric for a humanizer skill must:

1. **Avoid single-metric optimization.** Run at least three independent detectors and report scores without targeting 0% on all. A text that reads naturally but scores 20–40% on some detectors is better than an uncanny text scoring 0% everywhere.
2. **Set minimum quality thresholds, not maximum evasion targets.** Define "good enough" as: ≥2/3 detectors score below 50%, stylometric Delta distance to target author is below the average human-human Delta distance within the target author's corpus, and ≥60% of blind human raters prefer the humanized output over the raw AI output.
3. **Use adversarial testing.** Run the humanizer output through detectors that use different underlying models and architectures. If a text passes GPTZero but fails Originality.ai, the humanizer is overfitting to one detector's signal.
4. **Measure burstiness directly as a diagnostic, not an optimization target.** Human texts have burstiness spread of 0.6–1.2; if the humanizer produces burstiness in that range naturally through varied sentence construction and author-appropriate cadence, it is working as intended. If burstiness is high because the humanizer randomly varies sentence length without regard to rhetorical purpose, the text will read as incoherent.
5. **Include genre-appropriate evaluation.** Technical or legal texts naturally have lower burstiness than creative prose. A humanizer must be evaluated against the expected human range for the specific genre, not against universal "human" thresholds.
6. **Implement the "smell test" as a structured qualitative check.** Expert readers should flag: repetitive sentence openers (the hallmark of GPT prose), formulaic transition phrases ("In conclusion," "Moreover," "It is worth noting that"), unnaturally consistent paragraph lengths, and absence of genuine idiosyncrasy.
7. **Build for iterative improvement, not one-shot optimization.** The arms race between detectors and humanizers means evaluation criteria must evolve. Freeze evaluation benchmarks and re-test periodically against updated detector versions. Track both the humanizer's detection-evasion rate and its prose-quality scores over time to detect Goodhart-style divergence.

## 5. Bibliography

Burrows, J. (2002). 'Delta': A measure of stylistic difference and a guide to likely authorship. *Digital Scholarship in the Humanities*, 17(3), 267–287. https://academic.oup.com/dsh/article-abstract/17/3/267/929277

Evert, S., Proisl, T., Jannidis, F., Reger, I., Pielström, S., Schöch, C., & Vitt, T. (2017). Understanding and explaining Delta measures for authorship attribution. *Digital Scholarship in the Humanities*, 32(suppl_2), ii4–ii16. https://doi.org/10.1093/llc/fqx023 (also available: https://zenodo.org/records/18177)

EyeSift. (2026). AI detector accuracy benchmarks 2026: GPTZero vs Turnitin vs Originality vs EyeSift — tested. https://www.eyesift.com/blog/ai-detector-accuracy-benchmarks-2026/

GPTZero. (2025, October 14). What is perplexity & burstiness for AI detection? https://gptzero.me/news/perplexity-and-burstiness-what-is-it/

Hopkins, M. (2026, January 22). AI agents will game any metric you give them: Goodhart's law explained. https://matthopkins.com/business/goodharts-law-ai-agents/

Leap AI. (2026). Perplexity vs burstiness — The two metrics that flag AI text. https://www.tryleap.ai/learn/perplexity-vs-burstiness

Marco, G., Gonzalo, J., & Fresno, V. (2025). The reader is the metric: How textual features and reader profiles explain conflicting evaluations of AI creative writing. *Findings of the Association for Computational Linguistics: ACL 2025*. arXiv:2506.03310. https://arxiv.org/abs/2506.03310

Memon, A. R., et al. (2025). Can we trust academic AI detective? Accuracy and limitations of AI-output detectors. *PMC/Springer Nature*. https://pmc.ncbi.nlm.nih.gov/articles/PMC12331776/

OpenAI. (2022, April 13). Measuring Goodhart's law. https://openai.com/index/measuring-goodharts-law/

O'Sullivan, J. (2025). Stylometric comparisons of human versus AI-generated creative writing. *Humanities and Social Sciences Communications*, 12, Article 5986. https://www.nature.com/articles/s41599-025-05986-3

Rashidi, H. H., et al. (2025). Do humans identify AI-generated text better than machines? Evidence based on excerpts from German theses. *ScienceDirect*. https://www.sciencedirect.com/science/article/pii/S1477388025000131

Unitary. (2023, September 11). Applying Goodhart's law to AI generated content detection: Misuse & innovation. https://www.unitary.ai/articles/applying-goodharts-law-to-ai-generated-content-detection-misuse-innovation

Various Authors. (2024). Human vs. machine: A comparative study on the detection of AI-generated content. *ACM Transactions on Asian and Low-Resource Language Information Processing*. https://dl.acm.org/doi/full/10.1145/3708889

Various Authors. (2025). Understanding reader perception shifts upon disclosure of AI authorship. arXiv:2510.24011. https://arxiv.org/abs/2510.24011

Various Authors. (2025). When metrics go wrong: A tale of Goodhart's law and AI misalignment. https://gpt.gekko.de/goodhart-ai-alignment/

Weber-Wulff, D., Anohina-Naumeca, A., Bjelobaba, S., Foltýnek, T., Guerrero-Dib, J., Popoola, O., et al. (2023). Testing of detection tools for AI-generated text. *International Journal for Educational Integrity*, 19(1), 1–39. https://doi.org/10.1007/s40979-023-00146-z
