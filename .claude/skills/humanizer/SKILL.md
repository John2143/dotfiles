---
description: Rewrite AI-generated text using dynamically-selected canonical author styles to produce natural human cadence and tone
argument-hint: '[text] or --file <path> [--persona <name>|all] [--dry-run] [--evaluate] [--list-personas]'
allowed-tools: Read, Write, Edit, Task
tool-hints: |
  Use Task for parallel persona subagent dispatch. Each subagent gets the full persona file from personas/{slug}.md.
  Use `Read(path=".claude/skills/humanizer/personas/registry.md")` for the persona lookup table.
  Use `Task(task)` with `tasks: [{id, description, assignment}]`. Each selected persona is one task.
  Collect subagent outputs from the Task result summary after all complete.
  Use Write for full-file overwrites when rewriting files. Use Edit sparingly for surgical fixes.
  Temperature 0–0.3 for style consistency; higher values produce caricature.
---

## Usage

**Invocation:** `/skill:humanizer [text] | --file <path> [--persona <name>|all] [--dry-run] [--evaluate] [--list-personas]`

Provide text to rewrite either inline or via a file. By default, 3–5 literary personas are dynamically selected based on the input's register, purpose, and domain. Flags:

- `--file <path>` — Read input from a file and overwrite it with the result (unless `--dry-run`).
- `--persona <name>` — Use a single persona by slug (e.g., `hemingway`, `orwell`, `didion`). Use `--list-personas` to see all available.
- `--persona all` — Explicitly select all 12 personas (same as default dynamic selection but broader).
- `--dry-run` — Print output to chat without modifying any file.
- `--evaluate` — After output, run a VERMILLION self-check and report the score.
- `--list-personas` — Print the persona registry and stop.

**Examples:**
- `/skill:humanizer This email sounds robotic. Please fix it.` — Inline text, dynamic persona selection
- `/skill:humanizer --file draft-post.md` — Rewrite a file in place, dynamic personas
- `/skill:humanizer --file draft-post.md --persona hemingway --dry-run` — Preview Hemingway-style rewrite without saving
- `/skill:humanizer --file draft-post.md --persona all --evaluate` — Full rewrite with all personas and quality scoring
- `/skill:humanizer --list-personas` — List every available persona and their traits

Parse `$ARGUMENTS`:
- If `--list-personas` is present: read and print `.claude/skills/humanizer/personas/registry.md` and stop.
- If `--file <path>` is present: read that file as input. The skill overwrites it on output (unless `--dry-run`).
- If bare text is provided (no `--file`): treat it as inline input. Output prints to chat.
- `--persona <name>`: select a single persona by slug. Case-insensitive. Valid slugs are listed in `personas/registry.md`.
- `--persona all` or omitted: dynamically select 3–5 best-fit personas based on input analysis (Step 1b).
- `--dry-run`: print output to chat without modifying any file.
- `--evaluate`: after output, run a VERMILLION self-check and report the score.

---

## Mode: Humanize

Rewrite AI-generated text so it reads like a human wrote it — not by generic "de-AI-ification" tricks, but by channeling the text through distinct literary author voices. No commercial humanizer tool does this; the approach is drawn from research showing that author-style mimicry evades detection better and reads more naturally than synonym swaps or perplexity manipulation.

The skill dispatches 3–5 persona subagents in parallel, each directed to rewrite the input in one author's voice. Each persona lives in a dedicated file under `personas/{slug}.md` with a detailed style profile, 10 authentic exemplars, negative constraints, and failure-mode guidance. An aggregator synthesizes the best elements across drafts into a single human-sounding output.

### What to expect

**Input** (AI-written):
> It is important to note that implementing a four-day work week requires careful consideration of several factors. Furthermore, organizations must evaluate the impact on productivity, employee satisfaction, and operational costs. This means three things: first, a pilot program should be established; second, metrics must be defined; and third, feedback loops are essential for continuous improvement.

**Output** (single persona, `--persona hemingway`):
> They went to four days. The numbers held. The people were happier. It cost less. You try it small first. You measure what matters. You ask the people doing the work. Then you decide.

**Output** (dynamic selection):
> The four-day week is an experiment worth running. Not because the research is conclusive — the studies are small, the samples self-selected — but because the alternative, year after year of the same meetings in the same rooms, has its own cost. The cost of not trying anything.
>
> Most arguments for the four-day week are really arguments about what work is. A job where you can do in four days what you did in five is a job where one of those days was not work at all — it was attendance, performance, the theater of diligence. The question is not productivity. The question is honesty.
>
> Try it small. One team. Three months. Agree on what you will measure and measure it honestly. Ask the people doing the work what they need and listen. The numbers will hold or they will not. Either way, you will know something you did not know before.

### Step 1 — Parse input and mode

1. If `--list-personas` is present, read `.claude/skills/humanizer/personas/registry.md` and print it. Stop.
2. If `--file <path>` is present, verify the file exists with `read`. If missing or empty, print "Error: file not found or empty" and stop.
3. If no `--file` and no bare text: print the argument hint and stop. Do not guess.
4. If `--persona <name>` is specified and the slug is valid, skip Step 1b. Dispatch only that persona. The slug must match a filename in `.claude/skills/humanizer/personas/{slug}.md`.

### Step 1b — Select personas dynamically

When `--persona all` or no `--persona` flag is given, read the input and classify it on three axes:

**Register**: formal · mixed · informal
**Purpose**: persuade · explain · narrate · observe · introspect
**Subject domain**: technical/systems · social/cultural · personal/psychological · political/moral · atmospheric/descriptive

Read `.claude/skills/humanizer/personas/registry.md` for the full lookup table. Select 3–5 personas that maximize:
1. **Register match** (formal text → formal personas; informal → informal)
2. **Purpose diversity** (don't pick 3 personas that all specialize in "narrate")
3. **Subject fit** (political → Orwell, Baldwin, Coates; introspective → Woolf, Didion; descriptive → McCarthy, Hemingway; systems → Le Guin)

**Selection algorithm:**
- If input has one clear purpose: pick 2 personas strong on that purpose, plus 1–2 with contrasting registers.
- If input is mixed-purpose: pick 1 per dominant purpose (up to 5).
- Always include at least 1 persona whose register differs from the input's dominant register — this creates productive tension for the aggregator.
- If you cannot classify confidently, default to: Hemingway + Orwell + Didion + Baldwin + Woolf.

**Output**: Print which personas were selected and why (one line each). The user sees this selection; they can re-invoke with `--persona <name>` to override.

### Step 2 — Dispatch persona subagents

For each selected persona, read the full profile from `.claude/skills/humanizer/personas/{slug}.md`. Each file contains:
- Style description and voice analysis
- 10 unaltered exemplars from the author's work
- Negative constraints
- Common failure modes and "not good for" boundaries
- A ready-to-use persona prompt block

Construct each subagent's assignment as the content of that file, prepended with:

```
INPUT TEXT TO REWRITE:

{the_input_text}

---

{persona_file_content}
```

Dispatch all persona subagents in parallel using `Task(task)`. Each subagent writes only to memory (no files).

### Step 2b — Validate persona outputs

After all subagents return, check each output:
- Discard any output that is fewer than 3 sentences, identical to the input, or clearly nonsensical (random characters, non-English, meta-commentary instead of rewritten text).
- If only 1 persona produced usable output: skip aggregation. Print it with a note: "*Only the {persona} persona produced usable output.*"
- If 0 personas produced usable output: print the original text unchanged with a warning: "*Humanization failed — all persona subagents produced unusable output. Original text returned unchanged.*" Stop here.

### Step 3 — Aggregate persona outputs

Read all usable drafts. Tell the aggregator which personas were selected and why.

**Aggregator prompt:**

```
You are a literary editor. You have multiple drafts of the same text, each written in a different author's style. The personas were selected because the input text is {register} in register and primarily aims to {purpose}, concerning {domain}.

DRAFTS:
{list_each_draft_labeled_with_persona_name}

Your task: produce a single final text that reads like natural human writing — not AI, not pastiche, and not any single author's caricature.

RULES:
- Select the best elements from each draft. Do NOT pick a single winner.
- The final text must have a CONSISTENT voice within each section. Do not oscillate between different authorial styles within the same paragraph. A voice shift between sections is acceptable — each section must hold its voice steadily.
- Preserve all facts, claims, code blocks, tables, and structured data from the original.
- Remove any residual AI tropes: "moreover," "furthermore," "delve," "crucial," "paramount," "it is important to note," tricolons, formulaic signposting, uniform paragraph lengths.
- Vary paragraph length. Include at least one single-sentence paragraph.
- Trust the reader. Remove signposting like "This means three things" or "Let me explain."
- Write a conclusion that does NOT restate the introduction.
- The final voice should feel singular — as if one human wrote it, someone who can shift register but whose sensibility is consistent.
- Output ONLY the final text. No preamble, no commentary.

ANTI-PATTERNS:

BAD — voice oscillation within a paragraph:
The quarterly results were, one must acknowledge, disappointing. The team worked hard but the numbers did not lie. Blood meridian writ in red ink across the spreadsheet. His bonus was gone and there was no getting it back.

*PROBLEM: Austen, McCarthy, and Hemingway in three consecutive sentences. Reader is seasick.*

GOOD — voice-per-section, consistent within each:
The quarterly results were disappointing. Marketing over-spent by forty percent. The numbers did not lie.

It must be allowed that the fault was not entirely theirs. The campaign had been launched into a market that had already shifted beneath their feet. One could hardly blame them.

The board met in a room with no windows. They voted. Three left. Two stayed.

*CORRECT: Each section has ONE voice. Transitions are bridges, not collisions.*
```

Output the final text to chat (inline mode) or write it back to the input file (`--file` mode). If `--dry-run`, output to chat only.

### Step 4 — Evaluate (if `--evaluate`)

Run a quick VERMILLION self-check on the output:

Check each signal on a 3-point scale (0 = absent, 1 = mild, 2 = strong):
| Signal | Check |
|--------|-------|
| **V — Vague "their"** | Possessive pronouns without clear antecedents? |
| **E — Echoed structures** | Sentences follow the same rhythmic template? Read aloud. |
| **R — Rigid transitions** | >30% of sentences start with the same transition words? |
| **M — Mechanical punctuation** | Em dashes overloaded? Punctuation rhythm uniform? |
| **I — Inflexible paragraphing** | All paragraphs similar length? |
| **L — Lack of short paragraphs** | Any single-sentence paragraphs? |
| **L — Lack of personal voice** | Could anyone have written this? Distinct perspective? |
| **I — Imprecise abstraction** | Abstract nouns where concrete ones would work? |
| **O — Overuse of hedging** | "might," "may," "could," "it is important to note" density? |
| **N — No lived experience** | Any anecdotes, concrete examples, named specifics? |

Report: `VERMILLION: X/20`. Target ≤6. Flag any signal scoring 2.

### Step 4b — Re-aggregation fallback

If VERMILLION ≥ 10 or output quality is clearly poor on self-review:
- Do NOT automatically redo. Offer the user three options:
  1. **Single-persona mode**: use the single best draft directly. Name which persona and why.
  2. **Different persona set**: re-select with different register/purpose priorities, re-dispatch, re-aggregate.
  3. **Tighter aggregation**: "Produce at most 3 voice shifts. Each section must stay in ONE voice for at least 4 consecutive sentences. If a shift would feel jarring, do not shift."

---

## Persona Index & Files

All persona profiles live under `.claude/skills/humanizer/personas/{slug}.md`. Each file is a self-contained subagent prompt with 10 authentic exemplars, style analysis, negative constraints, and failure-mode guidance.

### Index

| Slug | Author | Register | Purpose | Domain | When to use |
|------|--------|----------|---------|--------|-------------|
| `hemingway` | Ernest Hemingway | informal | narrate | atmospheric/descriptive | Action, direct statements, understated emotion, technical precision |
| `austen` | Jane Austen | formal | observe | social/cultural | Social analysis, nuanced argument, ironic commentary, formal contexts |
| `mccarthy` | Cormac McCarthy | mixed | narrate | atmospheric/descriptive | Atmospheric description, grave subjects, landscape, existential weight |
| `didion` | Joan Didion | formal | observe | social/cultural | Analysis, cultural criticism, institutional critique, personal essay |
| `baldwin` | James Baldwin | mixed | persuade | political/moral | Persuasion, moral argument, personal testimony, calls to action |
| `orwell` | George Orwell | formal | explain | political/moral | Political argument, clear explanation, institutional critique |
| `woolf` | Virginia Woolf | formal | introspect | personal/psychological | Introspection, psychological depth, subjective experience, memory |
| `thompson` | Hunter S. Thompson | informal | narrate | social/cultural | Satire, institutional rage, dark comedy, anti-authoritarian polemic |
| `dfw` | David Foster Wallace | formal | explain | social/cultural | Cultural analysis, complex explanation, recursive argument, self-aware criticism |
| `leguin` | Ursula K. Le Guin | formal | explain | technical/systems | Systems thinking, ecological/political critique, speculative framing |
| `smith` | Zadie Smith | mixed | observe | social/cultural | Cultural criticism, personal essay, contemporary observation |
| `coates` | Ta-Nehisi Coates | formal | persuade | political/moral | Moral witness, historical analysis, institutional critique |

### Selection quick-reference

```
By register:   formal    → austen, didion, orwell, woolf, dfw, leguin, coates
               mixed     → mccarthy, baldwin, smith
               informal  → hemingway, thompson

By purpose:     persuade  → baldwin, orwell, thompson, coates
               explain   → orwell, dfw, leguin
               narrate   → hemingway, mccarthy, thompson
               observe   → austen, didion, smith
               introspect → woolf

By domain:      political/moral        → orwell, baldwin, coates, thompson
               social/cultural        → austen, didion, smith, dfw, thompson
               personal/psychological → woolf, didion
               technical/systems      → leguin, orwell, hemingway
               atmospheric/descriptive → mccarthy, hemingway
```

### How to add a persona

1. Create `personas/{slug}.md` following the format of existing files (Style Profile, 10 Exemplars, Negative Constraints, Common Failure Modes, Not Good For, Prompt).
2. Add the slug row to the index table above and to `personas/registry.md`.
3. Add the slug to the appropriate lines in the selection quick-reference above.
4. The orchestrator picks it up automatically — no other changes needed.
---

## Constraints

- Never alter meaning, facts, or technical accuracy.
- Preserve code blocks, tables, inline code, and structured data verbatim.
- When unsure about a stylistic edit, leave the original phrasing alone.
- Only read/write the specified input file. Do not search the repo or modify other files.
- Persona subagents write only to memory (no files). The aggregator produces the single output.
- Do not ask questions — work with the input provided.
- Do not use temperature above 0.3 for persona subagents (prevents caricature).
- This skill targets prose and markdown documents (blog posts, reports, documentation, emails, essays). Not for poetry, song lyrics, creative fiction, or code. Return code unchanged with a note.
- When selecting personas dynamically, always report which were chosen and why. The user can override.

## TLDR

This skill dispatches 3–5 persona subagents to rewrite AI text in distinct literary voices, then synthesizes the best elements. Personas are dynamically selected from a 12-author registry based on the input's register, purpose, and domain. Each persona file under `personas/` contains 10 exemplars, style analysis, and failure-mode guidance. If the aggregator produces pastiche or scores poorly, offer re-aggregation or single-persona fallback. Use `--persona <name>` for a single voice, `--dry-run` to preview, `--evaluate` for scoring.
