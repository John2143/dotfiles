"""Initialize agent state activity — loads prompts, composes system prompt,
writes messages.json to S3."""

import json
import logging

from temporalio import activity

from frigate_genai.config import _S3_BUCKET
from frigate_genai.s3_helpers import (
    _atomic_write,
    _s3_client,
    _s3_get,
    _s3_list,
    _s3_put,
    load_json,
)

log = logging.getLogger("frigate-genai-sidecar")


@activity.defn(name="init_agent_state")
async def init_agent_state_activity(init_arg: dict) -> dict:
    """Initialize agent state in S3: loads prompts, composes system prompt,
    writes messages.json. All I/O goes through S3.
    Returns {msg_path, max_frames}.
    """

    event_id = init_arg["event_id"]
    camera = init_arg["camera"]
    label = init_arg["label"]
    event_prefix = init_arg["frames_dir"]  # "events/{event_id}"

    prompts = load_json(init_arg["prompts_path"])
    camera_desc = prompts.get("camera", {}).get(camera, "")
    label_hint = prompts.get("label", {}).get(label, "")

    data_box = init_arg.get("data_box")
    box_text = ""
    if data_box and len(data_box) == 4:
        box_text = f"Detected at left={data_box[0]:.2f} top={data_box[1]:.2f} width={data_box[2]:.2f} height={data_box[3]:.2f}."

    if label == "car":
        prefix = (
            "You are a forensic vehicle analyst. The event you are watching matters — "
            "someone may have committed a crime. Your entire job is to LOOK AT FRAMES. "
            "Extract every identifying detail: make, model, color, license plate, damage, "
            "stickers, occupants."
        )
        crop_hint = "crop() close-ups: plates, badges, decals, occupants, damage. Crop TIGHT — a single plate or face should fill the crop, not the whole vehicle."
        bisect_hint = "Bisect when the vehicle stops or disappears."
    else:
        prefix = (
            "You are a forensic security camera analyst. The event you are watching "
            "matters — someone may need help or have committed a crime. Your entire job "
            "is to LOOK AT FRAMES. Understand exactly what happened from start to finish."
        )
        crop_hint = "crop() close-ups: faces, hands, clothing, items carried, bags, tools. Crop TIGHT — one subject per crop, not the whole scene."
        bisect_hint = "Bisect when behavior changes or the subject disappears."
    system_prompt = (
        prefix
        + "\n\n"
        + "WORK IN TWO PHASES. NEVER skip phase 2.\n\n"
        + "PHASE 1 — SCAN: For clips with ≤5 frames, view EVERY frame at "
        "@high or @max — token cost is trivial and low-res views miss details. "
        "For longer clips, scan batches of 5-10 at @low first. "
        "When you find something worth inspecting, transcode() that region "
        "to extract HD frames.\n\n"

        + "PHASE 2 — ZOOM: After scanning, you MUST zoom in on the subject. "
        + "Pick 2-4 key frames and show them individually at @max resolution "
        + "(e.g., show_frame('frame://45@max')). Then " + crop_hint + " "
        "If a cropped detail (plate, face, text) is STILL too small or blurry to read "
        "at @max resolution, upscale('crop://N') to enhance it 4x. Upscale is expensive "
        "(up to 3 min) and only accepts small tight crops — never full frames. "
        "Use it only when you have already zoomed and cropped and the detail remains "
        "unreadable, and you can name what you expect to read from it. "
        "Default to swinir-psnr for accurate detail; use realesrgan only on noisy or "
        "compressed frames. Never upscale an upscale://N — always go back to the "
        "original crop://N or frame://N for the cleanest source.\n\n"
        "PERSISTENCE: When cropping, start WIDER than you think — you can always call "
        "compact() to erase old attempts and zoom in differently. If a crop shows "
        "nothing useful, try a different region or frame. If 3 crops in a row produce "
        "tiny (<200px) or empty results, your coordinate estimation is off — compact "
        "and retry with wider bounds. Compact is FREE: it drops old compressed images "
        "to free context space, preserving your text findings. Report what you found "
        "AND what you searched for but couldn't find. "
        + bisect_hint + " Track every movement. "
        + "NEVER call set_description() until you have searched every visible region "
        "across 2-3 key frames. Report what you found AND what you searched for "
        "but couldn't find. If you upscaled, review the upscaled result before concluding."
    )

    spawn_guidance = (
        "\n\nSPAWN/JOIN -- PARALLEL SUBAGENTS:\n"
        "You can spawn() parallel subagents to investigate different regions simultaneously.\n"
        "Each subagent gets its own context and runs independently. Use spawn when:\n"
        "- Multiple distinct regions need inspection (plates, faces, text)\n"
        "- Different time windows need scanning\n"
        "- Detail extraction that would consume many turns\n"
        "Rules:\n"
        "- spawn() returns a spawn_key immediately. Subagents run in background.\n"
        "- call join(spawn_key) to collect results. BLOCKS until all complete.\n"
        "- join() returns formatted findings from each subagent.\n"
        "- Max 5 subagents per spawn.\n"
        "- Only spawn() when you have specific tasks -- don't spawn for trivial checks."
    )
    system_prompt += spawn_guidance

    if camera_desc:
        system_prompt += f"\n\n{camera_desc}"
    if label_hint:
        system_prompt += f"\n\n{label_hint}"

    frame_files = _s3_list(f"{event_prefix}/frames/frame_")
    max_frames = len(frame_files)
    user_text = (
        f"{label} on {camera}. {max_frames} recording frames (indices 0-{max_frames - 1}).\n\n"
        f"{box_text}\n\n"
        f"The snapshot is a low-res bounding box preview ~3s into the clip. "
        f"START HERE: show the recording frame closest to the snapshot's timestamp "
        f"at @high or @max resolution, then crop() the EXACT detection region "
        f"from the box above. Never crop arbitrary corners when the box tells you "
        f"where to look. Do NOT view frames at @tiny or @low unless you have 15+ "
        f"frames to scan — for short clips, every frame should be at @high or @max. "
        f"If the snapshot frame falls between recording frames, transcode() a 1-2s "
        f"window around the snapshot timestamp to extract HD frames."
    )

    agent_prefix = f"{event_prefix}/agent"
    # Clean old display files from S3
    old_displays = _s3_list(f"{agent_prefix}/display_")
    for key in old_displays:
        _s3_client().delete_object(Bucket=_S3_BUCKET, Key=key)
    msg_path = f"{agent_prefix}/messages.json"

    # Seed with a completed tool cycle
    snapshot_data = _s3_get(f"{event_prefix}/snapshot.jpg")
    if snapshot_data is not None:
        display_name = "display_001.jpg"
        _s3_put(f"{agent_prefix}/{display_name}", snapshot_data)
        init_messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": "A new detection was recorded. Inspect the snapshot."},
            {"role": "assistant", "content": None, "tool_calls": [
                {"id": "seed_snap", "type": "function", "function": {
                    "name": "show_frame", "arguments": '{"source": "snapshot://"}',
                }},
            ]},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"[[{display_name}]]"}},
                {"type": "text", "text": f"Detection snapshot.\n\n{user_text}"},
            ]},
        ]
    else:
        init_messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text},
        ]

    init_state = {
        "messages": init_messages,
        "agent_dir": agent_prefix,
        "camera": camera,
        "start_time": init_arg.get("start_time", 0),
        "end_time": init_arg.get("end_time", 0),
        "max_frames": max_frames,
        "data_box": data_box,
        "trace": [],
        "stats": {"turns_low": 0, "turns_high": 0, "turns_max": 0, "turns_transcode": 0},
    }
    _atomic_write(msg_path, init_state)

    log.info("init_agent_state: event=%s frames=%d msg_path=%s", event_id, max_frames, msg_path)
    return {"msg_path": msg_path, "max_frames": max_frames}



@activity.defn(name="init_subagent_state")
async def init_subagent_state_activity(init_arg: dict) -> dict:
    """Initialize subagent state: copy parent images, compose task-focused system
    prompt, seed messages.json. """
    task = init_arg["task"]
    camera = init_arg["camera"]
    label = init_arg["label"]
    subagent_dir = init_arg["subagent_dir"]
    event_id = init_arg["event_id"]

    # Copy parent images to subagent directory
    display_files = []
    for i, s3_key in enumerate(init_arg.get("image_s3_keys", [])):
        raw = _s3_get(s3_key)
        if raw:
            dname = f"display_{i+1:03d}.jpg"
            _s3_put(f"{subagent_dir}{dname}", raw)
            display_files.append(dname)

    # Build focused system prompt
    prompts = load_json(init_arg["prompts_path"])
    label_hint = prompts.get("label", {}).get(label, "")
    start_t = init_arg.get("start_time", 0)
    end_t = init_arg.get("end_time", 0)
    duration = end_t - start_t if start_t and end_t else 0
    system_prompt = (
        f"You are a focused analysis subagent investigating event {event_id}.\n"
        f"Camera: {camera}. Detected object: {label}. Clip duration: {duration:.1f}s.\n"
        + (f"Guidance for {label}: {label_hint}\n" if label_hint else "")
        + f"\nYour delegated task: {task}\n\n"
        "TOOLS: show_frame (scan frames), crop (zoom into regions), "
        "transcode (extract HD frames), upscale (4x AI enhancement for small details).\n\n"
        "RULES:\n"
        f"- You have {init_arg['max_turns']} turns. Be decisive.\n"
        "- Report exactly what you see -- do not speculate beyond the evidence.\n"
        "- If you cannot determine the answer after thorough inspection, "
        "use confidence='nothing_found'.\n"
        "- Do NOT call close_subagent until you have examined frames.\n"
        "- Use compact() if context gets full.\n\n"
        "YOUR OUTPUT: close_subagent(findings='...', confidence='high|medium|low|nothing_found')\n"
        "  findings = complete description with specific observable details.\n"
        "  confidence = how certain you are based on what you actually saw."
    )

    # Seed messages
    content_parts = []
    for dname in display_files:
        content_parts.append({"type": "image_url", "image_url": {"url": f"[[{dname}]]"}})
    content_parts.append({"type": "text", "text": f"Task: {task}\n\nInvestigate and call close_subagent() when complete."})

    init_messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": content_parts},
    ]

    msg_path = f"{subagent_dir}messages.json"
    state = {
        "messages": init_messages,
        "agent_dir": subagent_dir,
        "camera": camera,
        "start_time": init_arg.get("start_time", 0),
        "end_time": init_arg.get("end_time", 0),
        "max_frames": 0,
        "data_box": None,
        "trace": [],
        "stats": {},
        "task": task,
        "subagent_id": subagent_dir.rstrip("/").split("/")[-1],
        "key_images": [],
    }
    _atomic_write(msg_path, state)

    log.info("init_subagent_state: event=%s sub_id=%s task=%s", event_id, state["subagent_id"], task[:40])
    return {"msg_path": msg_path}