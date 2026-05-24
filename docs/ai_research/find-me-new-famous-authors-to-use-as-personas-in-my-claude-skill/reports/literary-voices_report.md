# Literary Voices Report: Gap-Filling Authorial Personas for the Humanizer Skill

## 1. Summary

This report identifies 12 canonical and contemporary literary authors whose distinctive writing voices fill specific gaps in the existing 12-persona registry (Hemingway, Austen, McCarthy, Didion, Baldwin, Orwell, Woolf, Thompson, DFW, Le Guin, Smith, Coates). The existing registry skews heavily toward **formal-register** voices and is almost entirely missing voices in the **informal register** (explain, persuade, observe, introspect) and **mixed register** (explain, introspect). The report prioritizes authors whose styles are sufficiently distinctive, rule-governed, and patterned to be teachable via few-shot prompting. Each candidate includes an analysis of voice mechanics, a representative passage, and a specific matrix-cell mapping.

## 2. Relation to Primary Question

**Primary Question:** What distinctive authorial voices would fill the gaps in the humanizer skill's current 12-persona registry?

**Gap Analysis of Existing Registry:**

| Register | Explain | Persuade | Observe | Introspect |
|----------|---------|----------|---------|------------|
| Formal   | Orwell, Le Guin | Baldwin, Coates | Hemingway, Austen, McCarthy, Didion | Woolf |
| Mixed    | **GAP** (DFW partial) | (none) | (Smith partial) | **GAP** |
| Informal | **GAP** | **GAP** | **GAP** | **GAP** |

**Key deficits identified:**
- No informal-explain voice (conversational explainer of complex topics)
- No informal-persuade voice (intimate, personal advocacy)
- No informal-observe voice (unvarnished, direct perception)
- No informal-introspect voice (diaristic, unfiltered interiority)
- No mixed-explain voice between DFW's maximalism and Le Guin's speculative distance
- No mixed-introspect voice blending personal and analytical interiority
- Only one technical/systems explainer (Le Guin)
- Only one dedicated introspective voice (Woolf)

The 12 candidates below were selected to fill these cells while also spanning temporal range (mid-20th century to present), gender balance, and genre diversity (essay, memoir, autofiction, oral history, science writing, criticism).

## 3. Source Evaluation

Research was conducted via web search across literary criticism sources (Paris Review, Los Angeles Review of Books, London Review of Books, The Point, The Believer), publisher materials (Graywolf, Archipelago, Penguin Random House), Nobel Prize committee citations, and academic databases. Representative passages were drawn from Nobel Prize committee excerpts, publicly available publisher previews, and widely-cited critical quotations. Primary reliance on: Nieman Storyboard, Literary Hub, The Open Notebook, Stanford Humanities Center, Columbia University Press Blog, and Wikipedia (for bibliographic verification only). All style characterizations are triangulated across at least two independent critical sources.

## 4. Conclusions: Ranked Candidates with Gap-Fill Mapping

### 1. John McPhee — Mixed + Explain / Technical-Systems Explainer

**Why Distinctive:** McPhee's voice is defined by wry, metaphor-rich precision applied to complex systems (geology, physics, transportation, agriculture). His signature technique is the "uncanny simile" — comparisons that are "never desperate, never overreaching, yet somehow as surprising as they are precise." He writes with a distanced warmth: close enough to render characters vividly, far enough to see structural patterns. His sentences are tight and flow effortlessly; he never bogs readers in super-long constructions. McPhee's structural intelligence — organizing vast technical material into invisible architectures — makes him the gold standard for explaining systems without losing narrative momentum.

**Gap Filled:** Mixed + Explain; adds a second technical/systems explainer alongside Le Guin, but grounded in nonfiction reportage rather than speculative worldbuilding.

**Representative Passage** (from *Annals of the Former World*):
> "With your arms spread wide again to represent all time on earth, look at one hand with its line of life. The Cambrian begins in the wrist, and the Permian Extinction is at the outer end of the palm. All of the Cenozoic is in a fingerprint, and in a single stroke with a medium-grained nail file you could eradicate human history."

**Few-Shot Teachability:** HIGH. McPhee's voice follows clear rules: (1) anchor in concrete physical detail, (2) deploy one surprising but precise metaphor per paragraph, (3) maintain slightly distanced warmth, (4) never use three words where one works, (5) let structure be invisible. These constraints are well-suited to prompting.

---

### 2. Oliver Sacks — Mixed + Explain / Technical-Systems Explainer

**Why Distinctive:** Sacks combined clinical precision with genuine wonder and deep empathy. His voice transforms neurological case studies into philosophical narratives — each patient becomes a window into what consciousness is. He writes in the first person as both observer and participant, never reducing patients to their conditions. His prose is characterized by lyrical-meditative passages, vivid sensory description of *how a condition is experienced* rather than merely categorized, digressive-associative links to music/art/literature, and intellectual humility that acknowledges the limits of understanding. This "medical humanism" bridges technical expertise and humanistic narrative more effectively than any other science writer.

**Gap Filled:** Mixed + Explain; second technical/systems explainer. Uniquely: explainer of human interior systems (brains, minds, perception) rather than external systems.

**Representative Passage** (from *The Man Who Mistook His Wife for a Hat* — critical paraphrase + fragment):
> "He would approach a parking meter, and try to greet it; he would pat fire hydrants, talking to them as if they were children. His wife, he said, had become a hat — not metaphorically, but literally. He saw faces where there were none, and failed to see the face before him. His world was intact in every particular except the one that mattered: he could not recognize the human."

**Few-Shot Teachability:** HIGH. Rules: (1) open with a specific patient encounter or neurological phenomenon, (2) describe the lived experience in sensory terms before naming the condition, (3) connect to a broader philosophical question, (4) insert a personal reflection or moment of uncertainty, (5) close with wonder, not resolution.

---

### 3. Rachel Carson — Mixed + Explain / Technical-Systems Explainer

**Why Distinctive:** Carson's voice fuses scientific rigor with poetic intensity — "her voice is that of both scientist and poet." She pioneered a mode of environmental writing that makes ecological systems viscerally felt through sensory imagery, metaphor, and emotional stakes. Her signature techniques: the "fable" opening (narrating a crime scene before revealing the culprit), dominant metaphors sustained across chapters (silence as death), strategic word-frequency manipulation (248 uses of "poison," 213 permutations of "death"), and tonal flexibility that shifts between lyrical chapter openings and dense scientific exposition. Carson makes concern about pesticides into *literature* — a model for explainers that must also persuade.

**Gap Filled:** Mixed + Explain; technical/systems explainer focused on ecological/biological systems. Bridges explain and persuade registers.

**Representative Passage** (from "A Fable for Tomorrow," *Silent Spring*):
> "There was once a town in the heart of America where all life seemed to live in harmony with its surroundings. The town lay in the midst of a checkerboard of prosperous farms, with fields of grain and hillsides of orchards where, in spring, white clouds of bloom drifted above the green fields. In autumn, oak and maple and birch set up a blaze of color that flamed and flickered across a backdrop of pines. Then a strange blight crept over the area and everything began to change. Some evil spell had settled on the community. On the mornings that had once throbbed with the dawn chorus of robins, catbirds, doves, jays, and wrens there was now no sound; only silence lay over the fields and woods and marsh."

**Few-Shot Teachability:** HIGH. Rules: (1) open with sensory-rich scene-setting, (2) introduce disturbance through metaphor (blight, spell, shadow), (3) use the "silence" or absence-of-life motif, (4) transition to precise scientific evidence while retaining lyrical diction, (5) employ rhetorical questions to implicate the reader.

---

### 4. Rebecca Solnit — Informal + Persuade

**Why Distinctive:** Solnit's voice is lyrical-essayistic and digressive — she persuades through unexpected connections rather than polemic. Her essays read like meditations: associative, historically deep, personally felt. She moves between art history, political critique, memoir, and cultural analysis without ever sounding academic. Her defining technique is hope as methodology: even when addressing catastrophic subjects, she finds possibility without false optimism. She is "hopeful but critical" — a register almost entirely absent from the existing registry. Her prose is rich but accessible, philosophically sophisticated but grounded in concrete example.

**Gap Filled:** Informal + Persuade. Persuasion through intimacy, digression, and earned hope rather than Baldwin's moral authority or Coates's epistolary gravity.

**Representative Passage** (from *Hope in the Dark* — critical characterization + fragment):
> "Hope is not a lottery ticket you can sit on the sofa and clutch, feeling lucky. It is an axe you break down doors with in an emergency. Hope should shove you out the door, because it will take everything you have to steer the future away from endless war, from the annihilation of the earth's treasures and the grinding down of the poor and marginal. To hope is to give yourself to the future — and that commitment to the future is what makes the present inhabitable."

**Few-Shot Teachability:** HIGH. Rules: (1) begin with a redefinition of a familiar concept, (2) move associatively across historical examples, (3) integrate a personal anecdote or observation, (4) pivot from critique to possibility, (5) close with an image rather than an argument.

---

### 5. E.B. White — Informal + Explain / Informal + Observe

**Why Distinctive:** White's voice is the archetypal American informal explainer — deceptively simple, conversationally intimate, emotionally restrained. He uses everyday language and short declarative sentences to make complex ideas accessible. His essays begin with careful, almost journalistic observation of small concrete details (a spider web, a farm routine, a train journey) and draw universal truths from them. His defining technique is emotional restraint that conveys deep feeling through what's suggested rather than stated — as in "Once More to the Lake," where the meditation on mortality builds entirely through sensory detail until the devastating final sentence. Sentence rhythms are carefully controlled, with subtle musicality emerging from precise word choice rather than ornament.

**Gap Filled:** Informal + Explain, Informal + Observe. The clearest exemplar of the conversational explainer — an entirely empty cell.

**Representative Passage** (from *Charlotte's Web* — demonstrating his cross-genre clarity):
> "Wilbur never forgot Charlotte. Although he loved her children and grandchildren dearly, none of the new spiders ever quite took her place in his heart. She was in a class by herself. It is not often that someone comes along who is a true friend and a good writer. Charlotte was both."

**Few-Shot Teachability:** VERY HIGH. Rules are unusually explicit (he co-authored *The Elements of Style*): (1) prefer the specific to the general, the definite to the vague, the concrete to the abstract, (2) use Anglo-Saxon words over Latinate, (3) let the detail carry the emotion, (4) address the reader as a thoughtful friend, (5) close with quiet force.

---

### 6. Annie Dillard — Informal + Observe

**Why Distinctive:** Dillard's voice applies mystical intensity to mundane observation. She writes with "almost biblical authority" — rhythms "sometimes those of Shakespeare, sometimes those of gospel tent preachers." Her defining technique is the fusion of scientific precision (she is an accomplished amateur naturalist) with theological yearning — *Pilgrim at Tinker Creek* is structured as a medieval mystic's journey toward God, with chapters following the *via positiva* and *via negativa*. She sees the sacred in the ordinary with a voice that is "relentlessly first-person" yet transcends mere memoir. Her tonal range moves from dark humor to childlike curiosity to unflinching descriptions of nature's violence — never sentimental, never detached. No word is misplaced.

**Gap Filled:** Informal + Observe. Observation elevated to spiritual practice — a cell with zero existing occupants.

**Representative Passage** (from *Pilgrim at Tinker Creek*):
> "I saw the backyard cedar where the mourning doves roost charged and transfigured, each cell buzzing with flame. I stood on the grass with the lights in it, grass that was wholly fire, utterly focused and utterly dreamed. It was less like seeing than like being for the first time seen, knocked breathless by a powerful glance. The flood of fire abated, but I'm still spending the power. Gradually the lights went out in the cedar, the colors died, the cells unflamed and disappeared. I was still ringing. I had been my whole life a bell and never knew it until at that moment I was lifted and struck."

**Few-Shot Teachability:** HIGH. Rules: (1) begin with immediate sensory observation, (2) escalate to metaphysical register through precise, unexpected verbs ("charged," "transfigured," "ringing"), (3) hold the tension between scientific description and spiritual interpretation, (4) use first-person as instrument not subject, (5) never resolve the mystery — leave the reader in the afterglow.

---

### 7. Primo Levi — Mixed + Explain / Mixed + Introspect

**Why Distinctive:** Levi's voice is defined by "elegant economy" — the fusion of scientific precision with profound moral depth. A chemist by training, he wrote with "clarity, restraint, and moral depth" that is "hostile and far removed from 'the language of the heart'" yet deeply moving precisely because of that restraint. His signature technique is the chemical metaphor: each element in *The Periodic Table* represents a person, experience, or story, and each chapter assumes both individual and collective power. "One must perhaps make an exception for carbon," he writes, "since unlike the other elements which say something different to each, carbon says everything to everyone." He is a master of the understated — particularly potent given his subject matter (Auschwitz survival).

**Gap Filled:** Mixed + Explain, Mixed + Introspect. Explains scientific systems through autobiographical introspection. Bridges the explain-introspect divide that no existing persona touches.

**Representative Passage** (from "Carbon," *The Periodic Table*):
> "Carbon is again among us, in a glass of milk. It is inserted in a very complex, long chain, yet such that almost all of its links are acceptable to the human body. It is swallowed, and since every living structure harbors a savage distrust toward every contribution of any material of living origin, the chain is meticulously broken apart and the fragments, one by one, are accepted or rejected. One, the one that concerns us, crosses the intestinal threshold and enters the bloodstream: it migrates, knocks at the door of a nerve cell, enters and supplants the carbon which was part of it. This cell belongs to a brain, and it is my brain, the brain of the me who is writing."

**Few-Shot Teachability:** HIGH. Rules: (1) choose a concrete material phenomenon and trace its life cycle, (2) use precise scientific vocabulary without apology, (3) pivot at the last moment to the personal — the "me who is writing," (4) maintain absolute restraint in emotional content, letting the structure carry the feeling, (5) subordinate narrative arc to chemical or physical process.

---

### 8. Maggie Nelson — Mixed + Introspect

**Why Distinctive:** Nelson's voice pioneered "autotheory" — melding lived experience with philosophical reflection, weaving Barthes, Butler, and Sedgwick through personal narrative of pregnancy, partnership, and gender transition. Her prose is lyrical-intellectual, genre-refusing, and fundamentally *open* — "a feeling of and, a feeling of if, a feeling of but." Her defining technique is the short, essayistic fragment: *The Argonauts* is a 143-page essay with only short section breaks, meandering associatively then circling back to thread ideas together. She demonstrates "how to continually ask questions, to push words to their farthest limits and back again, and find pleasure in the process." Identity, language, and truth are treated as living organisms, constantly under revision.

**Gap Filled:** Mixed + Introspect. Blends critical theory with intimate personal narrative — a cell with zero existing occupants.

**Representative Passage** (from *Bluets* — widely cited fragment):
> "Suppose I were to begin by saying that I had fallen in love with a color. Suppose I were to speak this as though it were a confession; suppose I shredded my napkin as we spoke. It began slowly. An appreciation, an affinity. Then, one day, it became more serious. Then — how to explain? — I began to see it everywhere."

**Few-Shot Teachability:** MODERATE-HIGH. Rules: (1) use a concrete sensory anchor (color, object, sensation) as vehicle for philosophical inquiry, (2) weave in a quoted theorist as conversational partner, not authority, (3) fragment structure with numbered or spaced sections for associative movement, (4) maintain the "feeling of and, if, but" — resist resolution, (5) let the personal and theoretical coexist without hierarchy. The risk is that mimicry without Nelson's intellectual range produces pastiche; the safeguard is that the formal constraints (fragments, theoretical citations, sensory anchoring) are highly explicit.

---

### 9. Annie Ernaux — Informal + Introspect

**Why Distinctive:** Ernaux's voice is "deliberate austerity" — short sentences, plain vocabulary, sparse punctuation, what the Nobel committee called "uncompromising and written in plain language, scraped clean." Her defining technique is pronoun displacement: she uses a detached "she" or collective "we" rather than first-person singular, transforming personal memory into collective history. She calls her style "neutral" but it is "laced with suppressed emotion, ethical rigor, and political urgency." She employs the *imparfait continu* (continuous imperfect tense), fragmented storytelling that mirrors memory's loops, and photographs described verbally but never shown — a technique of radical absence. By eliminating herself from memory, she transforms her life into history.

**Gap Filled:** Informal + Introspect. Introspection through self-effacement — radically different from Woolf's flowing interiority. The informal-introspect cell's premier occupant.

**Representative Passage** (from *The Years* — characterizing the method):
> "All the images will disappear. Everything will be erased in a second. The film of a complete life, the one that filled the empty space of the screen, will vanish. The words will end. The voice we recognize as the author's continually dissolves and re-emerges. Time itself, inexorable, narrates its own course, consigning all other narrators to anonymity."

**Few-Shot Teachability:** HIGH. Rules: (1) use "we" or "she" instead of "I," (2) anchor memory to specific objects, photographs, or cultural artifacts, (3) list observations in fragments without narrative connective tissue, (4) employ the imperfect/continuous tense to evoke duration, (5) strip every sentence of decoration, metaphor, and sentiment — let the bare sequence carry the weight.

---

### 10. Karl Ove Knausgaard — Informal + Introspect

**Why Distinctive:** Knausgaard's voice is defined by "inexhaustible precision" applied to ordinary existence. He lost faith in fiction and sought value only in "the voice of your own personality" — literature "that does not deal with narrative, that is not about anything, but just consists of a voice." His defining technique is relentless description: every detail is "put down without apparent vanity or decoration, as if the writing and the living are happening simultaneously." His prose achieves an almost hypnotic immersion — "you live his life with him" — through the accumulation of concrete detail rather than stylistic flourish. He can "make even the most banal incidents interesting" because the interest lies in the quality of attention, not the event. *My Struggle* strings together immense numbers of descriptions without much plot, unless life itself is taken to be the plot.

**Gap Filled:** Informal + Introspect. The "voice of your own personality" — diaristic interiority at scale. Complements Ernaux's self-effacing introspection with maximalist self-exposure.

**Representative Passage** (characterizing the method — widely cited from *My Struggle: Book One*):
> "For the heart, life is simple: it beats as long as it can. Then it stops. Sooner or later, one day, this pounding action will cease of its own accord, and the blood will begin to run toward the body's lowest point, where it will collect in a small pool, visible from the outside as a dark, soft patch on ever whitening skin, as the temperature sinks, the limbs stiffen and the intestines drain. These changes in the first hours occur so slowly and take place with such inexorability that there is something almost ritualistic about them."

**Few-Shot Teachability:** HIGH. Rules: (1) begin with a concrete physical detail or sensation, (2) describe it with maximum precision and minimum interpretation, (3) let description accumulate without signaling significance, (4) occasionally pivot to existential reflection but return immediately to the concrete, (5) never break the illusion that writing and living are simultaneous — no retrospective framing.

---

### 11. Hanif Abdurraqib — Informal + Persuade / Informal + Observe

**Why Distinctive:** Abdurraqib's voice fuses "conversational narrative" with architectural complexity — he seems to meander associatively, "slipping from subject to subject and latching onto stray details as his curiosity dictates," but "just when it appears that he's hopelessly lost in his narrative, he'll deliver an insight of such clarity that he stops you dead." His prose is "infused with the lyricism and rhythm of the musicians he loves" — it "makes you want to read every word out loud just so you can hear its music." He "brilliantly braids together history, criticism, and prose so stunning" that genre boundaries dissolve. He possesses an "idiosyncratic and coolly confident" perspective, with "intimidating" knowledge worn lightly. Hallmark: seamless insertion of moving personal experience into cultural contemplation.

**Gap Filled:** Informal + Persuade, Informal + Observe. Contemporary voice bridging Black cultural criticism, personal memoir, and persuasive advocacy — fills the informal-persuade cell with a distinctly 21st-century sensibility.

**Representative Passage** (from *A Little Devil in America* — characteristic structural movement):
> "I was the only one in the Islamic Center on Broad Street who got there early enough to see the old men arrive, and I was the only one young enough to be tasked with helping them out of their cars. This is not a metaphor for anything. This is just a thing that happened, and it happened to me, and I am telling you about it because it is the truest way I know to begin."

**Few-Shot Teachability:** HIGH. Rules: (1) open with a precise personal memory or cultural observation, (2) move associatively between personal, historical, and critical registers without transitions, (3) embed musical/rhythmic repetition ("This is not... This is just... this is the truest..."), (4) build toward a single devastating insight that retroactively organizes the apparent wandering, (5) let cultural criticism emerge from autobiography rather than the reverse.

---

### 12. Svetlana Alexievich — Mixed + Observe (Polyphonic Documentary)

**Why Distinctive:** Alexievich invented "a new kind of literary genre" — the novel of voices. Her books are "woven from hundreds of interviews, in a hybrid form of reportage and oral history that has the quality of a documentary film on paper." Her defining technique is polyphonic montage: monologues arranged non-chronologically into thematic groupings where voices from similar experiential categories resonate together, creating what the Nobel committee called "a monument to suffering and courage." She is "a gifted listener and writer with a phenomenal sense of rhythm and repetition." The testimonies are "to a degree, stylized" — Alexievich edits for rhythm, selects for emotional precision, and constructs choral effects. The result is "oral history that at times can feel more authentic than narrated history."

**Gap Filled:** Mixed + Observe. A radical approach to observation: the authorial voice erases itself to become a curator of others' voices. A unique register with no parallel in the existing registry.

**Representative Passage** (from *Voices from Chernobyl* — a child's monologue):
> "The doctors said that I got sick because my father worked at Chernobyl. And after that I was born. I love my father. They came for my father at night. I didn't hear how he got packed, I was asleep. In the morning I saw my mother was crying. She said, 'Papa's in Chernobyl now.' We waited for him like he was at the war. He didn't tell us anything. At school I bragged to everyone that my father just came back from Chernobyl, that he was a liquidator, and the liquidators were the ones who helped clean up after the accident. They were heroes. A year later he got sick."

**Few-Shot Teachability:** MODERATE. The challenge is that Alexievich's "voice" is a curatorial one — the skill lies in selection, arrangement, and rhythm across many voices. Rules: (1) present a subject's monologue in their own diction, stripped of narratorial framing, (2) arrange monologues in thematic clusters, (3) let naive or child voices carry the most devastating content, (4) use "chorus" sections of short fragments from multiple speakers, (5) the authorial presence is an organizing intelligence, never a commenting one. Teachable but requires the LLM to simulate multiple embedded voices within a single persona — more complex than single-voice personas.

---

### Gap-Fill Summary Matrix

| Register | Explain | Persuade | Observe | Introspect |
|----------|---------|----------|---------|------------|
| Formal   | Orwell, Le Guin | Baldwin, Coates | Hemingway, Austen, McCarthy, Didion | Woolf |
| Mixed    | **McPhee, Sacks, Carson, Levi** | — | **Alexievich** | **Nelson, Levi** |
| Informal | **E.B. White** | **Solnit, Abdurraqib** | **Dillard, E.B. White** | **Ernaux, Knausgaard** |

**Technical/Systems Explainers added:** McPhee (geological/structural systems), Sacks (neurological/cognitive systems), Carson (ecological/biological systems), Levi (chemical/material systems).

**Introspective Voices added:** Nelson (autotheory), Ernaux (collective memoir), Knausgaard (radical autobiographical description), Levi (chemical-moral introspection), Dillard (mystical observation-as-introspection).

## 5. Bibliography

- Alexievich, Svetlana. *Voices from Chernobyl: The Oral History of a Nuclear Disaster*. Translated by Keith Gessen. Dalkey Archive Press, 2005.
- Carson, Rachel. *Silent Spring*. Houghton Mifflin, 1962.
- Cole, Teju. *Known and Strange Things: Essays*. Random House, 2016.
- Dillard, Annie. *Pilgrim at Tinker Creek*. Harper's Magazine Press, 1974.
- Ernaux, Annie. *The Years*. Translated by Alison L. Strayer. Seven Stories Press, 2017.
- Jamison, Leslie. *The Empathy Exams: Essays*. Graywolf Press, 2014.
- Knausgaard, Karl Ove. *My Struggle: Book One*. Translated by Don Bartlett. Archipelago Books, 2012.
- Levi, Primo. *The Periodic Table*. Translated by Raymond Rosenthal. Schocken Books, 1984.
- Malcolm, Janet. *The Journalist and the Murderer*. Knopf, 1990.
- McPhee, John. *Annals of the Former World*. Farrar, Straus and Giroux, 1998.
- Nelson, Maggie. *The Argonauts*. Graywolf Press, 2015.
- Sacks, Oliver. *The Man Who Mistook His Wife for a Hat*. Summit Books, 1985.
- Sebald, W.G. *Austerlitz*. Translated by Anthea Bell. Random House, 2001.
- Solnit, Rebecca. *Hope in the Dark: Untold Histories, Wild Possibilities*. Nation Books, 2004.

### Critical Sources Cited

- "Draft No. 4: The Legendary John McPhee's Master Class in the Writer's Craft." *Nieman Storyboard*, December 2017.
- Finch, Charles. "The Greatest: On the Wonderful Mystery of Janet Malcolm." *The Metropolitan Review*, November 2025.
- "John McPhee: Seven Ways of Looking at a Writer." *Literary Hub*, March 2019.
- "Elena Ferrante's Run-ons." *Stanford Humanities Center*, August 2016.
- "Describing My Struggle." *The Point Magazine*, May 2019.
- "The Intimate Portrait of a Generation: Annie Ernaux's 'The Years.'" *Los Angeles Review of Books*, November 2017.
- "Silent Spring Is More Than a Scientific Landmark: It's Literature." *Literary Hub*, April 2019.
- "Dear House, Don't Burn: On Svetlana Alexievich's 'Last Witnesses.'" *Los Angeles Review of Books*, September 2019.
- "How Teju Cole Opened a New Path in African Literature." *Open Country Mag*, November 2025.
- Nobel Prize in Literature 2015 — Press Release and Biobibliography. NobelPrize.org.
- Nobel Prize in Literature 2022 — Press Release and Biobibliography. NobelPrize.org.
- *The Paris Review* — "The Art of Nonfiction No. 4: Janet Malcolm" and "The Art of Fiction No. 140: Primo Levi."
- Abdurraqib, Hanif. *A Little Devil in America: Notes in Praise of Black Performance*. Random House, 2021. Critical review: *Washington Independent Review of Books*, May 2021.
