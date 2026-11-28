"""PendingSceneWorkflow — one kept scene waiting for the seat gate to open.

Intake stores every kept scene here, paused or not, instead of starting the
description immediately. The drain then admits waiting scenes in priority
order, so pausing defers work rather than dropping it, and a restart, a drain
budget running out or a long pause loses nothing: the queue is in Temporal.

Keep run() replay-stable: waiting workflows replay on every new build, and a
scene can wait for days.
"""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.common import VersioningBehavior
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.workflow import ParentClosePolicy

from frigate_genai.activities.lifecycle import label_only_activity
from frigate_genai.activities.select_model import DEFAULT_MODEL
from frigate_genai.config import (
    DISPATCHER_TASK_QUEUE,
    STRONG_MODEL,
    TASK_QUEUE,
    _ACTIVITY_RETRY,
)

# By name: importing the workflow module here would make pending -> genai ->
# dispatcher -> pending a cycle. The type is registered on the same worker.
GENAI_WORKFLOW = "GenAIWorkflow"

PENDING_MAX_AGE = timedelta(days=7)
MUST_KEEP = "must_keep"


def pending_ids(input_data: dict) -> tuple[str, str]:
    """(pending workflow id, child GenAIWorkflow id) for one scene.

    The retry suffix keeps a weak-output retry of the same scene distinct from
    the scene itself, so neither start is rejected as a duplicate of the other.
    """
    scene_id = input_data["scene"]["scene_id"]
    suffix = "-retry1" if input_data.get("retry_of") else ""
    return f"pending-{scene_id}{suffix}", f"genai-{scene_id}{suffix}"


def pending_model(input_data: dict, strong_ok: bool) -> str:
    """Model to describe with, decided when the scene is admitted.

    A pause can last days, so the choice belongs at admission: the free VRAM
    that decides whether the 26b model fits is only known then.
    """
    if input_data.get("model"):
        return input_data["model"]
    scene = input_data.get("scene") or {}
    if scene.get("priority") == MUST_KEEP and strong_ok:
        return STRONG_MODEL
    return DEFAULT_MODEL


@workflow.defn(versioning_behavior=VersioningBehavior.AUTO_UPGRADE)
class PendingSceneWorkflow:
    """Hold one scene until the drain admits it, then describe it."""

    def __init__(self) -> None:
        self._strong_ok: bool | None = None

    @workflow.signal
    def admit(self, strong_ok: bool) -> None:
        """The drain's admission decision. First signal wins."""
        if self._strong_ok is None:
            self._strong_ok = bool(strong_ok)

    @workflow.run
    async def run(self, input_data: dict) -> dict:
        scene = input_data["scene"]
        scene_id = scene.get("scene_id", "")
        pending_id, genai_id = pending_ids(input_data)

        # A scene that never gets admitted must not sit in the queue forever;
        # expire it 7 days after its own start so the reason is visible in
        # Frigate rather than only in Temporal history.
        keep_until = float(scene.get("start") or 0) + PENDING_MAX_AGE.total_seconds()
        remaining = keep_until - workflow.now().timestamp()
        try:
            await workflow.wait_condition(
                lambda: self._strong_ok is not None,
                timeout=max(remaining, 1.0),
            )
        except asyncio.TimeoutError:
            workflow.logger.info("pending %s expired while paused", pending_id)
            await workflow.execute_activity(
                label_only_activity,
                args=[input_data["event_id"], "expired while paused"],
                task_queue=DISPATCHER_TASK_QUEUE,
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=_ACTIVITY_RETRY,
            )
            return {"expired": True, "scene_id": scene_id}

        model = pending_model(input_data, bool(self._strong_ok))
        child_input = {**input_data, "model": model}
        try:
            await workflow.start_child_workflow(
                GENAI_WORKFLOW,
                child_input,
                id=genai_id,
                task_queue=TASK_QUEUE,
                parent_close_policy=ParentClosePolicy.ABANDON,
            )
        except WorkflowAlreadyStartedError:
            # The child id already exists: an earlier admission of this same
            # scene. Nothing left to do. Any other failure must fail this
            # workflow so the scene stays visible instead of vanishing.
            workflow.logger.warning("pending %s: child %s already exists",
                                    pending_id, genai_id)
            return {"duplicate": True, "scene_id": scene_id}
        return {"model": model, "scene_id": scene_id}
