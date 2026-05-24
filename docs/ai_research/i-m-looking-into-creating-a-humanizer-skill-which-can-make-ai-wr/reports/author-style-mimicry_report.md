# Author Style Mimicry Techniques — Research Report

## 1. Summary

Computational stylometry provides a rigorous, quantitative framework for distinguishing authors by measuring linguistic features such as function-word frequency distributions, sentence-length variability, punctuation habits, and syntactic patterns. Burrows' Delta, the foundational method, operates on the most frequent words (typically function words) in a text corpus, computing z-score-normalized distances between texts. Because function words like prepositions, determiners, and conjunctions are produced largely subconsciously and are resistant to intentional manipulation, they form a reliable "authorial fingerprint." Research consistently demonstrates that these fingerprints are robust enough to achieve authorship attribution accuracy above 90% with sufficient text samples, and they remain effective at distinguishing AI-generated text from human writing even as language models become more sophisticated (O'Sullivan, 2025).

For NLP-based style transfer, the research literature identifies three principal approaches. **Fine-tuning** on author corpora yields the strongest results—a 2025 study found that AI models fine-tuned on as few as two books can generate prose that readers prefer over work by professional imitators. However, fine-tuning requires substantial computational resources and curated datasets, making it impractical for real-time or ad-hoc use. **Few-shot prompting** provides a more accessible alternative: providing 2–5 writing samples in a prompt allows LLMs to approximate author style through in-context learning. Research published in 2025–2026 demonstrates that few-shot prompting yields up to 23.5× higher style fidelity compared to zero-shot approaches, and that prompting strategy exerts more influence on style fidelity than model size alone (Wang et al., 2025; Jemama & Kumar, 2025). **Constrained decoding** and linguistically informed prompting—where models are explicitly instructed to attend to features like punctuation patterns, phrasal verb usage, and rare-word frequency—represent a third approach, though results from the 2026 PAN workshop suggest its benefits over simpler prompting strategies are modest.

Analysis of specific author style profiles reveals distinct, computationally tractable signatures. **Ernest Hemingway** is characterized by extremely low Flesch-Kincaid scores (3.9 for *The Old Man and the Sea*), heavy use of parataxis and asyndeton (clauses placed side by side without subordinating conjunctions), adverb avoidance (only 80 -ly adverbs per 10,000 words), and a rhythm built on short declarative sentences connected by "and." **Jane Austen** pioneered free indirect discourse (FID)—a narrative technique blending third-person narration with a character's consciousness—which, though notoriously difficult to detect computationally because it lacks grammatical markers, is identifiable through co-occurrence patterns of modal verbs, cognitive verbs, and high-degree words. **Cormac McCarthy** employs an extreme minimalist punctuation regime (periods, capitals, occasional commas—no semicolons, no quotation marks), long polysyndetic sentences linked by "and" that borrow biblical cadence, and deliberate juxtaposition of sparse minimalist prose against passages of sublime, almost liturgical language.

The critical distinction between effective style mimicry and superficial pastiche lies in the difference between surface features and deep structure. Surface features—word choice, sentence length, punctuation patterns—are statistically tractable and relatively easy for LLMs to approximate. Deep structure—the intentional purpose behind stylistic choices, the cultural and psychological context that informs an author's voice, and the coherent worldview that makes a style feel authentic rather than decorative—remains largely beyond the reach of current systems. A March 2026 study in *Digital Scholarship in the Humanities* confirmed that "while GPT-4o captures some surface-level stylistic elements of the authors, it struggles to fully replicate the depth and uniqueness of stylometric signatures." The findings from the PAN 2026 adversarial evaluation corroborate this: LLM-generated impersonation texts failed to bypass any of six established authorship verification methods across three genres (email, SMS, social media), and neural AV methods like STAR and LUAR actually rejected LLM impersonations with *higher* confidence than genuine human negative samples—likely because LLM outputs exhibit elevated lexical diversity and entropy relative to authentic human writing.

## 2. Relation to Primary Question

Author style mimicry techniques directly address the core humanizer problem: rather than using generic "de-AI-ification" tricks (synonym swapping, sentence-length randomization, perplexity manipulation) that produce unnatural text, adopting a specific author's stylistic signature provides a coherent, defensible target for rewriting—one that embodies authentic human cadence, tone, and naturalness because it is derived from actual human literary practice rather than from the negative goal of "not sounding like AI."

## 3. Source Evaluation

### Primary Academic Sources

**O'Sullivan, J. (2025). "Stylometric comparisons of human versus AI-generated creative writing." *Humanities and Social Sciences Communications*, Nature.**
https://www.nature.com/articles/s41599-025-05986-3
- **Assessment:** Primary source, peer-reviewed journal article in a Nature portfolio journal. Verifiable author (James O'Sullivan, University College Cork), published 2025. Uses the publicly available Beguš corpus and open-source Python scripts, enabling full reproducibility.
- **Weight:** High. This is the most directly relevant source—a quantitative, replicable study applying Burrows' Delta to compare human and AI-generated creative texts. The author explicitly limits claims to the corpus studied and cautions against overinterpretation. The methodology (hierarchical clustering + MDS on 100 most frequent words) is standard best practice in computational stylometry.

**Nini, A. et al. — "Authorship Impersonation via LLM Prompting does not Evade Authorship Verification Methods." arXiv:2603.29454, March 2026.**
https://arxiv.org/html/2603.29454v1
- **Assessment:** Primary source, preprint (not yet peer-reviewed at time of access). Multiple verified academic authors. Published March 2026—highly current. Evaluates six AV methods (three non-neural, three neural) against GPT-4o impersonation attempts across three genres using a likelihood-ratio forensic framework.
- **Weight:** High-medium. The forensic evaluation framework is rigorous and the dataset is well-documented. Weighted slightly below the Nature article because it is a preprint. The finding that LLM impersonations are *more* detectable than random human negatives is especially significant and counterintuitive—it warrants independent replication but is well-supported by the lexical diversity analysis in Section V-B.

**Wang, Z. et al. (2025). "Catch Me If You Can? Not Yet: LLMs Still Struggle to Imitate the Implicit Writing Styles of Everyday Authors." Findings of EMNLP 2025.**
https://arxiv.org/html/2509.14543v1
- **Assessment:** Primary source, peer-reviewed (accepted to Findings of EMNLP 2025). Multiple verified academic authors from Stony Brook University and Penn State. Comprehensive evaluation spanning 40,000+ generations across four domains, 400+ authors, and five LLM families.
- **Weight:** High. This is the most thorough evaluation of few-shot style imitation for everyday (non-famous) authors. Its four-metric evaluation framework (AA, AV, stylometric modeling, AI detection) provides a template for rigorous humanizer assessment. The finding that increasing demonstration count beyond 5 yields negligible improvement is directly actionable.

**Burrows, J. (2002). "Delta: a measure of stylistic difference and a guide to likely authorship." *Literary and Linguistic Computing*, 17(3), 267–287.**
- **Assessment:** Primary source, peer-reviewed, foundational paper in computational stylometry. Verified author (John Burrows, University of Newcastle, Australia). Seminal work cited by virtually all subsequent stylometry research.
- **Weight:** High for methodology. This is the paper that introduced Burrows' Delta and established function-word frequency analysis as the gold standard. Though published in 2002, the method remains current and was used by O'Sullivan (2025) and the PAN 2026 workshop. Its age does not diminish its relevance—it is foundational infrastructure.

### Secondary and Supplementary Sources

**The Decoder (2025). "AI models can mimic famous authors' writing styles using just two books for training."**
https://the-decoder.com/ai-models-can-mimic-famous-authors-writing-styles-using-just-two-books-for-training/
- **Assessment:** Secondary source, tech journalism. Reports on a research study but does not provide the primary paper. The headline claim is attention-grabbing but the article references a legitimate study.
- **Weight:** Low-medium. Useful as a pointer to research but not as evidence itself. The specific claim about "two books" should be verified against the primary study, which was not directly accessed.

**BookAnalysis.com (2024). "Understanding Ernest Hemingway's Incredible Writing Style."**
https://bookanalysis.com/ernest-hemingway/writing-style/
- **Assessment:** Secondary source, literary analysis blog. Author unverified, though the site appears to be an established literary reference. Content is well-sourced with specific examples from Hemingway's work and references to scholarly analysis.
- **Weight:** Medium. The specific stylistic claims (Flesch-Kincaid scores, adverb counts, parataxis definition) are independently verifiable and consistent across multiple sources. However, as a non-scholarly source, it is used here for descriptive literary analysis rather than as research evidence.

**EnchantingMarketing.com (2023). "How to Write Like Hemingway (With Examples of his Writing Style)."**
https://www.enchantingmarketing.com/write-like-hemingway/
- **Assessment:** Secondary source, writing advice blog. Cites specific data from Ben Blatt's *Nabokov's Favorite Word Is Mauve* (a statistically rigorous analysis of literary style).
- **Weight:** Medium. The referenced statistics (80 -ly adverbs per 10,000 words; Flesch-Kincaid scores) trace to Blatt's published book, which performed systematic quantitative analysis. The blog's interpretive framing is opinion, but the data points are well-sourced.

**Open Culture (2013/updated). "The Three Punctuation Rules of Cormac McCarthy (RIP), and How They All Go Back to James Joyce."**
https://www.openculture.com/2013/08/cormac-mccarthys-punctuation-rules.html
- **Assessment:** Secondary source, cultural blog. Draws on McCarthy's own words from a rare interview (Oprah Winfrey show) and published commentary.
- **Weight:** Medium. McCarthy's punctuation rules are direct quotes from the author himself, making this section primary-source quality. The James Joyce connection is interpretive but widely accepted in literary scholarship.

**JASNA (Jane Austen Society of North America). "Discerning Voice through Austen Said: Free Indirect Discourse, Coding, and Interpretive (Un)Certainty."**
https://jasna.org/publications-2/persuasions-online/vol37no1/white-smith/
- **Assessment:** Secondary source, published by a reputable scholarly society. Describes the Austen Said project at the University of Nebraska-Lincoln, which computationally tagged every word in Austen's novels by speaker/narrator.
- **Weight:** Medium-high. The JASNA is a credible scholarly organization. The Austen Said project is a legitimate computational humanities initiative. The article is descriptive rather than presenting new experimental results, but its claims about FID's computational elusiveness are well-grounded.

**Medium / AI Natural Write / various humanizer tool reviews (2026).**
- **Assessment:** Commercial and promotional content. These sources review products they may have affiliate relationships with. Claims about bypass rates are not independently verified.
- **Weight:** Low. Included only to document the landscape of existing humanizer tools, not as evidence for their efficacy. Bypass-rate claims (97%, 94%) are manufacturer claims and should be treated as marketing, not fact.

**The Algorithmic Bridge (2026). "10 Signs of AI Writing That 99% of People Miss."**
https://www.thealgorithmicbridge.com/p/10-signs-of-ai-writing-that-99-of
- **Assessment:** Secondary source, Substack newsletter. Author identified but not academically credentialed in NLP. Observations about AI writing patterns ("structural seesaw," hedging) are interpretive rather than experimentally validated.
- **Weight:** Low-medium. The specific claims about AI writing patterns are astute and align with stylometric findings, but the source lacks rigorous methodology. Useful as a practitioner observation, not as research evidence.

## 4. Conclusions

### 4.1 A Multi-Persona Architecture Is the Most Promising Approach

The user's intuition—using multiple subagents each embodying a different author persona, then synthesizing—has strong research support. The key insight from the stylometry literature is that human writing achieves its natural quality through *variability*: O'Sullivan (2025) found that human-authored texts formed "broader and less compact clusters" compared to the "tight, uniform clusters" of AI-generated texts. A single author persona (even a well-executed one) risks reproducing the uniformity that makes AI text detectable. Multiple personas introduce the stylistic diversity that characterizes authentic human writing. The architecture should be: (a) decompose the input into semantic units; (b) assign each unit to a persona whose style suits its rhetorical function; (c) generate each unit with that persona's stylistic constraints; (d) blend at the seams to avoid jarring transitions.

### 4.2 Target Deep Structure, Not Surface Features

The most actionable finding from the 2025–2026 research is that the gap between effective mimicry and pastiche is the gap between surface features and deep structure. A humanizer that merely adjusts sentence length, swaps synonyms, or randomizes punctuation will produce text that is superficially varied but structurally hollow. Effective author style mimicry must target: (a) **coherence of worldview**—the text should feel as though it emerges from a consistent perspective, not a statistical collage; (b) **rhetorical intentionality**—stylistic choices should serve communicative purposes (Hemingway's short sentences create tension; Austen's FID creates ironic distance); (c) **variability within constraints**—real authors are not perfectly consistent; they vary sentence length, register, and rhythm based on context.

### 4.3 Specific Actionable Style Profiles

Based on the research, the following author profiles are computationally tractable and stylistically distinctive enough to serve as effective personas:

- **Hemingway:** Target Flesch-Kincaid 3.5–5.0; cap -ly adverbs at <100 per 10,000 words; enforce paratactic structure (≤1 subordinating conjunction per 5 clauses); use "and"-chaining for compound sentences; no semicolons; dialogue attribution via context rather than "he said"/"she said."
- **Austen:** Deploy free indirect discourse (blend narrator voice with character consciousness); use modal verbs (could, must, would) co-occurring with cognitive/evaluative verbs; maintain ironic distance between narrator and character; periodic sentences with balanced clauses.
- **McCarthy:** No quotation marks, no semicolons; minimal commas; polysyndetic long sentences for atmospheric passages; short declarative sentences for action/impact; archaic or biblical diction mixed with plain speech; deliberate tonal juxtaposition.

### 4.4 Few-Shot Prompting Is the Pragmatic Choice

Fine-tuning produces better results but is impractical for a general-purpose humanizer that must adapt to arbitrary input text and target styles. The Wang et al. (2025) findings are decisive: few-shot prompting with 5 examples achieves most of the available gain; more than 8 examples yields diminishing returns; prompting strategy matters more than model size. The practical implementation should: (a) maintain a library of exemplar passages for each persona (5–8 passages of 150–500 words each); (b) prepend the relevant exemplars to the generation prompt; (c) include explicit stylistic instructions derived from the computational profile (e.g., "Your average sentence length should be 12–15 words; do not use -ly adverbs; connect clauses with 'and' rather than subordinating conjunctions").

### 4.5 Verification Framework

Any humanizer built on these techniques should incorporate the evaluation framework from Wang et al. (2025): (a) authorship attribution—can a fine-tuned classifier attribute the output to the target author? (b) authorship verification—can an AV system distinguish the output from ground-truth author text? (c) stylometric distance—does the output's Mahalanobis distance to the target author's style model decrease relative to a generic baseline? (d) AI detection—do standard detectors (GPTZero, Turnitin) classify the output as human? This four-metric framework provides objective, falsifiable criteria for humanizer quality.

### 4.6 Known Limitations

Current LLMs struggle most with informal, stylistically diverse domains (blogs, forums, social media) and perform best on structured formats (news, email). The PAN 2026 results indicate that neural AV methods are actually *more* confident rejecting LLM impersonations than random human negatives, suggesting a fundamental limitation: LLM outputs exhibit elevated lexical diversity and entropy that betray their synthetic origin even when surface features are well-matched. This means the humanizer should not aim to "fool" forensic AV systems—an unrealistic goal given current technology—but rather to produce text that reads naturally to human audiences and avoids the obvious tells of generic AI prose.

## 5. Bibliography

Argamon, S. (2008). Interpreting Burrows's Delta: Geometric and probabilistic foundations. *Literary and Linguistic Computing*, 23(2), 131–147. https://doi.org/10.1093/llc/fqn003

Beguš, N. (2024). Experimental narratives: A comparison of human crowdsourced storytelling and AI storytelling. *Humanities and Social Sciences Communications*, 11(1), 1–22. https://doi.org/10.1057/s41599-024-03868-8

Burrows, J. (2002). Delta: A measure of stylistic difference and a guide to likely authorship. *Literary and Linguistic Computing*, 17(3), 267–287. https://doi.org/10.1093/llc/17.3.267

Draftly. (2025). How to write like Cormac McCarthy. https://joindraftly.com/en/authors/cormac-mccarthy

Enchanting Marketing. (2023). How to write like Hemingway (with examples of his writing style). https://www.enchantingmarketing.com/write-like-hemingway/

Evert, S., Proisl, T., Jannidis, F., Reger, I., Pielström, S., Schöch, C., & Vitt, T. (2017). Understanding and explaining delta measures for authorship attribution. *Digital Scholarship in the Humanities*, 32(suppl_2), ii4–ii16. https://doi.org/10.1093/llc/fqx023

JASNA (Jane Austen Society of North America). (2016). Discerning voice through Austen Said: Free indirect discourse, coding, and interpretive (un)certainty. *Persuasions On-Line*, 37(1). https://jasna.org/publications-2/persuasions-online/vol37no1/white-smith/

Jemama, L., & Kumar, R. (2025). How well do LLMs imitate human writing style? arXiv:2509.24930. https://arxiv.org/abs/2509.24930

Jordan, P. (n.d.). Hemingway and parataxis. *TSS Publishing*. https://theshortstory.co.uk/hemingway-and-parataxis-by-peter-jordan/

Liu, X. (2020). Free indirect speech in Northanger Abbey. *Theory and Practice in Language Studies*, 10(4). https://www.academypublication.com/issues2/tpls/vol10/04/10.pdf

Mikros, G. (2025). Beyond the surface: Stylometric analysis of GPT-4o's capacity for literary style imitation. *Digital Scholarship in the Humanities*, 40(2), 587. https://academic.oup.com/dsh/article/40/2/587/8118784

Miller, E. (2018). Austenesque: A study of free indirect speech in Jane Austen. *Medium*. https://medium.com/@emiller20/austenesque-b7835fdd38ac

Neal, T., Sundararajan, K., Fatima, A., Yan, Y., Xiang, Y., & Woodard, D. (2017). Surveying stylometry techniques and applications. *ACM Computing Surveys*, 50(6), 86:1–86:36. https://doi.org/10.1145/3132039

Nini, A., et al. (2026). Authorship impersonation via LLM prompting does not evade authorship verification methods. arXiv:2603.29454. https://arxiv.org/html/2603.29454v1

Nini, A., et al. (2015). Grammar as a behavioral biometric: Using cognitively motivated grammar models for authorship verification. https://doi.org/10.1016/j.csl.2015.06.002

NOTIONES. (2023). Stylometric analysis and machine learning: A winning couple for authorship identification. https://www.notiones.eu/2023/01/11/stylometric-analysis-and-machine-learning-a-winning-couple-for-authorship-identification/

Open Culture. (2013). The three punctuation rules of Cormac McCarthy (RIP), and how they all go back to James Joyce. https://www.openculture.com/2013/08/cormac-mccarthys-punctuation-rules.html

O'Sullivan, J. (2025). Stylometric comparisons of human versus AI-generated creative writing. *Humanities and Social Sciences Communications*, Nature. https://www.nature.com/articles/s41599-025-05986-3

Przystalski, K., Argasiński, J., Grabska-Gradzińska, I., & Ochab, J. (2024). Stylometry recognizes human and LLM-generated texts in short samples. SSRN. https://doi.org/10.2139/ssrn.4950812

Savoy, J. (2020). *Machine learning methods for stylometry: Authorship attribution and author profiling*. Springer Nature. https://doi.org/10.1007/978-3-030-53360-1

The Algorithmic Bridge. (2026). 10 signs of AI writing that 99% of people miss. https://www.thealgorithmicbridge.com/p/10-signs-of-ai-writing-that-99-of

The Decoder. (2025). AI models can mimic famous authors' writing styles using just two books for training. https://the-decoder.com/ai-models-can-mimic-famous-authors-writing-styles-using-just-two-books-for-training/

The Hemingway Society. (n.d.). A quantitative guide to Hemingway's style. https://www.hemingwaysociety.org/quantitative-guide-hemingways-style

The Reply Hub. (2025). Why Cormac McCarthy's style endures: 7 secrets for your writing. https://thereplyhub.blog/cormac-mccarthy-style-endures-7-secrets-writing

Toshevska, M., & Gievska, S. (2025). LLM-based text style transfer: Have we taken a step forward? *Natural Language Engineering*. https://www.cambridge.org/core/journals/natural-language-engineering/article/from-theories-on-styles-to-their-transfer-in-text-bridging-the-gap-with-a-hierarchical-survey/C2C386DEEB83B6281280ACD899AA1A3F

VastlyWise. (2026). AI-based writing style mimicry for emulating famous authors. https://vastlywise.com/ai-blog/ai-writing-style-mimicry

Wang, Z., Tripto, N. I., Park, S., Li, Z., & Zhou, J. (2025). Catch me if you can? Not yet: LLMs still struggle to imitate the implicit writing styles of everyday authors. *Findings of EMNLP 2025*. arXiv:2509.14543. https://arxiv.org/html/2509.14543v1

Wikipedia contributors. (2026). Stylometry. *Wikipedia, The Free Encyclopedia*. https://en.wikipedia.org/wiki/Stylometry

Zaitsu, W., & Jin, M. (2023). Distinguishing ChatGPT(-3.5, -4)-generated and human-written papers through Japanese stylometric analysis. *PLoS ONE*, 18(8), e0288453. https://doi.org/10.1371/journal.pone.0288453
