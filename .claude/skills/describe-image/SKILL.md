---
description: Describe an image using a vision-capable model. Spawns a subagent if the current model lacks vision support.
argument-hint: <image-path>
allowed-tools: Read, Task
tool-hints: |
  Use `read` to verify the image exists and check its metadata.
  Use `Task(oracle)` or `Task(quick_task)` to spawn a vision-capable subagent
  when the current model cannot process images.
  The subagent runs `--model google/gemini-2.5-flash` (direct Google API)
  or `--model openrouter/google/gemini-2.5-flash` (OpenRouter).
  Prefer the google provider (cheaper, no OR surcharge) unless it's unreachable.
---


## Usage

**Invocation:** `/skill:describe-image <image-path> [image-path...]`

Describes an image using a vision-capable model. If the current model lacks vision support, the skill spawns a subagent with a vision model (`google/gemini-2.5-flash`).

- `image-path` — a local file path or URL to an image. Supported formats: PNG, JPEG, GIF, WebP, SVG, BMP. When omitted, the skill asks for a path.
- Multiple paths can be provided and each is described sequentially with its own label.

**Examples:**
- `/skill:describe-image screenshot.png` — Describe a local screenshot
- `/skill:describe-image https://example.com/photo.jpg` — Describe an image from a URL
- `/skill:describe-image img1.png img2.png` — Describe two images sequentially
Parse `$ARGUMENTS`:
- If a positional argument is provided, treat it as `$IMAGE_PATH` — the local file or URL to describe.
- If no argument was given, ask the user to provide an image path or URL.
- If multiple arguments are given, process each one sequentially.

---

## Mode: Describe a single image

### Step 1 — Validate the image

If `$IMAGE_PATH` is a local file:
- Use `read` to confirm the file exists and is readable.
- If the file doesn't exist, report the error and ask for a valid path.
- Supported formats: PNG, JPEG, GIF, WebP, SVG, BMP.

If `$IMAGE_PATH` is a URL:
- Use `read` to fetch the URL and confirm the returned data is an image (check Content-Type or binary signature).
- If the URL is inaccessible or returns non-image content, report the error.

### Step 2 — Check current model capabilities

Determine whether your current model supports image input:
- If you have the `inspect_image` tool available: use it directly.
- If your model supports image input natively (e.g., you are running on a Gemini or Claude model with vision): read the image file directly and describe it.
- If your model does NOT support images (e.g., DeepSeek, text-only models): proceed to Step 3.

### Step 3 — Spawn a vision-capable subagent

Launch a `Task(oracle)` subagent with a vision model:

```
Task(
  agent: "oracle",
  tasks: [{
    id: "DescribeImage",
    description: "Describe the image",
    assignment: "Read the image at $IMAGE_PATH and describe it in detail. Include: overall scene/subject, colors, composition, notable details, text content if any, and the mood or context. Be thorough but concise."
  }]
)
```

Model selection for the subagent:
- **Primary**: `google/gemini-2.5-flash` — direct Google API, no OpenRouter surcharge, supports text+image input.
- **Fallback**: `openrouter/google/gemini-2.5-flash` — OpenRouter, slightly more expensive but routed through multiple providers.

The subagent inherits the `Read` tool and can access the file at `$IMAGE_PATH`. If the image is a URL, the subagent can open it directly.

### Step 4 — Relay the description

Present the subagent's output to the user verbatim. Do not summarize or reinterpret — the subagent is the vision specialist.

---

## Mode: Describe multiple images

If multiple image paths are provided:
1. Process each one using Steps 1–4 above.
2. Label each description with the image path so the user knows which is which.
3. If images are related (e.g., screenshots of the same UI), note relationships between them after all descriptions.

---

## Output

A plain-text description of each image:
- **File**: the image path
- **Summary**: 1–2 sentence overview
- **Details**: bullet list of notable elements, colors, composition, text
- **Context**: any inferred mood, purpose, or category

---

## Constraints

- **Read-only**: never modify or delete the image file.
- **No secrets**: if the image contains API keys, tokens, passwords, or private data, flag it to the user but do not reproduce the secret in the description.
- **Subagent model**: always use a vision-capable model (`google/gemini-2.5-flash` or fallback). Never spawn a text-only model for image description.
- **Large images**: if the image is > 20 MB, warn the user that the API may reject or downsample it. Offer to resize before sending.
