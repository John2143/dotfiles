"""One schema-constrained local LLM call per scene.

The whole point of the rewrite: instead of a multi-turn tool loop, hand the
model up to 8 keyframes plus the detector crop and ask for a fixed JSON
object. Anything malformed degrades to a low-confidence description — never
to an exception, so a bad reply cannot become a Temporal retry storm.
"""

import base64
import json
import logging
import time

from temporalio import activity

from frigate_genai.activities.llm import _resolve_provider, _run_with_heartbeat
from frigate_genai.intake import MUST_KEEP_LABELS
from frigate_genai.s3_helpers import _first_line, _s3_get, load_json

log = logging.getLogger("frigate-genai-sidecar")

MAX_IMAGES = 8
MAX_TOKENS = 500
DESCRIPTION_MAX = 600

SCENE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["scene", "subjects", "action", "confidence", "needs_review"],
    "properties": {
        "scene": {"type": "string", "maxLength": DESCRIPTION_MAX},
        "subjects": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["label", "present", "count", "details"],
                "properties": {
                    "label": {"enum": sorted(MUST_KEEP_LABELS)},
                    "present": {"type": "boolean"},
                    "count": {"type": "integer", "minimum": 0},
                    "details": {"type": "string", "maxLength": 200},
                },
            },
        },
        "action": {"type": "string", "maxLength": 200},
        "confidence": {"enum": ["high", "medium", "low", "nothing_found"]},
        "needs_review": {"type": "boolean"},
    },
}

INSTRUCTIONS = """\
Answer with one JSON object and nothing else.

- "scene": one paragraph (max 600 chars) describing what happened from the
  first frame to the last: what entered, what left, what changed, where the
  action began and ended. Chronological. Only what is visible.
- "subjects": one entry per label in the requested list that is actually
  visible. Set "present": false when the detector's label is a false positive.
  "details" is a short physical description (clothing, colour, size, what the
  person is carrying, what the animal is doing).
- "action": the single most important action, max 200 chars.
- "confidence": "high" when the scene is unambiguous, "medium" when part is
  unclear, "low" when the images are unusable, "nothing_found" when the
  flagged label is not in the scene at all.
- "needs_review": true when a human should look at this event.
"""

_FALLBACK_MARKERS = ("response_format", "json_schema", "structured output", "unsupported")


def _prompt_context(arg: dict) -> tuple[str, dict]:
    """Camera note and per-label hints from the baked prompts.json.

    Explicit values on the arg win, so tests and one-off calls need no file.
    """
    camera_note = (arg.get("camera_note") or "").strip()
    label_hints = dict(arg.get("label_hints") or {})
    if camera_note and label_hints:
        return camera_note, label_hints
    try:
        prompts = load_json(arg.get("prompts_path", "/var/lib/frigate-genai-sidecar/prompts.json"))
    except (OSError, ValueError):
        return camera_note, label_hints
    if not camera_note:
        camera_note = (prompts.get("camera") or {}).get(arg.get("camera", ""), "").strip()
    for label in arg.get("labels") or []:
        if label not in label_hints:
            hint = (prompts.get("label") or {}).get(label)
            if hint:
                label_hints[label] = hint
    return camera_note, label_hints


def _build_messages(arg: dict) -> list[dict]:
    camera = arg.get("camera", "")
    camera_note, label_hints = _prompt_context(arg)
    labels = arg.get("labels") or []

    system_parts = [INSTRUCTIONS]
    if camera_note:
        system_parts.append(f"Camera context: {camera_note}")
    for label in labels:
        hint = (label_hints.get(label) or "").strip()
        if hint:
            system_parts.append(f"On {label}: {hint}")
    system_parts.append(f"Labels requested for this scene: {', '.join(labels)}.")

    members = arg.get("members") or []
    timeline = ""
    if members:
        first = members[0]
        last = members[-1]
        span = float(last.get("end_time") or 0) - float(first.get("start_time") or 0)
        timeline = (
            f"This scene merges {len(members)} detections on {camera} over {span:.0f} s "
            f"({', '.join(sorted(set(m.get('label', '') for m in members)))})."
        )

    facts = _detector_facts(members)

    user_text = (
        f"Images: keyframes in chronological order"
        + (", then a wider crop around the detected object" if arg.get("crop") else "")
        + f". {timeline}"
        + (f"\n\n{facts}" if facts else "")
        + "\n\nDescribe the scene."
    )

    return [
        {"role": "system", "content": "\n\n".join(system_parts)},
        {"role": "user", "content": [{"type": "text", "text": user_text}]},
    ]


def _detector_facts(members: list[dict]) -> str:
    """Frigate's own metadata, as text.

    Measured as the largest single win: telling the model what the detector
    already saw lifts dog recall 37→50 of 57, package 2→6 of 10, and cuts
    invented-person claims 5→1 of 19 for +9% tokens. The model is a describer,
    not a detector — and `sub_label` is the only identity signal in the system.
    """
    if not members:
        return ""
    lines = ["Frigate's detector reported (trust these facts, do not re-detect):"]
    for member in members:
        label = member.get("label") or "object"
        bits = [f"- {label}"]
        duration = member.get("duration")
        if isinstance(duration, (int, float)):
            bits.append(f"{duration:.1f} s")
        score = member.get("top_score")
        if isinstance(score, (int, float)) and score:
            bits.append(f"score {score:.2f}")
        where = member.get("on_property")
        if where is True:
            bits.append("inside our property")
        elif where is False:
            bits.append("outside our property")
        zones = member.get("entered_zones") or []
        if zones:
            bits.append(f"zones: {', '.join(zones)}")
        sub_label = (member.get("sub_label") or "").strip()
        if sub_label:
            bits.append(f"identified as {sub_label}")
        lines.append(" ".join(bits))
    lines.append("Report a subject only if you can see it in the images; use these facts "
                 "to recognise what the detector found, not as a substitute for looking.")
    return "\n".join(lines)


def _image_parts(arg: dict) -> list[dict]:
    keys = [k for k in (arg.get("keyframes") or []) if k][:MAX_IMAGES]
    crop = arg.get("crop")
    if crop:
        keys = keys + [crop]
    parts = []
    for key in keys:
        raw = _s3_get(key)
        if not raw:
            log.warning("Describe: missing image %s", key)
            continue
        encoded = base64.b64encode(raw).decode()
        parts.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encoded}"}})
    return parts


def _parse(text: str) -> dict | None:
    """Return a schema-valid payload, or None."""
    if not text:
        return None
    candidate = text.strip()
    if candidate.startswith("```"):
        candidate = candidate.strip("`")
        candidate = candidate.split("\n", 1)[1] if "\n" in candidate else candidate
    start, end = candidate.find("{"), candidate.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        payload = json.loads(candidate[start:end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    for key in SCENE_SCHEMA["required"]:
        if key not in payload:
            return None
    if not isinstance(payload.get("scene"), str) or not payload["scene"].strip():
        return None
    if not isinstance(payload.get("subjects"), list):
        return None
    if payload.get("confidence") not in ("high", "medium", "low", "nothing_found"):
        return None
    return payload


def _compose_description(payload: dict) -> str:
    description = payload["scene"].strip()
    extras = []
    for subject in payload.get("subjects") or []:
        if not isinstance(subject, dict) or not subject.get("present"):
            continue
        try:
            count = int(subject.get("count") or 0)
        except (TypeError, ValueError):
            count = 0
        if count > 1:
            extras.append(f"{count} {subject.get('label')}")
    if extras:
        description = f"{description} Also seen: {', '.join(extras)}."
    action = (payload.get("action") or "").strip()
    if action and action.lower() not in description.lower():
        description = f"{description} ({action})"
    return description[:DESCRIPTION_MAX]


def _call_model(client, model_name: str, messages: list[dict], structured: bool):
    kwargs = {
        "model": model_name,
        "messages": messages,
        "temperature": 0,
        "max_tokens": MAX_TOKENS,
        "extra_body": {"reasoning_effort": "none"},
    }
    if structured:
        kwargs["response_format"] = {
            "type": "json_schema",
            "json_schema": {"name": "scene", "schema": SCENE_SCHEMA, "strict": True},
        }
    return client.chat.completions.create(**kwargs)


@activity.defn(name="describe_scene")
async def run_describe_scene(arg: dict) -> dict:
    """Describe one scene with a single local LLM call."""
    scene_id = arg.get("scene_id", "?")
    model = arg.get("model") or "ollama/gemma4:12b"

    provider_cfg = load_json(arg.get("provider_path",
        "/var/lib/frigate-genai-sidecar/provider.json"))
    client, model_name = _resolve_provider(provider_cfg, model)

    messages = _build_messages(arg)
    images = _image_parts(arg)
    if not images:
        log.warning("Describe %s: no images available", scene_id)
        return {
            "description": "No frames available for this event.",
            "subjects": [], "confidence": "low", "needs_review": True,
            "prompt_tokens": 0, "completion_tokens": 0, "seconds": 0.0, "model": model,
        }
    messages[-1]["content"].extend(images)

    started = time.monotonic()
    structured = True
    try:
        response = await _run_with_heartbeat(
            lambda: _call_model(client, model_name, messages, structured),
            interval=8.0,
        )
    except Exception as e:
        if structured and any(marker in str(e).lower() for marker in _FALLBACK_MARKERS):
            log.warning("Describe %s: server rejected response_format (%s); retrying with the schema in the prompt",
                        scene_id, _first_line(str(e)))
            messages[0]["content"] += "\n\nJSON schema:\n" + json.dumps(SCENE_SCHEMA)
            response = await _run_with_heartbeat(
                lambda: _call_model(client, model_name, messages, False),
                interval=8.0,
            )
        else:
            raise

    seconds = time.monotonic() - started
    usage = getattr(response, "usage", None)
    prompt_tokens = getattr(usage, "prompt_tokens", 0) or 0
    completion_tokens = getattr(usage, "completion_tokens", 0) or 0
    text = response.choices[0].message.content if response.choices else ""

    payload = _parse(text or "")
    if payload is None:
        # Retry once at the same model before degrading.
        log.warning("Describe %s: malformed reply, retrying once", scene_id)
        retry = await _run_with_heartbeat(
            lambda: _call_model(client, model_name, messages, structured),
            interval=8.0,
        )
        payload = _parse((retry.choices[0].message.content if retry.choices else "") or "")
        if payload is None:
            log.error("Describe %s: malformed reply twice (%s)", scene_id, _first_line(text or ""))
            return {
                "description": (text or "")[:DESCRIPTION_MAX] or "Unreadable model reply.",
                "subjects": [], "confidence": "low", "needs_review": True,
                "prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
                "seconds": seconds, "model": model,
            }

    log.info("Describe %s: model=%s conf=%s review=%s %.1fs (%d+%d tokens)",
             scene_id, model, payload["confidence"], payload["needs_review"],
             seconds, prompt_tokens, completion_tokens)
    return {
        "description": _compose_description(payload),
        "subjects": payload.get("subjects") or [],
        "confidence": payload["confidence"],
        "needs_review": bool(payload.get("needs_review")),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "seconds": seconds,
        "model": model,
    }
