"""SubAgentWorkflow -- subagent lifecycle: init state -> run turn loop -> return findings."""

from datetime import timedelta

from temporalio import workflow
from temporalio.workflow import ParentClosePolicy

from frigate_genai.config import _ACTIVITY_RETRY
from frigate_genai.activities.agent_state import init_subagent_state_activity
from frigate_genai.workflows.agent_session import AgentSessionWorkflow


@workflow.defn
class SubAgentWorkflow:
    """Subagent lifecycle: initialize state on disk, delegate to AgentSessionWorkflow,
    return findings to spawner."""

    @workflow.run
    async def run(self, sub_input: dict) -> dict:
        # 1. Initialize subagent state
        init = await workflow.execute_activity(
            init_subagent_state_activity,
            arg=sub_input,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=_ACTIVITY_RETRY,
        )

        # 2. Delegate to AgentSessionWorkflow
        session = await workflow.execute_child_workflow(
            AgentSessionWorkflow,
            arg={
                "msg_path": init["msg_path"],
                "provider_path": sub_input["provider_path"],
                "model": sub_input["model"],
                "event_id": sub_input["event_id"],
                "camera": sub_input["camera"],
                "label": sub_input["label"],
                "max_turns": sub_input["max_turns"],
                "max_frames": 0,
                "start_time": sub_input["start_time"],
                "end_time": sub_input["end_time"],
                "genai_queue": sub_input["genai_queue"],
                "prompts_path": sub_input.get("prompts_path", ""),
                "depth": sub_input.get("depth", 1),
                "max_depth": sub_input.get("max_depth", 2),
            },
            id=f"{sub_input['event_id']}-sub-{sub_input.get('subagent_dir','').rstrip('/').split('/')[-1]}",
            task_queue=sub_input["genai_queue"],
            parent_close_policy=ParentClosePolicy.TERMINATE,
        )

        # 3. Return findings to spawner
        return {
            "findings": session.get("description"),
            "confidence": session.get("confidence"),
            "turns_used": session.get("turns_used", 0),
            "total_cost": session.get("total_cost", {}),
            "key_images": session.get("key_images", []),
            "tool_failures": session.get("tool_failures", 0),
            "subagent_id": sub_input.get("subagent_dir", "").rstrip("/").split("/")[-1],
            "task": sub_input.get("task", ""),
        }
