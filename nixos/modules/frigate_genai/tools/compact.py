"""tool_compact activity — distill findings via LLM, strip old images, preserve same-turn crops."""

import json
import logging

from temporalio import activity

from frigate_genai.activities.genai_turn import _resolve_provider, _run_with_heartbeat
from frigate_genai.s3_helpers import (
    _find_tc_id,
    _load_state,
    _s3_get,
    _s3_list,
    load_json,
)

log = logging.getLogger(__name__)


@activity.defn(name="tool_compact")
async def tool_compact_activity(arg: dict) -> dict:
    """Compact context: distill findings via LLM, strip old images, preserve same-turn crops."""

    msg_path = arg["msg_path"]
    provider_path = arg.get("provider_path", "/var/lib/frigate-genai-sidecar/provider.json")
    model = arg.get("model", "gemini/gemini-2.5-flash")
    state, agent_dir = _load_state(msg_path)
    outcome_messages = []

    tc_id = _find_tc_id(state, "compact")

    # Find the assistant message that called compact — only strip BEFORE it
    compact_assistant_idx = None
    for i in range(len(state["messages"]) - 1, -1, -1):
        tcs = state["messages"][i].get("tool_calls", [])
        names = [t.get("function", {}).get("name", "") for t in tcs]
        if "compact" in names:
            compact_assistant_idx = i
            break

    # Extract text from messages up to the compact-calling assistant
    conv_lines = []
    for m in state["messages"][:compact_assistant_idx]:
        role = m.get("role", "")
        content = m.get("content", "")
        if isinstance(content, list):
            text = " ".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
        else:
            text = str(content) if content else ""
        if text.strip():
            prefix = "User" if role == "user" else ("Assistant" if role == "assistant" else role)
            conv_lines.append(f"[{prefix}] {text.strip()}")
    # Also include cropped/upscaled content from same turn (messages after assistant)
    for m in state["messages"][compact_assistant_idx + 1:] if compact_assistant_idx is not None else []:
        role = m.get("role", "")
        content = m.get("content", "")
        if isinstance(content, list):
            text = " ".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
        elif isinstance(content, str):
            text = content
        else:
            text = ""
        if text.strip() and role == "user":
            conv_lines.append(f"[Tool result] {text.strip()}")

    all_keys = _s3_list(agent_dir + "/")
    crop_files = sorted(k for k in all_keys if k.rsplit("/", 1)[-1].startswith("crop_"))
    upscale_files = sorted(k for k in all_keys if k.rsplit("/", 1)[-1].startswith("upscale_"))

    conv_text = "\n".join(conv_lines) if conv_lines else "(no prior conversation)"
    crop_list = ", ".join(f"crop://{int(cf.rsplit('/')[-1].replace('crop_','').rsplit('.',1)[0])}" for cf in crop_files[:20])
    upscale_list = ", ".join(f"upscale://{int(uf.rsplit('/')[-1].replace('upscale_','').rsplit('.',1)[0])}" for uf in upscale_files[:10])

    summary_prompt = (
        "You are summarizing a visual investigation. From the conversation below, produce a single "
        "paragraph covering:\n"
        "- Which frames were useful (with indices + resolution) and what they showed.\n"
        "- Which frames were NOT useful (empty, occluded, too dark).\n"
        "- Where to look next if investigation should continue.\n"
        "- What to re-view to refresh your memory (specific frame://N or crop://N).\n\n"
        f"Available crops: {crop_list or 'none'}\n"
        f"Available upscales: {upscale_list or 'none'}\n\n"
        "Conversation:\n"
        f"{conv_text}\n\n"
        "Compact summary:"
    )

    # Call LLM for distilled summary
    try:
        provider_cfg = load_json(provider_path)
        client, model_name = _resolve_provider(provider_cfg, model)
        resp = await _run_with_heartbeat(
            lambda: client.chat.completions.create(
                model=model_name,
                messages=[{"role": "user", "content": summary_prompt}],
                temperature=0.1,
                max_tokens=300,
            ),
            interval=5.0,
        )
        summary_text = resp.choices[0].message.content.strip()
        log.info("Compact summary (%d chars): %.80s...", len(summary_text), summary_text)
    except Exception as e:
        log.warning("Compact LLM summary failed: %s, falling back to raw", e)
        summary_parts = ["Exploration so far:"]
        for line in conv_lines:
            summary_parts.append(f"  {line}")
        if crop_files:
            crop_lines = ["\nCrops available:"]
            for cf in crop_files:
                cf_name = cf.rsplit("/", 1)[-1]
                crop_id = cf_name.replace("crop_", "").rsplit(".", 1)[0]
                crop_lines.append(f"  crop://{int(crop_id)}: {cf_name}")
            summary_parts.append("\n".join(crop_lines))
        if upscale_files:
            upscale_lines = ["\nUpscales available:"]
            for uf in upscale_files:
                uf_name = uf.rsplit("/", 1)[-1]
                us_id = uf_name.replace("upscale_", "").rsplit(".", 1)[0]
                upscale_lines.append(f"  upscale://{int(us_id)}: {uf_name}")
            summary_parts.append("\n".join(upscale_lines))
        summary_text = "\n".join(summary_parts)

    outcome_messages.append({"role": "user", "content": summary_text})

    # Strip image_url parts from messages BEFORE the compact-calling assistant
    strip_end = compact_assistant_idx if compact_assistant_idx is not None else len(state["messages"]) - 1
    for mi in range(strip_end):
        if state["messages"][mi].get("role") == "user":
            content = state["messages"][mi].get("content")
            if isinstance(content, list):
                state["messages"][mi]["content"] = [
                    p for p in content
                    if isinstance(p, dict) and p.get("type") != "image_url"
                ]

    tool_result = "Context compacted. Summary prepared, images removed. Use crop://N or upscale://N to re-view crops; use show_frame at @high resolution to re-examine frames."
    outcome_messages.append({
        "role": "tool", "tool_call_id": tc_id, "content": tool_result,
    })

    return {"crops_preserved": len(crop_files), "upscales_preserved": len(upscale_files),
            "messages": outcome_messages,
            "strip_images_before": compact_assistant_idx}
