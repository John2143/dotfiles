"""GenAIWorkflow — orchestrates event processing: extract, genai, describe."""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.common import ParentClosePolicy, SearchAttributePair

from frigate_genai.config import (
    MAX_TURNS,
    TASK_QUEUE,
    FFMPEG_TASK_QUEUE,
    GEMINI_TASK_QUEUE,
    OLLAMA_TASK_QUEUE,
    _ACTIVITY_RETRY,
    _EXTRACT_RETRY,
    _SEARCH_CAMERA,
    _SEARCH_LABEL,
    _SEARCH_DURATION,
    _SEARCH_MODEL,
    _SEARCH_CONFIDENCE,
    _SEARCH_TRANSCODE,
    _SEARCH_TOOL_FAILURES,
)
from frigate_genai.s3_helpers import _s3_event_prefix, _s3_agent_prefix, _s3_put
from frigate_genai.activities.select_model import select_model_activity
from frigate_genai.activities.frame_extraction import transcode_into_parts_activity, fetch_snapshot_activity
from frigate_genai.activities.lifecycle import (
    update_description_activity,
    cleanup_cancelled_activity,
    save_agent_log_activity,
    summarize_agent_activity,
)
from frigate_genai.activities.agent_state import init_agent_state_activity
from frigate_genai.tools import _TOOL_ACTIVITIES, _get_tool_queue
from frigate_genai.workflows.agent_session import AgentSessionWorkflow


@workflow.defn
class GenAIWorkflow:
    """Orchestrates GenAI event processing: extract, genai, describe."""

    @workflow.run
    async def run(self, input_data: dict) -> None:

        try:
            event_id = input_data["event_id"]
            camera = input_data["camera"]
            label = input_data["label"]
            start_time = input_data["start_time"]
            end_time = input_data["end_time"]

            log_ctx = f"event={event_id} camera={camera} label={label}"

            workflow.logger.info("GenAI workflow started: %s", log_ctx)

            # Step 0: select model (car override is in input_data already)
            model = input_data.get("model")
            if model is None:
                model = await workflow.execute_activity(
                    select_model_activity,
                    input_data,
                    start_to_close_timeout=timedelta(seconds=10),
                    retry_policy=_ACTIVITY_RETRY,
                )
                input_data["model"] = model
            # Publish model as search attribute for filtering
            workflow.upsert_search_attributes([
                SearchAttributePair(_SEARCH_MODEL, model),
            ])
            workflow.logger.info("model=%s", model)

            skip_frames = input_data.get("skip_frames", False)

            # Step 1: fetch snapshot + extract ffmpeg frames (parallel)
            if skip_frames:
                frames_dir = await workflow.execute_activity(
                    fetch_snapshot_activity,
                    input_data,
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=_ACTIVITY_RETRY,
                )
            else:
                snapshot_dir, (ffmpeg_dir, frame_count) = await asyncio.gather(
                    workflow.execute_activity(
                        fetch_snapshot_activity,
                        input_data,
                        start_to_close_timeout=timedelta(seconds=30),
                        retry_policy=_ACTIVITY_RETRY,
                    ),
                    workflow.execute_activity(
                        transcode_into_parts_activity,
                        input_data,
                        task_queue=FFMPEG_TASK_QUEUE,
                        start_to_close_timeout=timedelta(hours=1),
                        heartbeat_timeout=timedelta(seconds=10),
                        retry_policy=_EXTRACT_RETRY,
                    ),
                )
                frames_dir = snapshot_dir

                # Upsert duration + frame count as search attributes
                dur_sec = int(end_time - start_time)
                workflow.upsert_search_attributes([
                    SearchAttributePair(_SEARCH_DURATION, dur_sec),
                ])
                workflow.logger.info("duration=%ds frames=%d", dur_sec, frame_count)


            # Step 2: progress patch
            await workflow.execute_activity(
                update_description_activity,
                args=[event_id, f"Processing {label} on {camera}..."],
                start_to_close_timeout=timedelta(seconds=15),
                retry_policy=_ACTIVITY_RETRY,
            )

            # Step 3: initialize agent state on disk (activity — sandboxed in workflow)
            genai_queue = GEMINI_TASK_QUEUE if model.startswith("gemini/") else OLLAMA_TASK_QUEUE
            init_result = await workflow.execute_activity(
                init_agent_state_activity,
                arg={
                    "event_id": event_id, "camera": camera, "label": label,
                    "frames_dir": frames_dir, "prompts_path": input_data["prompts_path"],
                    "data_box": input_data.get("data_box"),
                    "start_time": start_time, "end_time": end_time,
                },
                task_queue=TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=_ACTIVITY_RETRY,
            )
            msg_path = init_result["msg_path"]
            max_frames = init_result["max_frames"]

            session_result = await workflow.execute_child_workflow(
                AgentSessionWorkflow,
                arg={
                    "msg_path": msg_path,
                    "provider_path": input_data["provider_path"],
                    "model": model,
                    "event_id": event_id,
                    "camera": camera,
                    "label": label,
                    "max_turns": MAX_TURNS,
                    "max_frames": max_frames,
                    "start_time": start_time,
                    "end_time": end_time,
                    "genai_queue": genai_queue,
                    "prompts_path": input_data["prompts_path"],
                    "depth": 0,
                    "max_depth": 2,
                    "parent_agent_dir": f"events/{event_id}/agent/",
                },
                id=f"{event_id}-agent-session",
                task_queue=genai_queue,
                parent_close_policy=ParentClosePolicy.TERMINATE,
            )
            description = session_result.get("description")
            confidence = session_result.get("confidence")
            total_cost = session_result.get("total_cost", {})
            turns_low = session_result.get("turns_low", 0)
            turns_high = session_result.get("turns_high", 0)
            turns_max = session_result.get("turns_max", 0)
            turns_transcode = session_result.get("turns_transcode", 0)
            tool_failures = session_result.get("tool_failures", 0)
            trace_entries = session_result.get("trace_entries", [])
            turn = session_result.get("turns_used", 0) - 1

            # Format trace for UI + memo
            def _format_trace(entries: list[dict]) -> str:
                lines = []
                for e in entries:
                    if e["type"] == "turn":
                        prefix = "(cached) " if e.get("cached") else ""
                        lines.append(
                            f"Turn {e['turn']}: {e['prompt_tokens']}+{e['completion_tokens']} tokens {prefix}"
                        )
                    elif e["type"] == "tool_call":
                        n = e["name"]
                        a = e.get("args", {})
                        if n == "get_snapshot":
                            lines.append("  -> get_snapshot()")
                        elif n == "show_frame":
                            lines.append(
                                f"  -> show_frame({a.get('source', '?')[:50]}, {a.get('resolution', '?')}): {e.get('frames_shown', '?')} frames"
                            )
                        elif n == "crop":
                            lines.append(
                                f"  -> crop({a.get('source', '')[:30]}, count={e.get('count', '?')})"
                            )
                        elif n == "transcode":
                            lines.append(
                                f"  -> transcode(start={a.get('start')}, dur={a.get('duration', 1)}, {e.get('fps', '?')}fps): {e.get('frames_extracted', '?')} frames"
                            )
                        elif n == "compact":
                            lines.append("  -> compact()")
                        elif n == "set_description":
                            lines.append(
                                f"  -> set_description(confidence={e.get('confidence')}): {e.get('description', '')[:120]}"
                            )
                        else:
                            lines.append(f"  -> {n}()")
                        if e.get("error"):
                            lines.append(f"    ERROR: {e['error']}")
                    elif e["type"] == "nudge":
                        lines.append(f"  [nudge] {e['reason']}")
                return "\n".join(lines)

            trace_text = _format_trace(trace_entries)
            trace_text += (
                f"\n\nTotal: {turn+1} turns, {turns_low} L/{turns_high} H/{turns_max} M/{turns_transcode} T, "
                f"{total_cost['prompt']}+{total_cost['completion']} tokens"
            )

            workflow.set_current_details(trace_text)
            workflow.upsert_memo({
                "AgentSummary": trace_text,
                "AgentTokens": (
                    f"in={total_cost['prompt']} "
                    f"out={total_cost['completion']} "
                    f"cached={total_cost.get('cached', 0)}"
                ),
                "AgentTurns": (
                    f"turns={turn+1} "
                    f"low={turns_low} "
                    f"high={turns_high} "
                    f"max={turns_max} "
                    f"transcode={turns_transcode}"
                ),
                "AgentConfidence": confidence or "N/A",
            })
            if confidence:
                workflow.upsert_search_attributes([
                    SearchAttributePair(_SEARCH_CONFIDENCE, confidence),
                ])
            workflow.upsert_search_attributes([
                SearchAttributePair(_SEARCH_TRANSCODE, turns_transcode > 0),
            ])
            workflow.upsert_search_attributes([
                SearchAttributePair(_SEARCH_TOOL_FAILURES, tool_failures),
            ])

            # Persist agent logs (fire-and-forget activity)
            trace_header = f"Event: {event_id}  Camera: {camera}  Label: {label}  Model: {model}\n"
            trace_header += f"Frames available: {max_frames}  Snapshot: yes\n"
            trace_header += f"Confidence: {confidence or 'N/A'}\n\n"
            await workflow.execute_activity(
                save_agent_log_activity,
                arg={"event_id": event_id, "trace_text": trace_header + trace_text},
                task_queue=genai_queue,
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=_ACTIVITY_RETRY,
            )

            stats = {
                "event_id": event_id, "camera": camera, "label": label, "model": model,
                "provider_path": input_data["provider_path"],
                "turns": turn + 1, "turns_low": turns_low, "turns_high": turns_high,
                "turns_max": turns_max, "turns_transcode": turns_transcode,
                "total_cost": total_cost, "confidence": confidence,
                "trace": trace_header + trace_text,
            }
            summary = await workflow.execute_activity(
                summarize_agent_activity,
                args=[stats],
                task_queue=genai_queue,
                start_to_close_timeout=timedelta(seconds=120),
                retry_policy=_ACTIVITY_RETRY,
            )
            if summary:
                description = f"{description}\n\n[{summary}]"

            # Step 4: final result
            if not description:
                workflow.logger.error("No description from GenAI: %s", log_ctx)
                await workflow.execute_activity(
                    update_description_activity,
                    args=[event_id, "Failed: GenAI returned no description"],
                    start_to_close_timeout=timedelta(seconds=15),
                    retry_policy=_ACTIVITY_RETRY,
                )
                return

            await workflow.execute_activity(
                update_description_activity,
                args=[event_id, description],
                start_to_close_timeout=timedelta(seconds=15),
                retry_policy=_ACTIVITY_RETRY,
            )

            workflow.logger.info("GenAI workflow completed: %s", log_ctx)
            await workflow.execute_activity(
                cleanup_cancelled_activity,
                args=[input_data, False],
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )
        except asyncio.CancelledError:
            workflow.logger.info("GenAI workflow cancelled, cleaning up: %s", log_ctx)
            await workflow.execute_activity(
                cleanup_cancelled_activity,
                args=[input_data, True],
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )
            raise
