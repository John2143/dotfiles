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
    return findings to spawner. Acts as an IPC signal wrapper, forwarding parent↔child
    signals through the AgentSession handle."""

    def __init__(self):
        self._session_handle = None
        self._signal_buffer: list[dict] = []
        self.ipc_token: str = ""
        self.parent_ipc_token: str = ""

    @workflow.signal(name="receive_ipc")
    async def receive_ipc(self, payload: dict) -> None:
        """Forward IPC signals to the inner AgentSessionWorkflow.
        Buffers if handle not yet ready."""
        if self._session_handle is None:
            self._signal_buffer.append(payload)
        else:
            try:
                await self._session_handle.signal("receive_ipc", payload)
            except Exception:
                pass  # Drop forwarding attempt on child completion

    @workflow.update(name="receive_ipc_update")
    async def receive_ipc_update(self, payload: dict) -> dict:
        """Forward IPC update as Signal; never calls execute_update on child handle."""
        if self._session_handle is None:
            self._signal_buffer.append(payload)
            return {"status": "accepted", "message_id": payload.get("message_id", "")}
        try:
            await self._session_handle.signal("receive_ipc", payload)
            return {"status": "accepted", "message_id": payload.get("message_id", "")}
        except Exception:
            return {"status": "closed", "message_id": payload.get("message_id", "")}

    @workflow.run
    async def run(self, sub_input: dict) -> dict:
        # Capture IPC tokens before init activity
        self.ipc_token = sub_input.get("ipc_token", "")
        self.parent_ipc_token = sub_input.get("parent_ipc_token", "")

        # 1. Initialize subagent state
        init = await workflow.execute_activity(
            init_subagent_state_activity,
            arg=sub_input,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=_ACTIVITY_RETRY,
        )

        # 2. Start AgentSessionWorkflow as child (not execute — await after building handle)
        session_input = {
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
            "subagent_dir": sub_input["subagent_dir"],
            "parent_agent_dir": sub_input.get("parent_agent_dir", ""),
            "frames_dir": sub_input.get("frames_dir", ""),
            "ipc_token": self.ipc_token,
            "parent_ipc_token": self.parent_ipc_token,
            "parent_workflow_id": sub_input.get("parent_workflow_id", ""),
            "parent_run_id": sub_input.get("parent_run_id", ""),
        }
        child_workflow_id = f"{sub_input['event_id']}-sub-{sub_input.get('subagent_dir','').rstrip('/').split('/')[-1]}"

        # Use start_child_workflow to get a handle before awaiting result
        self._session_handle = await workflow.start_child_workflow(
            AgentSessionWorkflow,
            arg=session_input,
            id=child_workflow_id,
            task_queue=sub_input["genai_queue"],
            parent_close_policy=ParentClosePolicy.TERMINATE,
        )

        # Flush buffered signals
        if self._signal_buffer:
            buffered = list(self._signal_buffer)
            self._signal_buffer.clear()
            for payload in buffered:
                try:
                    await self._session_handle.signal("receive_ipc", payload)
                except Exception:
                    pass

        # 3. Await session result
        session = await self._session_handle
        self._session_handle = None

        # 4. Return findings to spawner
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
