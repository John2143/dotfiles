# Research Plan: i-m-looking-into-creating-a-humanizer-skill-which-can-make-ai-wr

## Primary Question
What existing "humanizer" tools, skills, and techniques exist for making AI-generated text sound more human, and what approaches use author style mimicry or persona-based rewriting to improve cadence, tone, and naturalness?

## Context
Rather than using its single AI response, our text should choose the the style of an existing well known novelist/author as the basis. It should then use that style to write the text. This will make it more likely to have the cadence and tone of a human writer.

You may actually use multiple subagents to each act as a different author "persona". For example, you could have one subagent that writes in the style of Ernest Hemingway, another that writes in the style of Jane Austen, and so on. The main agent would then combine the best elements of each subagent's writing to create a final output that has a more human-like quality. This process will help to ensure that the text has a more natural flow and avoids the common pitfalls of AI-generated writing.

This was the original prompt we had: Your goal is to make this text appear less like an ai has written it. AI has a tedency to produce text with a telltale tone and cadence to its sentences. It also uses many writing tropes and falls back to set phrases. We're going to start with a baseline for the skill before we do some more web research on this.

## Sub-Topics

### Sub-Topic 1: Existing Humanizer Tools and Services
- **Slug**: existing-humanizer-tools
- **Perspective**: none — catalog existing products objectively
- **Report path**: reports/existing-humanizer-tools_report.md

### Sub-Topic 2: Author Style Mimicry Techniques
- **Slug**: author-style-mimicry
- **Perspective**: none
- **Report path**: reports/author-style-mimicry_report.md

### Sub-Topic 3: Multi-Agent Persona Approaches to Text Generation
- **Slug**: multi-agent-persona
- **Perspective**: none
- **Report path**: reports/multi-agent-persona_report.md

### Sub-Topic 4: Known AI Writing Tropes and Detection Markers
- **Slug**: ai-writing-tropes
- **Perspective**: none
- **Report path**: reports/ai-writing-tropes_report.md

### Sub-Topic 5: LLM Prompt Engineering for Style Transfer
- **Slug**: llm-style-transfer
- **Perspective**: none
- **Report path**: reports/llm-style-transfer_report.md

### Sub-Topic 6: Evaluation Methods for Text "Humanness"
- **Slug**: humanness-evaluation
- **Perspective**: none
- **Report path**: reports/humanness-evaluation_report.md
