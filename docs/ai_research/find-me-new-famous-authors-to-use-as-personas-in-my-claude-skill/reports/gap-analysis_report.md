# Gap Analysis: Humanizer Persona Registry

## 1. Summary

The humanizer skill's 12-persona registry is organized along three axes: **register** (formal, mixed, informal), **purpose** (persuade, explain, narrate, observe, introspect), and **domain** (political/moral, social/cultural, personal/psychological, technical/systems, atmospheric/descriptive). Mapping the 15 register×purpose cells against the current roster reveals **6 uncovered cells** — two-fifths of the matrix is empty. The gaps cluster in the informal and mixed registers, with informal carrying the heaviest burden: only one informal persona (Hemingway) serves a single purpose (narrate), while Thompson's persona file tags him as narrate-only despite the registry's selection reference listing him under persuade as well — an internal inconsistency that, even resolved in his favor, leaves 5 unambiguous gaps.

Domain coverage is similarly lopsided. Political/moral (4 personas) and social/cultural (5) are well-stocked; technical/systems and atmospheric/descriptive have 2–3 personas but concentrated in narrow register bands; personal/psychological has only 2, both in formal register. The registry's primary structural weakness is the **absence of any informal voice that explains, observes, or introspects**, and the **absence of any mixed-register voice that explains or introspects**. These are not marginal edge cases — informal explanation and mixed-register introspection are among the most common human writing scenarios.

This report identifies each uncovered cell, analyzes why existing personas cannot serve it, cross-references domain gaps, and prioritizes the five gaps whose filling would add the most practical value to the skill. The analysis uses the persona files' own tag metadata and the registry's selection reference as authoritative, flagging internal discrepancies where they exist.

## 2. Relation to Primary Question

The primary research question — "What distinctive authorial voices would fill the gaps in the humanizer skill's current 12-persona registry?" — requires first knowing precisely what the gaps are. This report answers the prerequisite: which cells in the 3×5 register×purpose matrix are empty, which domain intersections are thin, and which unfilled positions would most improve the skill's real-world utility. The concrete gap list (Section 4) provides the target map that subsequent research tasks (literary voices, internet-native voices, genre writers, translated voices) will populate with specific author candidates.

## 3. Source Evaluation

The analysis draws on two primary sources within the repository, both treated as authoritative:

- **Persona registry** (`.claude/skills/humanizer/personas/registry.md`): The canonical lookup table mapping each of the 12 personas to register, purpose, and domain. Its "Selection reference" section provides the condensed axis list used for matrix construction.
- **Individual persona files** (`.claude/skills/humanizer/personas/{slug}.md`): Each file's YAML-like frontmatter tags (`register=`, `purpose=`, `domain=`) provide the per-persona ground truth.

**Internal discrepancy noted**: Thompson's persona file (`thompson.md`) tags `purpose=narrate`, but the registry's selection reference lists him under both `narrate → hemingway, mccarthy, thompson` and `persuade → baldwin, orwell, thompson, coates`. The persona file also lists domain as `social/cultural` alone, while the registry reference places Thompson in both `political/moral` and `social/cultural`. This analysis treats the per-file tags as definitive for the matrix, while acknowledging the registry reference's broader assignment in the gap discussion. The net effect is minimal: even crediting Thompson with persuade coverage, the informal register still has 3 uncovered purpose cells.

No external sources were consulted. The analysis is self-contained within the skill's own taxonomy.

## 4. Conclusions

### 4.1 Complete Matrix: Register × Purpose

The 3×5 matrix yields 15 cells. Below, each cell is populated from persona file tags (not registry reference cross-listings). Cells marked **GAP** are unambiguously empty.

| | Persuade | Explain | Narrate | Observe | Introspect |
|---|---|---|---|---|---|
| **Formal** | Coates | Orwell, DFW, Le Guin | **GAP** | Austen, Didion | Woolf |
| **Mixed** | Baldwin | **GAP** | McCarthy | Smith | **GAP** |
| **Informal** | **GAP** [^1] | **GAP** | Hemingway, Thompson | **GAP** | **GAP** |

[^1]: Formal/Persuade previously included Baldwin in the user-provided survey matrix, but Baldwin's persona file tags `register=mixed`. The registry selection reference lists Baldwin under persuade. Coates unambiguously occupies Formal×Persuade. Thompson's persona file tags `purpose=narrate` only; the registry reference additionally lists him under persuade. If that broader assignment is accepted, Informal×Persuade is partially covered by Thompson. This report treats the persona-file tags as the ground truth for the matrix, producing the conservative count above.

**Uncovered cells (6):**

1. **Formal × Narrate** — No formal-register narrator exists. McCarthy and Hemingway are atmospheric narrators at mixed and informal registers, respectively, but neither operates in formal prose. A formal narrator would handle historical narrative, literary fiction in elevated register, or ceremonial storytelling where McCarthy's gravitas is too archaic and Hemingway's minimalism too sparse.

2. **Mixed × Explain** — No mixed-register explainer exists. Orwell (formal) and DFW (formal, recursive) are the only dedicated explainers, with Le Guin adding a systems/technical variant. A mixed-register explainer would bridge the gap between academic precision and general-audience accessibility — the voice of the longform magazine explainer, the accessible nonfiction book, the smart newsletter.

3. **Mixed × Introspect** — No mixed-register introspective voice exists. Woolf owns formal introspection — stream of consciousness, lyrical, immersive. But there is no persona for introspection that keeps one foot in ordinary language: the memoir voice, the personal essay that thinks through feeling without dissolving into it, the writer who examines inner life without Woolf's high-modernist apparatus.

4. **Informal × Explain** — No informal explainer exists. This is arguably the most commonly needed voice in practice: the conversational explainer who makes complex things clear without dumbing them down. Think popular science, how-to essays, accessible tech writing, the kind of explanation that feels like a smart friend walking you through something. Orwell is too formal and didactic; DFW is too recursive and self-conscious.

5. **Informal × Observe** — No informal observer exists. Austen and Didion (formal) and Smith (mixed) cover social observation, but there is no voice for casual, witty, conversational social commentary — the voice of the personal essayist, the diarist, the sharp observer at the party who tells you about it afterward.

6. **Informal × Introspect** — No informal introspection exists. Woolf's introspection is formal, lyrical, often impersonal in its very depth. There is no voice for raw, unliterary self-examination: the confessional voice, the diary entry, the letter that accidentally reveals everything, the kind of introspection that sounds like someone thinking rather than someone Performing Thought.

### 4.2 Domain Coverage Gaps

Analyzing domain × register intersections reveals voice types missing within each domain:

#### Political/Moral (4 personas: Orwell, Baldwin, Coates, Thompson)
- **Well-covered across registers**: Formal (Orwell, Coates), mixed (Baldwin), informal (Thompson, per registry reference).
- **Gap**: No **informal political persuasion** that isn't gonzo fury. Thompson's register is weaponized mania; a calmer, more conversational informal political voice — the op-ed columnist, the accessible moral essayist, the persuasive blogger — does not exist in the registry.

#### Social/Cultural (5 personas: Austen, Didion, Smith, DFW, Thompson)
- **Well-covered in formal and mixed**: Formal (Austen, Didion, DFW), mixed (Smith), informal (Thompson).
- **Gap**: No **informal social observation** that isn't satirical or furious. Thompson observes society through a flamethrower. There is no persona for warm, witty, conversational cultural observation — the voice of Nora Ephron, David Sedaris, or a good culture newsletter.

#### Personal/Psychological (2 personas: Woolf, Didion)
- **Critically thin**: Only 2 personas, both formal.
- **Gaps**: No **mixed-register introspection** (memoir that moves between analytical and emotional registers, e.g., Knausgård or Cusk). No **informal introspection** (raw, conversational self-examination, e.g., Anne Lamott or Cheryl Strayed). This is the most underserved domain relative to its importance — nearly all human writing involves some form of introspection.

#### Technical/Systems (3 personas: Le Guin, Orwell, Hemingway — per registry reference)
- **Adequate in formal** (Le Guin, Orwell) and informal (Hemingway, for technical precision in a stripped-down register).
- **Gap**: No **mixed-register technical/systems voice**. A persona that explains complex systems accessibly, bridges expert and lay audiences, writes the kind of explanation that appears in Wired features, Stratechery, or clear technical documentation for intelligent non-specialists.

#### Atmospheric/Descriptive (2 personas: McCarthy, Hemingway)
- **Only 2 personas**: McCarthy (mixed, grave/archaic) and Hemingway (informal, spare/understated).
- **Gap**: No **formal atmospheric/descriptive voice**. No persona for lyrical, elevated nature writing or landscape description that isn't Hemingway's minimalism or McCarthy's biblical austerity. Think Annie Dillard, Barry Lopez, or W.G. Sebald — formal descriptive prose that treats the physical world with intellectual and aesthetic seriousness.

### 4.3 Prioritized Gap List (Top 5)

These five gaps are selected for **practical value to the skill**: how often users would need this voice, how poorly existing personas cover the need, and how much the voice would expand the skill's range.

#### Priority 1: Informal × Explain
**Why first**: The single most common humanization scenario is making AI-generated explanatory text sound human. Think blog posts, newsletter explanations, how-to content, accessible nonfiction. Formal explainers (Orwell, DFW) often sound too stiff or academic for general-audience content. An informal explainer would cover popular science, tech blogging, accessible journalism, and everyday instructional writing — the bread-and-butter of content that needs humanizing.
**What it needs**: Conversational clarity. The ability to use accessible language, humor, and personal anecdote without losing precision. A voice that feels like a smart, generous person explaining something they genuinely want you to understand.
**Kind of writer**: Mary Roach, Stephen Jay Gould, Carl Sagan, Terry Pratchett (explanatory comedy), Randall Munroe, Bill Bryson.

#### Priority 2: Informal × Introspect
**Why second**: Woolf is the only introspective persona, and her formal, high-modernist register makes her unusable for most practical introspection tasks. A huge volume of human writing is personal and introspective — personal essays, memoir fragments, newsletter reflections, journal entries. There is currently no persona for this at a conversational register.
**What it needs**: Raw, unperformed self-examination. The ability to think on the page without preening. Vulnerability that feels earned, not performed. A voice that can say "I don't know" without it sounding like a rhetorical device.
**Kind of writer**: Anne Lamott, Cheryl Strayed, Mary Karr, Sylvia Plath (prose, not poetry), Leslie Jamison.

#### Priority 3: Mixed × Introspect
**Why third**: Bridges Woolf's formal introspection and the proposed informal confessional voice. This is the voice of the literary memoir, the personal essay with intellectual weight, the writer who moves between emotional rawness and analytical distance within a single paragraph. Extremely common in contemporary nonfiction — Knausgård's "My Struggle," Maggie Nelson's "The Argonauts," Rachel Cusk's "Outline" trilogy all operate in this register.
**What it needs**: The ability to toggle between immersion in feeling and stepping back to analyze that feeling. Metaphor and intellectual scaffolding alongside unvarnished confession. A voice that treats the self as both subject and specimen.
**Kind of writer**: Karl Ove Knausgård, Rachel Cusk, Maggie Nelson, Elena Ferrante, W.G. Sebald, Meghan Daum.

#### Priority 4: Formal × Narrate
**Why fourth**: The registry has no formal narrator at all, yet narrative is a primary purpose shared by fiction, literary journalism, and longform nonfiction storytelling. McCarthy's mixed-register narration is too archaic for many subjects; Hemingway's informal narration is too sparse for stories that require emotional explicitness or complex interiority. A formal narrator would handle narrative history, literary fiction in elevated register, and storytelling that needs gravitas without biblical weight.
**What it needs**: Controlled, elegant narrative prose. The ability to sustain a story over distance without the minimalism of Hemingway or the King James cadence of McCarthy. A voice that can move between scene, summary, and reflection without losing narrative momentum.
**Kind of writer**: Vladimir Nabokov, Toni Morrison, F. Scott Fitzgerald, Edith Wharton, Gabriel García Márquez, Jhumpa Lahiri.

#### Priority 5: Informal × Observe
**Why fifth**: Social observation is well-covered in formal (Austen, Didion) and mixed (Smith) registers, but there is no casual, conversational observer. This is the voice of the personal essayist observing daily life, the culture writer with a Substack, the sharp-eyed diarist. The absence forces users to either elevate their register (using Smith or Didion for content that should feel casual) or abandon observation as a purpose for informal writing entirely.
**What it needs**: Wit, warmth, precision. The ability to notice what others overlook and describe it in language that feels offhand but lands precisely. A voice that is funny without being cruel, observant without being clinical.
**Kind of writer**: Nora Ephron, David Sedaris, Samantha Irby, Jia Tolentino, Fran Lebowitz, E.B. White.

### 4.4 Gap Summary Table

| Priority | Gap Cell | Domain Intersections | Estimated Practical Demand |
|---|---|---|---|
| 1 | Informal × Explain | Technical/systems (mixed register gap) | Very high — explanatory content is the #1 humanization use case |
| 2 | Informal × Introspect | Personal/psychological (informal gap) | High — personal/introspective content is extremely common |
| 3 | Mixed × Introspect | Personal/psychological (mixed gap) | High — literary memoir and personal essay |
| 4 | Formal × Narrate | Atmospheric/descriptive (formal gap) | Moderate — narrative-specific, but sole formal narrator |
| 5 | Informal × Observe | Social/cultural (informal, non-satirical gap) | Moderate — distinctive voice type, common in personal essays |

### 4.5 Deferred Gaps

**Mixed × Explain** (deferred from priority consideration): While genuinely uncovered — there's no mixed-register explainer — this gap would often be filled by either Informal × Explain (Priority 1) for more accessible content, or by the existing formal explainers (Orwell, DFW, Le Guin) for more demanding material. A dedicated mixed-register explainer would be useful but is less urgently needed than the five prioritized gaps above, because the explain purpose already has four personas across two registers, while introspect has only one persona total.

**Registry clarification needed**: The Thompson persona should be reconciled. If his purpose tag is expanded to `purpose=narrate+persuade` (matching the registry reference), and his domain tag to `domain=social/cultural+political/moral`, the matrix becomes slightly more populated without adding any personas. This would mean Informal × Persuade is covered by Thompson, reducing the total gap count from 6 to 5 cells.

## 5. Bibliography

Primary sources:
- `.claude/skills/humanizer/personas/registry.md` — Persona lookup table with register, purpose, and domain assignments; selection reference with axis lists.
- `.claude/skills/humanizer/personas/{slug}.md` — Individual persona profiles for all 12 personas: `austen.md`, `baldwin.md`, `coates.md`, `dfw.md`, `didion.md`, `hemingway.md`, `leguin.md`, `mccarthy.md`, `orwell.md`, `smith.md`, `thompson.md`, `woolf.md`. Each contains frontmatter tags (`register=`, `purpose=`, `domain=`), style profile, 10 exemplars, negative constraints, and failure-mode guidance.
- `.claude/skills/humanizer/SKILL.md` — Skill specification describing the persona selection algorithm (register match, purpose diversity, domain fit).

No external sources cited. All analysis derived from the registry's internal taxonomy.
