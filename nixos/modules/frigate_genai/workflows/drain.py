"""DrainWorkflow — batch intake and admission while the workstation is idle.

Runs every 300 s (started by the dispatcher's trigger loop, one at a time) and
caps itself at 20 minutes. Intake queues every kept scene as a
PendingSceneWorkflow; this workflow then admits queued scenes in priority order
for as long as the seat gate is open and the pause flag is clear. Because the
queue lives in Temporal, a pause, a restart or the budget running out defers
work instead of dropping it.
"""

import asyncio
from datetime import timedelta

from temporalio import workflow

from frigate_genai.activities.dispatcher import (
    admit_scenes_activity,
    collect_scenes_activity,
    finish_drain_activity,
    gate_status_activity,
    genai_paused_activity,
)
from frigate_genai.activities.select_model import DEFAULT_MODEL
from frigate_genai.config import DISPATCHER_TASK_QUEUE, _ACTIVITY_RETRY
from frigate_genai.workflows.genai import STRONG_MODEL

DRAIN_BUDGET = timedelta(minutes=20)
MAX_CONCURRENT_SCENES = 2
ADMIT_INTERVAL = timedelta(seconds=20)


@workflow.defn
class DrainWorkflow:
    """One drain: collect new scenes, then admit queued ones while allowed."""

    @workflow.run
    async def run(self, arg: dict | None = None) -> dict:
        try:
            return await self._drain(arg or {})
        except asyncio.CancelledError:
            raise
        except Exception as e:
            # A failed drain has to be visible in the pod log, not only in
            # Temporal history.
            workflow.logger.error("drain failed: %s: %s", type(e).__name__, e)
            raise

    async def _drain(self, arg: dict) -> dict:
        started_at = workflow.now()
        prompts_path = arg.get("prompts_path", "/var/lib/frigate-genai-sidecar/prompts.json")
        provider_path = arg.get("provider_path", "/var/lib/frigate-genai-sidecar/provider.json")

        collected = await workflow.execute_activity(
            collect_scenes_activity,
            {
                "now": started_at.timestamp(),
                "prompts_path": prompts_path,
                "provider_path": provider_path,
            },
            task_queue=DISPATCHER_TASK_QUEUE,
            start_to_close_timeout=timedelta(minutes=20),
            heartbeat_timeout=timedelta(minutes=2),
            retry_policy=_ACTIVITY_RETRY,
        )
        workflow.logger.info("drain: %d events, %d skipped, %d enqueued",
                             collected.get("events", 0),
                             collected.get("skipped", 0),
                             collected.get("enqueued", 0))

        admitted = 0
        # Unknown until admission lists the queue: a paused drain breaks before
        # it does, and reporting 0 there would read as "nothing waiting".
        waiting: int | None = None
        paused = False
        gate_reason = ""
        while (workflow.now() - started_at) < DRAIN_BUDGET:
            if await workflow.execute_activity(
                genai_paused_activity,
                task_queue=DISPATCHER_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=_ACTIVITY_RETRY,
            ):
                workflow.logger.info("drain: global pause active")
                paused = True
                break

            gate = await workflow.execute_activity(
                gate_status_activity,
                task_queue=DISPATCHER_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=20),
                retry_policy=_ACTIVITY_RETRY,
            )
            if not gate.get("open"):
                gate_reason = gate.get("reason", "closed")
                workflow.logger.info("drain: gate closed (%s)", gate_reason)
                break

            outcome = await workflow.execute_activity(
                admit_scenes_activity,
                {
                    "max_in_flight": MAX_CONCURRENT_SCENES,
                    "strong_ok": bool(gate.get("strong_ok")),
                },
                task_queue=DISPATCHER_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=60),
                retry_policy=_ACTIVITY_RETRY,
            )
            admitted += int(outcome.get("admitted") or 0)
            waiting = int(outcome.get("waiting") or 0)
            if not outcome.get("admitted") and not outcome.get("in_flight"):
                # Nothing is runnable: the queue is empty, or every waiting
                # scene is held by a paused label. The next tick starts a fresh
                # drain 300 s later rather than spinning out the whole budget.
                break

            await workflow.sleep(ADMIT_INTERVAL)

        summary = await workflow.execute_activity(
            finish_drain_activity,
            arg={
                "started": admitted,
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
            "paused": paused,
            "enqueued": int(collected.get("enqueued") or 0),
            "admitted": admitted,
            "waiting": waiting,
            "gate_reason": gate_reason,
            "released": summary.get("released") if isinstance(summary, dict) else [],
        }
        workflow.logger.info("drain finished: %s", result)
        return result
