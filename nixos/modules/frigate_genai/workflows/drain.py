"""DrainWorkflow — batch intake while the workstation is idle.

Runs every 300 s (started by the dispatcher's trigger loop, one at a time),
caps itself at 20 minutes, and stops starting new scenes the moment the seat
gate closes. Each scene is one GenAIWorkflow child; children are started with
ABANDON so a drain finishing never kills work in flight.
"""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.workflow import ParentClosePolicy

from frigate_genai.config import DISPATCHER_TASK_QUEUE, TASK_QUEUE, _ACTIVITY_RETRY
from frigate_genai.activities.dispatcher import (
    collect_scenes_activity,
    finish_drain_activity,
    gate_status_activity,
    genai_paused_activity,
)
from frigate_genai.activities.lifecycle import label_only_activity
from frigate_genai.activities.select_model import DEFAULT_MODEL
from frigate_genai.workflows.genai import STRONG_MODEL, GenAIWorkflow

DRAIN_BUDGET = timedelta(minutes=20)
MAX_CONCURRENT_SCENES = 2
LABEL_BATCH = 20


@workflow.defn
class DrainWorkflow:
    """One drain: collect, label skips, describe scenes while the gate holds."""

    @workflow.run
    async def run(self, arg: dict | None = None) -> dict:
        arg = arg or {}
        started_at = workflow.now()
        prompts_path = arg.get("prompts_path", "/var/lib/frigate-genai-sidecar/prompts.json")
        provider_path = arg.get("provider_path", "/var/lib/frigate-genai-sidecar/provider.json")

        if await workflow.execute_activity(
            genai_paused_activity,
            task_queue=DISPATCHER_TASK_QUEUE,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=_ACTIVITY_RETRY,
        ):
            workflow.logger.info("drain: global pause active")
            return {"paused": True, "started": 0}

        collected = await workflow.execute_activity(
            collect_scenes_activity,
            workflow.now().timestamp(),
            task_queue=DISPATCHER_TASK_QUEUE,
            start_to_close_timeout=timedelta(minutes=5),
            retry_policy=_ACTIVITY_RETRY,
        )
        scenes = collected.get("scenes") or []
        labelled = collected.get("labelled") or []
        workflow.logger.info("drain: %d scenes, %d skips", len(scenes), len(labelled))

        for start in range(0, len(labelled), LABEL_BATCH):
            batch = labelled[start:start + LABEL_BATCH]
            await asyncio.gather(*[
                workflow.execute_activity(
                    label_only_activity,
                    args=[item["id"], item["reason"]],
                    task_queue=DISPATCHER_TASK_QUEUE,
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=_ACTIVITY_RETRY,
                )
                for item in batch
            ], return_exceptions=True)

        remaining = list(scenes)
        started = 0
        strong = 0
        gate_reason = ""
        while remaining and (workflow.now() - started_at) < DRAIN_BUDGET:
            gate = await workflow.execute_activity(
                gate_status_activity,
                task_queue=DISPATCHER_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=20),
                retry_policy=_ACTIVITY_RETRY,
            )
            if not gate.get("open"):
                gate_reason = gate.get("reason", "closed")
                workflow.logger.info("drain: gate closed (%s), %d scenes left for next drain",
                                     gate_reason, len(remaining))
                break

            batch, remaining = remaining[:MAX_CONCURRENT_SCENES], remaining[MAX_CONCURRENT_SCENES:]
            handles = []
            for scene in batch:
                model = DEFAULT_MODEL
                if scene.get("priority") == "must_keep" and gate.get("strong_ok"):
                    model = STRONG_MODEL
                    strong += 1
                primary = scene["primary"]
                try:
                    handles.append(await workflow.start_child_workflow(
                        GenAIWorkflow,
                        {
                            "event_id": primary["id"],
                            "camera": scene["camera"],
                            "label": primary.get("label", ""),
                            "start_time": primary.get("start_time"),
                            "end_time": primary.get("end_time"),
                            "data_box": primary.get("data_box"),
                            "prompts_path": prompts_path,
                            "provider_path": provider_path,
                            "scene": scene,
                            "model": model,
                        },
                        id=f"genai-{scene['scene_id']}",
                        task_queue=TASK_QUEUE,
                        parent_close_policy=ParentClosePolicy.ABANDON,
                    ))
                    started += 1
                except Exception as e:
                    # A scene already described by an earlier drain (or a
                    # started child whose done-index write never landed) is
                    # skipped rather than aborting the whole drain.
                    workflow.logger.warning("drain: scene %s not started: %s",
                                            scene.get("scene_id"), e)
            await asyncio.gather(*handles, return_exceptions=True)

        summary = await workflow.execute_activity(
            finish_drain_activity,
            arg={
                "started": started,
                "retries": 0,
                "gpu_seconds": int((workflow.now() - started_at).total_seconds()),
                "gate_reason": gate_reason,
                "release_models": [DEFAULT_MODEL, STRONG_MODEL],
            },
            task_queue=DISPATCHER_TASK_QUEUE,
            start_to_close_timeout=timedelta(seconds=60),
            retry_policy=_ACTIVITY_RETRY,
        )

        result = {
            "paused": False,
            "scenes": len(scenes),
            "started": started,
            "strong": strong,
            "remaining": len(remaining),
            "gate_reason": gate_reason,
            "released": summary.get("released") if isinstance(summary, dict) else [],
        }
        workflow.logger.info("drain finished: %s", result)
        return result
