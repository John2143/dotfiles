"""GenAIWorkflow — one scene in, one description out.

Every scene is: extract frames, pick keyframes, crop the detected object,
make one schema-constrained local LLM call, record the result, write it to
Frigate. No tool loop, no child agent sessions.
"""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.common import SearchAttributePair
from temporalio.workflow import ParentClosePolicy

from frigate_genai.config import (
    TASK_QUEUE,
    FFMPEG_TASK_QUEUE,
    LLM_TASK_QUEUE,
    _ACTIVITY_RETRY,
    _DESCRIPTION_RETRY,
    _EXTRACT_RETRY,
    _SEARCH_CONFIDENCE,
    _SEARCH_COST,
    _SEARCH_DURATION,
    _SEARCH_MODEL,
)
from frigate_genai.activities.select_model import DEFAULT_MODEL, select_model_activity
from frigate_genai.activities.frame_extraction import transcode_into_parts_activity
from frigate_genai.activities.records import record_result_activity
from frigate_genai.activities.frames import crop_detection_activity
from frigate_genai.activities.describe import run_describe_scene
from frigate_genai.activities.lifecycle import update_description_activity, cleanup_cancelled_activity
from frigate_genai.tools.find_keyframes import pick_keyframes_activity

MUST_KEEP = "must_keep"
STRONG_MODEL = "ollama/gemma4:26b"
WEAK_CONFIDENCE = ("low", "nothing_found")


def _scene_from_input(input_data: dict) -> dict:
    """Return the scene dict, synthesising one for a bare event (manual
    reprocess from the dashboard, or a redo trigger)."""
    scene = input_data.get("scene")
    if scene and scene.get("primary"):
        return scene
    start = float(input_data.get("start_time") or 0)
    end = float(input_data.get("end_time") or start)
    camera = input_data.get("camera", "")
    label = input_data.get("label", "")
    return {
        "scene_id": f"{camera}-{int(start)}",
        "camera": camera,
        "start": start,
        "end": end,
        "labels": [label] if label else [],
        "priority": MUST_KEEP,
        "members": [
            {"id": input_data["event_id"], "label": label, "start_time": start, "end_time": end},
        ],
        "primary": {
            "id": input_data["event_id"],
            "label": label,
            "start_time": start,
            "end_time": end,
            "data_box": input_data.get("data_box"),
        },
    }


def _is_weak(result: dict) -> bool:
    return bool(result.get("needs_review")) or result.get("confidence") in WEAK_CONFIDENCE


@workflow.defn
class GenAIWorkflow:
    """Describe one scene with a single local LLM call."""

    @workflow.run
    async def run(self, input_data: dict) -> None:
        event_id = input_data["event_id"]
        camera = input_data.get("camera", "")
        label = input_data.get("label", "")
        log_ctx = f"event={event_id} camera={camera} label={label}"
        scene = _scene_from_input(input_data)
        primary = scene["primary"]
        primary_id = primary["id"]
        labels = scene.get("labels") or ([label] if label else [])
        retry_of = input_data.get("retry_of")

        workflow.logger.info("GenAI workflow started: %s scene=%s labels=%s",
                             log_ctx, scene.get("scene_id"), labels)

        try:
            model = input_data.get("model")
            if not model:
                model = await workflow.execute_activity(
                    select_model_activity,
                    input_data,
                    start_to_close_timeout=timedelta(seconds=10),
                    retry_policy=_ACTIVITY_RETRY,
                )
            workflow.upsert_search_attributes([SearchAttributePair(_SEARCH_MODEL, model)])
            workflow.logger.info("model=%s", model)

            # Progress marker, so a long drain is visible in Frigate.
            await workflow.execute_activity(
                update_description_activity,
                args=[primary_id, f"Processing {label} on {camera}..."],
                start_to_close_timeout=timedelta(seconds=15),
                retry_policy=_ACTIVITY_RETRY,
            )

            # Frames come from the recording only. The event snapshot carries
            # the detector box and class burned in (snapshots.bounding_box is
            # true), which is both an answer leak and a worse image: measured
            # as a presence loss, not a gain.
            frame_count = 0
            event_prefix = f"events/{primary_id}"
            if not input_data.get("skip_frames"):
                try:
                    _, frame_count = await workflow.execute_activity(
                        transcode_into_parts_activity,
                        {**input_data, "event_id": primary_id},
                        task_queue=FFMPEG_TASK_QUEUE,
                        start_to_close_timeout=timedelta(hours=1),
                        heartbeat_timeout=timedelta(seconds=60),
                        retry_policy=_EXTRACT_RETRY,
                    )
                except Exception:
                    workflow.logger.warning("Frame extraction failed for %s", log_ctx)
                    frame_count = 0

            duration = int(float(scene.get("end") or 0) - float(scene.get("start") or 0))
            workflow.upsert_search_attributes([SearchAttributePair(_SEARCH_DURATION, duration)])

            data_box = primary.get("data_box")
            keyframe_keys: list[str] = []
            sharpest_key = None
            if frame_count > 0:
                picked = await workflow.execute_activity(
                    pick_keyframes_activity,
                    arg={"event_id": primary_id, "max_frames": frame_count,
                         "args": {"count": 8, "data_box": data_box}},
                    task_queue=LLM_TASK_QUEUE,
                    start_to_close_timeout=timedelta(seconds=60),
                    retry_policy=_ACTIVITY_RETRY,
                )
                keyframe_keys = [f"{event_prefix}/frames/frame_{i:03d}.jpg"
                                 for i in picked.get("keyframes") or []]
                if picked.get("sharpest_frame") is not None:
                    sharpest_key = f"{event_prefix}/frames/frame_{int(picked['sharpest_frame']):03d}.jpg"
                workflow.logger.info("keyframes=%d sharpest=%s", len(keyframe_keys), picked.get("sharpest_frame"))
            if not keyframe_keys:
                await workflow.execute_activity(
                    update_description_activity,
                    args=[primary_id, "Skipped: no recording"],
                    start_to_close_timeout=timedelta(seconds=60),
                    retry_policy=_DESCRIPTION_RETRY,
                )
                await workflow.execute_activity(
                    cleanup_cancelled_activity,
                    args=[{"event_id": primary_id}, False],
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=_ACTIVITY_RETRY,
                )
                workflow.logger.info("No frames for %s; labelled and stopped", log_ctx)
                return

            crop = await workflow.execute_activity(
                crop_detection_activity,
                arg={"event_id": primary_id, "frame_key": sharpest_key, "data_box": data_box},
                task_queue=LLM_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=60),
                retry_policy=_ACTIVITY_RETRY,
            )

            result = await workflow.execute_activity(
                run_describe_scene,
                arg={
                    "scene_id": scene.get("scene_id") or f"{camera}-{int(float(scene.get('start') or 0))}",
                    "camera": camera,
                    "keyframes": keyframe_keys,
                    "crop": crop,
                    "labels": labels,
                    "members": scene.get("members") or [],
                    "prompts_path": input_data.get("prompts_path", "/var/lib/frigate-genai-sidecar/prompts.json"),
                    "provider_path": input_data.get("provider_path", "/var/lib/frigate-genai-sidecar/provider.json"),
                    "model": model,
                },
                task_queue=LLM_TASK_QUEUE,
                start_to_close_timeout=timedelta(minutes=10),
                heartbeat_timeout=timedelta(seconds=120),
                retry_policy=_ACTIVITY_RETRY,
            )

            description = result.get("description") or ""
            weak = _is_weak(result)
            if weak:
                description = f"{description}\n\nNeeds review ({label}).".strip()

            # Durable record first: a crash between here and the Frigate write
            # must not lose the description or the token counts.
            await workflow.execute_activity(
                record_result_activity,
                arg={
                    "scene_id": scene.get("scene_id"),
                    "camera": camera,
                    "event_ids": [m.get("id") for m in scene.get("members") or []],
                    "labels": labels,
                    "priority": scene.get("priority", ""),
                    "model": result.get("model") or model,
                    "description": description,
                    "confidence": result.get("confidence", ""),
                    "needs_review": bool(result.get("needs_review")),
                    "retry_of": retry_of,
                    "seconds": result.get("seconds") or 0.0,
                    "prompt_tokens": result.get("prompt_tokens") or 0,
                    "completion_tokens": result.get("completion_tokens") or 0,
                    "cloud_cost_microdollars": 0,
                },
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )

            workflow.upsert_search_attributes([
                SearchAttributePair(_SEARCH_COST, 0),
            ])
            if result.get("confidence"):
                workflow.upsert_search_attributes([
                    SearchAttributePair(_SEARCH_CONFIDENCE, result["confidence"]),
                ])
            workflow.upsert_memo({
                "SceneId": scene.get("scene_id", ""),
                "Model": result.get("model") or model,
                "Confidence": result.get("confidence", "N/A"),
                "Tokens": f"in={result.get('prompt_tokens', 0)} out={result.get('completion_tokens', 0)}",
                "Seconds": f"{float(result.get('seconds') or 0):.1f}",
            })
            workflow.set_current_details(description)

            await workflow.execute_activity(
                update_description_activity,
                args=[primary_id, description],
                start_to_close_timeout=timedelta(seconds=60),
                retry_policy=_DESCRIPTION_RETRY,
            )

            # One retry on the stronger model when the first pass was weak.
            if weak and scene.get("priority") == MUST_KEEP and not retry_of:
                try:
                    await workflow.start_child_workflow(
                        GenAIWorkflow,
                        {**input_data, "scene": scene, "retry_of": scene.get("scene_id"),
                         "model": STRONG_MODEL, "skip_frames": True},
                        id=f"genai-{scene.get('scene_id')}-retry1",
                        task_queue=TASK_QUEUE,
                        parent_close_policy=ParentClosePolicy.ABANDON,
                    )
                except Exception:
                    workflow.logger.warning("Weak-output retry could not be queued for %s", log_ctx)

            await workflow.execute_activity(
                cleanup_cancelled_activity,
                args=[{"event_id": primary_id}, False],
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )
            workflow.logger.info("GenAI workflow completed: %s", log_ctx)
        except asyncio.CancelledError:
            workflow.logger.info("GenAI workflow cancelled, cleaning up: %s", log_ctx)
            await workflow.execute_activity(
                cleanup_cancelled_activity,
                args=[{"event_id": primary_id}, True],
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )
            raise
