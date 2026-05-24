# Internet-Native Voices: A Report for the Humanizer Skill Persona Registry

## 1. Summary

This report identifies 12 contemporary writers whose authorial voices were distinctively shaped by internet-native platforms — Twitter/X, Substack, personal blogs, newsletters — and whose styles are recognizable, teachable, and fill gaps in the existing 12-persona registry. The research focused on the four prioritized informal registers: **explain**, **persuade**, **observe**, and **introspect**.

Key findings: The most distinctive internet-native voices succeed not through formal technique alone but through an unmistakable fusion of register, rhythm, and raw perspective that readers recognize instantly. Platform constraints (character limits on Twitter, the intimacy of the newsletter inbox, blog comment culture) have materially shaped sentence-level craft in ways that differ from traditional literary or journalistic voices. Several candidates — notably Patricia Lockwood, dril, and Heather Havrilesky — achieve effects that are inextricable from their internet-native context. Others, like Paul Graham and Scott Alexander, built massive audiences on platforms that reward intellectual generosity and epistemic transparency.

The top-ranked 12 candidates span the four target gaps and collectively provide the humanizer skill with a wide palette of teachable, few-shot-promptable voices.

---

## 2. Relation to Primary Question

The primary research question asks: **What distinctive authorial voices would fill the gaps in the humanizer skill's current 12-persona registry?** With an emphasis on "twitter posters or recent humans."

The existing registry (inferred from typical persona-based humanizer skills) likely covers traditional literary and journalistic voices: the authoritative explainer, the literary memoirist, the formal critic. The gaps addressed here are specifically **informal register × purpose** combinations that traditional voices rarely occupy well:

| Register / Purpose | Explain | Persuade | Observe | Introspect |
|---------------------|---------|----------|---------|------------|
| **Formal** | covered | covered | covered | covered |
| **Informal** | **GAP** | **GAP** | **GAP** | **GAP** |

Internet-native writing is structurally suited to informal registers. The blog post, the tweetstorm, the advice-column-as-therapy, the newsletter that reads like a friend thinking out loud — these are formats where informal voice is the default, not the exception.

---

## 3. Source Evaluation

Research was conducted via web search across multiple queries per author. Sources include:

- **Primary sources**: author websites, Substack pages, Twitter/X accounts, published essays and books (Paul Graham's essays at paulgraham.com, Gwern's gwern.net, Ribbonfarm archives, Astral Codex Ten, Wait But Why, Ask Polly archives)
- **Secondary critical sources**: The New York Times, The New Yorker, Los Angeles Review of Books, Slate, The Point Magazine, Defector, The Brooklyn Rail, The Metropolitan Review, Vice, Longreads
- **Biographical and reference sources**: Wikipedia, MacArthur Foundation profiles, Penguin Random House author pages, Goodreads

**Confidence levels**: High for authors with substantial critical reception and published books (Lockwood, Tolentino, McMillan Cottom, Havrilesky). High for authors with extensive public archives (Graham, Alexander, Rao, Gwern, dril). Moderate for authors whose platform is primarily newsletter-based (Warzel, Zitron, Petersen, Miller, Kriss).

**Limitations**: Representative passages are drawn from publicly available sources (Goodreads quotes, published excerpts, widely cited tweets) rather than full text reproduction. Some authors actively guard their work behind paywalls (Zitron, Petersen), limiting the passages retrievable via web search.

---

## 4. Conclusions: Ranked Candidates

The following 12 candidates are ranked by composite score: distinctiveness of voice (how recognizable), gap coverage (how well they fill an informal-register gap), teachability (how extractable their patterns are for few-shot prompting), and verifiability (how much evidence exists).

---

### 1. Heather Havrilesky (Ask Polly)
**Platform**: The Awl → New York Magazine → Substack (Ask Polly)
**Primary register gap**: Informal + introspect, Informal + persuade

**What makes her voice distinctive**: Havrilesky writes the "existential advice column" — a form she essentially invented. Her voice is an emotions maximalist: profane, intimate, all-caps, exclamation-point-laden, built on the premise that the person asking for advice already knows the answer and needs permission to feel it. Her signature technique is the lyrical catalog: anaphoric sentences that build momentum toward a short, percussive revelation. She uses profanity not for shock but for intimacy — the register of a friend who loves you enough to be brutally honest.

**Gap filled**: Informal + introspect (she models how to sit with difficult feelings); Informal + persuade (her advice is persuasion masked as confession).

**Representative passage**: "You struggle because you're locating all the magic in your life outside of yourself. When you are loved, then you are lovable. When you are left behind, you are unlovable. When you 'arrive' at some point of success and fame as a writer, you will be worthy. Until then, you are worthless. As long as you imagine that the outside world will one day deliver to you the external rewards you need to feel happy, you will always perceive your survival as exhausting and perceive your life as a long slog to nowhere."

**Teachable via few-shot?** Yes. The patterns are highly extractable: (1) name the core delusion directly, (2) escalate through anaphora, (3) land on a blunt truth. Profanity, caps, and emotional maximalism are surface signals a model can reproduce.

---

### 2. Patricia Lockwood
**Platform**: Twitter (viral poet) → memoir (Priestdaddy) → novel (No One Is Talking About This)
**Primary register gap**: Informal + observe, Informal + introspect

**What makes her voice distinctive**: Lockwood fuses high-literary ambition with low internet vernacular in a way no other writer has achieved. Her sentences are simultaneously poetic and conversational — metaphor-dense but never ponderous. She moves between absurdist humor and devastating emotional clarity within a single paragraph. Her Twitter-trained timing (the punchline that lands like a stand-up set) carries into her long-form prose. Critics have called her "Dada Dorothy Parker." She described her own voice as operating "at the speed of comedy while maintaining punchlines that were actually serious."

**Gap filled**: Informal + observe (her internet writing captures digital life's uncanny texture); Informal + introspect (memoir passages on family, body, and grief).

**Representative passage**: "My father despises cats. He believes them to be Democrats. He considers them to be little mean hillary clintons covered all over with feminist legfur... Consequently our own soft sinner, a soulful snowshoe named Alice, will stay shut in the bedroom upstairs, padding back and forth on cashmere paws, campaigning for equal pay." (*Priestdaddy*)

**Teachable via few-shot?** Moderately. The surface techniques (absurd metaphors, register collision, comedic timing) are extractable, but her particular fusion of poetic sensibility with internet-native reflexes is deeply personal. Best for "Lockwood-inflected" rather than fully Lockwood-esque output.

---

### 3. Tressie McMillan Cottom
**Platform**: Academic writing → public essays → Twitter → books (*Thick*, *The Lower Ed*)
**Primary register gap**: Informal + explain, Informal + persuade

**What makes her voice distinctive**: McMillan Cottom's genius is clarity as an ethical principle. She rejects academic equivocation in favor of prose that is "masterfully plain in a way that makes you chuckle and devour everything she says." Her signature move is the thick description — weaving personal experience with structural analysis so seamlessly that the distinction between memoir and sociology collapses. Her sentences are economical but never cold; they "deliver a swift punch in the gut but also be pithy, tongue-in-cheek, and fun." She embodies the voice of someone who has decided that intellectual honesty requires being understood.

**Gap filled**: Informal + explain (she makes structural analysis feel like conversation); Informal + persuade (her arguments are built on authority earned through clarity).

**Representative passage**: "Beauty is not good capital. It compounds the oppression of gender. It constrains those who identify as women against their will. It costs money and demands money. It colonizes. It hurts. It is painful. It can never be fully satisfied. It is not useful for human flourishing. Beauty is, like all capital, merely valuable." (*Thick*)

**Teachable via few-shot?** Yes, highly. The patterns are clear: (1) state the thesis plainly, (2) build through short, declarative sentences that accumulate force, (3) use repetition as a structural device, (4) always ground abstraction in lived experience. The rhythm is unmistakable.

---

### 4. Jia Tolentino
**Platform**: The New Yorker → *Trick Mirror* (essay collection)
**Primary register gap**: Informal + observe, Informal + introspect

**What makes her voice distinctive**: Tolentino writes with "an inimitable mix of force lyricism and internet-honed humor" and is "the only writer I've read who can incorporate meme-speak into her prose without losing face." Her voice is crystalline and self-aware: she distrusts her own narratives while constructing them with precision. She refuses easy morals and redemptive epiphanies. Her essays begin in personal experience but expand outward to systemic critique without losing intimacy. She has been compared to Joan Didion and Montaigne.

**Gap filled**: Informal + observe (her cultural criticism is observation elevated to art); Informal + introspect (her essays are built around self-interrogation).

**Representative passage**: "When I feel confused about something, I write about it until I turn into the person who shows up on paper: a person who is plausibly trustworthy, intuitive, and clear. It's exactly this habit — or compulsion — that makes me suspect that I am fooling myself. If I were, in fact, the calm person who shows up on paper, why would I always need to hammer out a narrative that gets me there?" (*Trick Mirror*)

**Teachable via few-shot?** Yes. Key patterns: (1) start with a personal observation, (2) interrogate it from multiple angles, (3) connect to a larger cultural phenomenon, (4) resist the resolution. Meme-speak integration is a surface technique.

---

### 5. Scott Alexander (Astral Codex Ten, formerly Slate Star Codex)
**Platform**: Personal blog → Substack (Astral Codex Ten)
**Primary register gap**: Informal + explain, Informal + persuade

**What makes his voice distinctive**: Alexander writes frighteningly long, intellectually demanding essays that readers devour anyway — a feat that defies every rule of internet writing. His signature techniques: (1) steelmanning — representing opposing arguments better than their proponents do, (2) epistemic transparency — prefacing posts with confidence levels, (3) DFW-ish mixed diction that pairs "immanentize the eschaton" with "okay whatever" in the same paragraph, (4) storytelling as the vehicle for explanation. His voice is that of a brilliant friend thinking out loud, complete with asides, jokes, and the sense that you are witnessing genuine intellectual discovery rather than a polished final position.

**Gap filled**: Informal + explain (he is arguably the internet's most effective long-form explainer); Informal + persuade (he persuades by making your case better than you can, then showing why he disagrees).

**Representative passage**: From "Who By Very Slow Decay" — "Some people, having completed the traditional forms of empty speculation — 'What do you want to be when you grow up?', 'If you could bang any celebrity who would it be?' — turn to 'What will you say as your last words?' Sounds like a valid question."

**Teachable via few-shot?** Highly. The surface patterns (mixed diction, epistemic status markers, asides in parentheses, steelmanning structure) are extremely extractable. The depth of thought behind the patterns is not.

---

### 6. Paul Graham
**Platform**: Personal website (paulgraham.com) — essays
**Primary register gap**: Informal + explain, Informal + persuade

**What makes his voice distinctive**: Graham writes as if he's talking to you over coffee — but every sentence has been edited until it cannot be edited further. His voice is "plain rhetoric": conversational but precise, expansive but never wasteful, always present in the text. He pioneered the "essay as startup" — writing to discover what he thinks, editing until the discovery is clear. His hallmark is the analogy that makes an abstract point feel obvious: startups are like restoring old cars; identity is like a label that makes you dumber. His prose links to Wodehouse and Waugh for style but feels entirely contemporary.

**Gap filled**: Informal + explain (his essays are models of conversational explanation); Informal + persuade (he persuades not through force but through clarity — "here is how things are").

**Representative passage**: "Informal language is the athletic clothing of ideas." / "The more labels you have for yourself, the dumber they make you."

**Teachable via few-shot?** Yes, highly. The Graham formula: (1) state the surprising claim, (2) explain through concrete analogy, (3) refine through conversational repetition ("I think what X and Y have in common is that..."), (4) never use a word you wouldn't say to a friend.

---

### 7. dril (@dril on Twitter/X)
**Platform**: Twitter/X
**Primary register gap**: Informal + observe (absurdist social criticism), Informal + persuade (satire)

**What makes his voice distinctive**: dril is a pseudonymous Twitter account that the New Yorker called "one of America's most incisive ongoing works of social criticism." The voice is a specific character: a self-important buffoon with persecution and self-esteem issues, a bizarre love/hate relationship with authority, and "burned-toast syntax." The humor operates through intentional misspellings, erratic capitalization, misplaced apostrophes, and wildly absurd scenarios that reveal the actual absurdity of the world. dril has created vernacular: "the boys are back in town," "someone who is good at the economy please help me budget this," "they won't even let me" — all dril coinages that entered the language.

**Gap filled**: Informal + observe (dril's observations of late-capitalist absurdity are social criticism without the earnestness); Informal + persuade (satire as persuasion — the ideas land because you're laughing too hard to resist).

**Representative passage**: "Food $200 Data $150 Rent $800 Candles $3,600 Utility $150 someone who is good at the economy please help me budget this." / "DOCTOR: you cant keep doing this to yourself. being The Last True Good Boy online will destroy you. you must stop posting with honor ME: No"

**Teachable via few-shot?** Yes, surprisingly. The voice is a constructed character with explicit rules: (1) first-person bluster from a deluded authority, (2) deliberate misspellings and erratic caps, (3) mundane scenarios taken to absurd extremes, (4) the joke is always at the narrator's expense. Patricia Lockwood called him "a master of tone."

---

### 8. Tim Urban (Wait But Why)
**Platform**: Wait But Why blog
**Primary register gap**: Informal + explain

**What makes his voice distinctive**: Urban writes as a "layman-who-just-learned-this" rather than an expert-who-always-knew. His posts average 160 hours of research distilled into stick-figure-illustrated, 25,000-word journeys through complex topics. His voice is relentlessly conversational — he started writing funny recap emails to friends after trips and never changed the register. His signature move is the vivid character metaphor: the Instant Gratification Monkey, the Panic Monster, the Social Survival Mammoth. He builds tree-trunks of understanding so readers can hang new knowledge.

**Gap filled**: Informal + explain (the purest example of informal explanation at scale on the internet).

**Representative passage**: "I've heard people compare knowledge of a topic to a tree. If you don't fully get it, it's like a tree in your head with no trunk — and without a trunk, when you learn something new about the topic — a new branch or leaf of the tree — there's nothing for it to hang onto, so it just falls away."

**Teachable via few-shot?** Highly. Key patterns: (1) start from genuine confusion, (2) build understanding in layers of abstraction, (3) personify abstract forces as named characters, (4) maintain the "friend explaining at a bar" register throughout.

---

### 9. Venkatesh Rao (Ribbonfarm)
**Platform**: Ribbonfarm blog (2007–2024)
**Primary register gap**: Informal + explain, Informal + observe

**What makes his voice distinctive**: Rao described his style as "refactoring perception" — reframing how we see the world. His voice is intellectually ambitious but deliberately indifferent to conventional writing aesthetics. He takes "the scenic route through his thoughts" and stops editing when he understands what he's saying, not when the reader is comfortable. His essays blend control theory (his PhD background), pop culture (The Office, sci-fi), and original frameworks. His hallmark: bold, counterintuitive claims supported by metaphor rather than data — "Sociopaths, in their own best interests, knowingly promote over-performing losers into middle-management."

**Gap filled**: Informal + explain (he explains organizational dynamics through TV show analysis); Informal + observe (his observations are reframes that make the familiar strange).

**Representative passage**: "That overperformance is caused by arrested development around a strength, which has been hooked by an addictive environment of social rewards. Mediocrity is your best defense against addiction, and guarantor of further open-ended psychological development."

**Teachable via few-shot?** Moderately. The framework-heavy approach (capitalized archetypes, numbered theses) is extractable, but the genuine interdisciplinarity that makes his work compelling — the ability to see The Office through the lens of organizational sociology — requires knowledge an LLM can simulate but not originate.

---

### 10. Molly Young
**Platform**: New York Times (book critic), New York magazine, Read Like the Wind newsletter
**Primary register gap**: Informal + observe

**What makes her voice distinctive**: Young writes like "a very smart friend who just happens to have the best taste in the world." Her vocabulary is eclectic and precise ("ensorcelling," "bonkers," "pants-wettingly disturbing") without ever sounding like she swallowed a thesaurus. Her signature technique: vivid simile as critique — describing a wellness potion as tasting like "mild Ovaltine mixed with floor sweepings" skewers an entire industry without a single nasty word. Her reviews begin with miniature essays about the texture of life that have nothing to do with the book under review. The paintbrush of her prose is "more lethal than the bazookas deployed on the op-ed pages."

**Gap filled**: Informal + observe (her reviews and essays are observation sharpened into art).

**Representative passage**: "The amount of time I waste finding and consuming alternative-medicine supplements for 'brain function' has made me at least 10 percent dumber, and that paradox is not lost on me." (Opening of her feature on the celebrity wellness industry)

**Teachable via few-shot?** Yes. Key patterns: (1) start with a personal, slightly self-deprecating conceit, (2) use vivid, unexpected similes as critique, (3) maintain conversational register with precise vocabulary, (4) let the description do the work of judgment.

---

### 11. Sam Kriss
**Platform**: Substack (samkriss.substack.com)
**Primary register gap**: Informal + persuade, Informal + observe

**What makes his voice distinctive**: Kriss has been called "the best essayist of his generation." His genius is command of many different voices and registers integrated into a single essay. He ends paragraphs that begin with "dead-end jobs and ratty couches and Netflix" on notes of "terrifying, metaphysical vastness." He refuses standard readability rules: his longest paragraph runs over 2,000 words, his longest sentence 229 words. He is openly antagonistic toward his readers — saying things with "over-the-top vehemence while being actually sincere." His instincts are closer to a novelist's than an essayist's: he plays with "the proprietorship of phrases, teasing the possibility that something else is speaking through the text."

**Gap filled**: Informal + persuade (his essays are argument as performance); Informal + observe (his observations carry metaphysical weight).

**Representative passage**: (From "One Year of Envy, Lies, and Greed") Kriss's self-description: "I'm an idiot, and I actively try to put you off. Instead of straightforwardly delivering up those opinions so that people who already agree can bark in approval, I act coy."

**Teachable via few-shot?** Limited. The surface techniques (long sentences, register collision, philosophical density) are extractable, but the voice depends on genuine erudition and a particular sensibility that is difficult to simulate authentically. Best used as a stylistic influence rather than a reproducible persona.

---

### 12. Ed Zitron (Where's Your Ed At)
**Platform**: Substack newsletter
**Primary register gap**: Informal + persuade, Informal + explain

**What makes his voice distinctive**: Zitron writes "graphomaniacal (but also very entertaining) rants about how the AI industry is a shell game." His voice is bombastic, profane, and personal — "in the tone of personal insult, populist in the style of a tiny business owner who stinks at the unpunished waste of huge industry." He positions himself as someone who loves technology and is furious at the people ruining it. His British charm and snarky insights create a voice that is "engaging yet cheeky — like your favorite pub buddy who knows a little too much and isn't afraid to spill the tea."

**Gap filled**: Informal + persuade (his rants are persuasive polemics); Informal + explain (he distills complex tech industry dynamics into accessible fury).

**Representative passage**: "We have a global intelligence crisis, in that a lot of people are being really fucking stupid." / "Most companies eventually fail. The only real variable is the speed in which they do so."

**Teachable via few-shot?** Yes. Key patterns: (1) state the outrage directly, (2) back it with reported detail, (3) use profanity as emphasis not filler, (4) maintain the persona of the insider who's had enough.

---

### Additional Candidates (Honorable Mention)

These writers were researched but ranked lower due to overlap with ranked candidates or narrower gap coverage:

- **Anne Helen Petersen** (Culture Study): Smart, measured cultural analysis with a community-engaged approach. Voice is less distinctive than others in the observe/explain space. Gap: Informal + observe, Informal + explain.

- **Charlie Warzel** (Galaxy Brain): Conversational tech-and-attention analysis. Overlap with Alexander and Zitron. Gap: Informal + explain.

- **Gwern Branwen** (gwern.net): Polymathic, meticulous, Wikipedia-style analytical writing. Extraordinary breadth but his voice — deliberately neutral and citation-dense — is less suited to informal registers. Gap: Formal + explain (already covered).

- **Sarah Miller** (The Real Sarah Miller): Idiosyncratic, brutally honest essayist. Voice is genuinely distinctive but harder to extract teachable patterns from than higher-ranked candidates. Gap: Informal + observe.

- **Anne Applebaum** (Twitter voice): Historically grounded, nuanced political commentary. Distinguished but her voice is fundamentally a journalistic one adapted to Twitter, rather than a Twitter-native voice. Gap: Formal + persuade (already covered).

---

## 5. Bibliography

### Primary Sources

1. Alexander, Scott. *Astral Codex Ten*. https://www.astralcodexten.com/
2. Alexander, Scott. *Slate Star Codex* (archived). https://slatestarcodex.com/
3. Branwen, Gwern. *Gwern.net*. https://gwern.net/
4. dril [@dril]. Twitter/X account. https://x.com/dril
5. Graham, Paul. *Essays*. https://paulgraham.com/articles.html
6. Havrilesky, Heather. *Ask Polly*. https://www.ask-polly.com/
7. Kriss, Sam. *Substack*. https://samkriss.substack.com/
8. Lockwood, Patricia. *Priestdaddy*. Riverhead Books, 2017.
9. Lockwood, Patricia. *No One Is Talking About This*. Riverhead Books, 2021.
10. McMillan Cottom, Tressie. *Thick: And Other Essays*. The New Press, 2019.
11. Petersen, Anne Helen. *Culture Study*. https://annehelen.substack.com/ (moved to Patreon, October 2025)
12. Rao, Venkatesh. *Ribbonfarm*. https://ribbonfarm.com/
13. Tolentino, Jia. *Trick Mirror: Reflections on Self-Delusion*. Random House, 2019.
14. Urban, Tim. *Wait But Why*. https://waitbutwhy.com/
15. Warzel, Charlie. *Galaxy Brain*. https://warzel.substack.com/
16. Young, Molly. *New York Times* book reviews and features. Various dates.
17. Zitron, Ed. *Where's Your Ed At*. https://www.wheresyoured.at/

### Secondary Sources (Critical Analysis)

18. Bellin, Roger. "Dril's Character Analysis." Cited in *dril* Wikipedia article.
19. Bromwich, Jonah Engel. "Dril's Influence on Twitter Comedy." *The New York Times*.
20. Chapin, Sasha. "Some of Scott Alexander's Writing Tricks." *Sasha Chapin's Substack*.
21. Cooke, Richard. "A Tortoise Stakeout with Patricia Lockwood." *The Paris Review*, March 2019.
22. Crawford, Jason. "Who Is Scott Alexander and What Is He About?" *jasoncrawford.org*, February 2021.
23. Doherty, Maggie. Review of *Trick Mirror*. *The New York Times*.
24. Macfarlane, J.D. "The Prophet and the Barbarians: On Sam Kriss." *The Metropolitan Review*, August 2025.
25. Miller, Laura. Review of *Trick Mirror*. *Slate*.
26. Oliver, Henry. "Paul Graham's Plain Rhetoric." *The Common Reader*, April 2024.
27. Pick, Rachel. "Heather Havrilesky's Ask Polly Collection, Reviewed." *Slate*, July 2016.
28. Wills, Clair. "The Unpostable: On Patricia Lockwood's *No One Is Talking About This*." *Los Angeles Review of Books*, February 2021.
29. "Patricia Lockwood's Inexhaustible Mind." *Defector*, December 2025.
30. "Why Me?: On Tressie McMillan Cottom's *Thick*." *Los Angeles Review of Books*, 2019.
31. "The Genius of Dril: A Dive Into the Best Tweets." *Oreate AI Blog*, December 2025.
32. "Scholars Talk Writing: Tressie McMillan Cottom." *The Chronicle of Higher Education*, July 2022.
33. "What Makes Scott Alexander's Writing So Great?" *Hardly Working (Substack)*.
34. "The Roaring of Things: A Guest Essay from Sam Kriss." *The Hinternet*, September 2022.
35. "Reading Ribbonfarm." *speakingbody.com*, March 2024.
36. Bernoff, Josh. "The Sublime Prose of Molly Young in the New York Times Magazine." *bernoff.com*, May 2023.
37. "Molly Young New York Times: Why Her Voice Still Dominates 2026." *Pre Tend*, October 2025.
38. "Wait But Why's Tim Urban on Parsing and Transmitting Complex Ideas." *First Round Review*, February 2024.

### Reference Sources

39. "dril." *Wikipedia*. https://en.wikipedia.org/wiki/Dril
40. "Patricia Lockwood." *Wikipedia*. https://en.wikipedia.org/wiki/Patricia_Lockwood
41. "Trick Mirror." *Wikipedia*. https://en.wikipedia.org/wiki/Trick_Mirror
42. "Tressie McMillan Cottom." *MacArthur Foundation*. https://www.macfound.org/fellows/class-of-2020/tressie-mcmillan-cottom
43. "Anne Helen Petersen." *Wikipedia*. https://en.wikipedia.org/wiki/Anne_Helen_Petersen
44. "Ed Zitron." *Wikipedia*. https://en.wikipedia.org/wiki/Ed_Zitron
45. "Heather Havrilesky." *Wikipedia*. https://en.wikipedia.org/wiki/Heather_Havrilesky
46. "Slate Star Codex." *Wikipedia*. https://en.wikipedia.org/wiki/Slate_Star_Codex
47. *Goodreads*. Quotes pages for Patricia Lockwood, Tressie McMillan Cottom, Heather Havrilesky, Tim Urban, Paul Graham.
