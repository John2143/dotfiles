"""GenAI turn activity — LLM call orchestration.

_run_with_heartbeat: heartbeat wrapper for sync LLM calls
_model_weights: selection weights for Gemini model tiering
_resolve_provider: OpenAI client factory for ollama/gemini
run_genai_turn_activity: single-turn LLM call with tool routing
"""

import asyncio
import json
import logging
import os
import random

from temporalio import activity

from frigate_genai.s3_helpers import (
    _atomic_write,
    _deserialize_messages,
    _first_line,
    _load_state,
    load_json,
)

log = logging.getLogger("frigate-genai-sidecar")


async def _run_with_heartbeat(func, *args, interval: float = 2.0):
    """Run a sync function in a thread, heartbeating every `interval` seconds.

    Prevents Temporal from cancelling the activity while the thread is busy
    (e.g. waiting for a slow LLM). On cancellation the inner task is also
    cancelled to avoid orphaning the thread.
    """
    task = asyncio.create_task(asyncio.to_thread(func, *args))
    try:
        while not task.done():
            try:
                jittered = interval * (0.8 + 0.4 * random.random())
                await asyncio.wait_for(asyncio.shield(task), timeout=jittered)
            except TimeoutError:
                activity.heartbeat()
        return task.result()
    except asyncio.CancelledError:
        task.cancel()
        raise


def _model_weights(gemini_models: list[str]) -> list[int]:
    """Return selection weights: flash-lite=3, base-flash=1, pro=1 (2:1 flash:pro ratio)."""
    weights = []
    for m in gemini_models:
        if "flash-lite" in m:
            weights.append(3)
        elif "pro" in m:
            weights.append(1)  # Reduced from 3 to 1
        else:
            weights.append(1)
    return weights


def _resolve_provider(provider_cfg: dict, model: str, timeout: float = 120.0):
    """Return (OpenAI client, model_name) for ollama/ or gemini/ models."""
    from openai import OpenAI

    is_ollama = model.startswith("ollama/")
    if is_ollama:
        base_url = provider_cfg.get("ollama_base_url", "http://office.ts.2143.me:11434/v1")
        api_key = os.environ.get("OLLAMA_API_KEY", "ollama")
        model_name = model[len("ollama/"):]
    else:
        base_url = provider_cfg.get("base_url", os.environ.get("OPENAI_BASE_URL", ""))
        api_key = os.environ.get(provider_cfg.get("api_key_env", ""), "")
        if not api_key:
            raise RuntimeError("API key not configured")
        model_name = model
    client = OpenAI(api_key=api_key, base_url=base_url, timeout=timeout)
    return client, model_name


@activity.defn(name="run_genai_turn")
async def run_genai_turn_activity(turn_arg: dict) -> dict:
    """Single-turn LLM call. Loads messages.json, deserializes [[ ]] refs,
    calls LLM, returns tool_calls + assistant_message + optional description.
    """

    msg_path = turn_arg["msg_path"]
    provider_path = turn_arg["provider_path"]
    model = turn_arg["model"]
    event_id = turn_arg["event_id"]
    camera = turn_arg["camera"]
    label = turn_arg["label"]

    # Load state from S3 or disk
    state, agent_dir = _load_state(msg_path)
    messages = state["messages"]

    # Turn-limit warnings: at 25 remaining, and urgency in nudge within 10
    turn_num = turn_arg.get("turn_num", 1)
    max_turns = turn_arg.get("max_turns", 100)
    if turn_num == max_turns - 25:
        messages.append({
            "role": "user",
            "content": (
                f"Turn {turn_num} of {max_turns}. "
                f"25 turns remaining. Start concluding — call set_description() soon."
            ),
        })
        _atomic_write(msg_path, state)

    # Deserialize [[filename]] refs → base64 data URIs for LLM call
    messages_with_images = _deserialize_messages(messages, agent_dir)

    # Load provider config
    try:
        provider_cfg = load_json(provider_path)
    except (OSError, json.JSONDecodeError) as e:
        log.error("Failed to load provider config: %s", e)
        raise RuntimeError(f"Failed to load provider config: {e}") from e

    extra_body = {}
    if model.startswith("ollama/"):
        extra_body["reasoning_effort"] = "none"
    elif model.startswith("gemini/"):
        thinking_mode = os.environ.get("GENAI_THINKING", "1") != "0"
        if thinking_mode:
            extra_body["thinking_enabled"] = True
    client, model_name = _resolve_provider(provider_cfg, model)
    from frigate_genai.tools.schemas import (
        _tool_close_subagent_schema,
        _tool_compact_schema,
        _tool_crop_schema,
        _tool_find_keyframes_schema,
        _tool_frame_diff_schema,
        _tool_get_snapshot_schema,
        _tool_set_description_schema,
        _tool_show_frame_schema,
        _tool_tag_image_schema,
        _tool_transcode_schema,
        _tool_upscale_schema,
        _tool_send_ipc_schema, _tool_wait_ipc_schema,
        get_tool_schemas,
    )
    tool_names = turn_arg.get("tool_names")
    if tool_names is not None:
        tools = get_tool_schemas(tool_names)
    else:
        # Fallback for old workflow calls (backward compatibility during transition)
        tools = turn_arg.get("tools")
        if tools is None:
            tools = [
                _tool_find_keyframes_schema(), _tool_frame_diff_schema(), _tool_tag_image_schema(),
                _tool_get_snapshot_schema(), _tool_show_frame_schema(), _tool_crop_schema(),
                _tool_transcode_schema(), _tool_compact_schema(), _tool_set_description_schema(),
                _tool_upscale_schema(), _tool_send_ipc_schema(), _tool_wait_ipc_schema(),
            ]


    from openai import APIStatusError, RateLimitError
    try:
        response = await _run_with_heartbeat(
            lambda: client.chat.completions.create(
                model=model_name,
                messages=messages_with_images,
                tools=tools,
                tool_choice="auto",
                extra_body=extra_body if extra_body else None,
            ),
            interval=8.0,
        )
    except RateLimitError as e:
        log.warning("Model %s rate-limited (429): %s", model, _first_line(str(e)))
        raise
    except APIStatusError as e:
        log.warning("LLM API error (HTTP %s): %s", e.status_code, _first_line(str(e)))
        raise
    msg = response.choices[0].message

    prompt_tok = response.usage.prompt_tokens
    comp_tok = response.usage.completion_tokens
    # LiteLLM reports cached tokens under prompt_tokens_details.cached_tokens
    # for Gemini; fall back to usage.cached_tokens for other providers.
    details = getattr(response.usage, "prompt_tokens_details", None)
    cached_tok = getattr(details, "cached_tokens", 0) if details else getattr(response.usage, "cached_tokens", 0) or 0
    log.info("GenAI turn: event=%s prompt=%d comp=%d cached=%d",
             event_id, prompt_tok, comp_tok, cached_tok)

    result = {
        "prompt_tokens": prompt_tok,
        "completion_tokens": comp_tok,
        "cached_tokens": cached_tok,
    }

    # Text-only response → persist it, then demand a function call
    if not msg.tool_calls:
        assistant_msg = msg.model_dump(exclude_none=True)
        result["assistant_message"] = assistant_msg
        result["text_only"] = True
        state["messages"].append(assistant_msg)
        remaining = max_turns - turn_num
        if remaining <= 10:
            urgency = f"Only {remaining} turns remaining! "
        else:
            urgency = ""
        tool_names = turn_arg.get("tool_names", [])
        tool_list = ", ".join(tool_names) if tool_names else "available tools"
        state["messages"].append({
            "role": "user",
            "content": (
                f"{urgency}You must call a tool function. Do NOT output plain text. "
                f"Choose from: {tool_list}. Continue your investigation."
            ),
        })
        _atomic_write(msg_path, state)
        return result

    assistant_msg = msg.model_dump(exclude_none=True)
    result["assistant_message"] = assistant_msg

    # Persist assistant message so tool activities can find their tc_id
    state["messages"].append(assistant_msg)
    _atomic_write(msg_path, state)
    log.debug("run_genai_turn: appended assistant message (tool_calls=%d)", len(msg.tool_calls))
    # Parse tool calls
    tool_calls = []

    def _reject(tc_id: str, content: str) -> None:
        """Append a tool-level error message and persist immediately."""
        state["messages"].append({
            "role": "tool",
            "tool_call_id": tc_id,
            "content": content,
        })
        _atomic_write(msg_path, state)

    for tc in msg.tool_calls:
        tc_entry = {
            "id": tc.id,
            "name": tc.function.name,
            "args": {},
        }
        try:
            args = json.loads(tc.function.arguments)
            if not isinstance(args, dict):
                args = {}
            tc_entry["args"] = args
        except json.JSONDecodeError as e:
            args = {}
            tc_entry["error"] = "json_parse_error"
            _reject(tc.id, (
                f"JSON parsing failed: {e}\n\n"
                f"Your tool call arguments were malformed. Common issues:\n"
                f"- Missing closing quote or brace\n"
                f"- Unescaped quotes inside strings\n"
                f"- Trailing comma\n\n"
                f"Fix the syntax and retry."
            ))
            continue  # Skip tool_calls.append — error already reported

        if tc.function.name == "set_description":
            confidence = args.get("confidence", "medium")
            description = args.get("description", "")
            valid_conf = {"high", "medium", "low", "nothing_found", "wrong_tag"}
            if not description or not description.strip():
                tc_entry["error"] = "empty_description"
                _reject(tc.id, (
                    "set_description() requires a non-empty description. "
                    "Provide your analysis before concluding."
                ))
                continue
            elif confidence not in valid_conf:
                tc_entry["error"] = f"invalid_confidence: {confidence}"
            else:
                result["description"] = description
                result["confidence"] = confidence

        if tc.function.name == "close_subagent":
            confidence = args.get("confidence", "medium")
            findings = args.get("findings", "")
            valid_conf = {"high", "medium", "low", "nothing_found"}
            if not findings or not findings.strip():
                tc_entry["error"] = "empty_findings"
                _reject(tc.id, (
                    "close_subagent() requires non-empty findings. "
                    "Summarize what you discovered before closing."
                ))
                continue
            elif confidence not in valid_conf:
                tc_entry["error"] = f"invalid_confidence: {confidence}"
            else:
                result["description"] = findings
                result["confidence"] = confidence
                result["key_images"] = args.get("show_images", [])

        tool_calls.append(tc_entry)
    # Guard: reject set_description/close_subagent when batched with other tools.
    # The model must review tool results before concluding.
    exit_tools = ("set_description", "close_subagent")
    if len(tool_calls) > 1 and any(tc["name"] in exit_tools for tc in tool_calls):
        exit_ids = [tc["id"] for tc in tool_calls if tc["name"] in exit_tools]
        for eid in exit_ids:
            state["messages"].append({
                "role": "tool",
                "tool_call_id": eid,
                "content": "Cannot call set_description/close_subagent while other tools are pending. Review their results first, then conclude."
            })
        _atomic_write(msg_path, state)
        tool_calls = [tc for tc in tool_calls if tc["name"] not in exit_tools]
        result.pop("description", None)
        result.pop("confidence", None)

    result["tool_calls"] = tool_calls
    return result
