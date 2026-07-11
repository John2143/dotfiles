"""Regression coverage for dispatcher-owned tool-call pairing."""

import asyncio
import importlib.util
import logging
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


class _FakeWorkflow:
    def __init__(self, genai_activity, apply_activity, outcome):
        self._genai_activity = genai_activity
        self._apply_activity = apply_activity
        self._outcome = outcome
        self.applied_outcomes = None
        self.logger = logging.getLogger(__name__)

    @staticmethod
    def defn(cls):
        return cls

    @staticmethod
    def run(fn):
        return fn

    def set_current_details(self, _details):
        pass

    def start_activity(self, _activity, **_kwargs):
        async def result():
            return self._outcome

        return result()

    async def execute_activity(self, activity, **kwargs):
        if activity is self._genai_activity:
            return {
                "tool_calls": [
                    {"id": "tag-call-from-dispatcher", "name": "tag_image", "args": {}}
                ]
            }
        if activity is self._apply_activity:
            self.applied_outcomes = kwargs["arg"]["outcomes"]
            return None
        raise AssertionError(f"Unexpected activity: {activity!r}")


class AgentSessionToolPairingTests(unittest.TestCase):
    def test_tag_result_uses_dispatcher_call_id_when_adapter_leaves_it_empty(self):
        """Gemini thought-adapter output must pair to the dispatched tag call."""
        genai_activity = object()
        apply_activity = object()
        outcome = {
            "messages": [
                {"role": "user", "content": [{"type": "image_url", "image_url": {}}]},
                {"role": "tool", "tool_call_id": "", "content": "Tagged 1 frame."},
            ]
        }
        workflow = _FakeWorkflow(genai_activity, apply_activity, outcome)
        modules = self._module_stubs(workflow, genai_activity, apply_activity)

        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_agent_session"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                asyncio.run(module.AgentSessionWorkflow().run(self._session_input()))
            finally:
                sys.modules.pop(module_name, None)

        self.assertEqual(
            workflow.applied_outcomes[0]["messages"][1]["tool_call_id"],
            "tag-call-from-dispatcher",
        )
        self.assertNotIn("tool_call_id", workflow.applied_outcomes[0]["messages"][0])

    @staticmethod
    def _module_stubs(workflow, genai_activity, apply_activity):
        temporalio = types.ModuleType("temporalio")
        temporalio.workflow = workflow
        exceptions = types.ModuleType("temporalio.exceptions")
        exceptions.ApplicationError = type("ApplicationError", (Exception,), {})

        config = types.ModuleType("frigate_genai.config")
        config._GENAI_RETRY = object()
        config._ACTIVITY_RETRY = object()

        genai_turn = types.ModuleType("frigate_genai.activities.genai_turn")
        genai_turn.run_genai_turn_activity = genai_activity
        tool_apply = types.ModuleType("frigate_genai.activities.tool_apply")
        tool_apply.apply_tool_messages_activity = apply_activity

        tools = types.ModuleType("frigate_genai.tools")
        tools._TOOL_ACTIVITIES = {"tag_image": object()}
        tools._get_tool_queue = lambda _name, queue: (object(), queue)

        schemas = types.ModuleType("frigate_genai.tools.schemas")
        for name in (
            "_tool_find_keyframes_schema", "_tool_frame_diff_schema", "_tool_tag_image_schema",
            "_tool_get_snapshot_schema", "_tool_show_frame_schema", "_tool_crop_schema",
            "_tool_transcode_schema", "_tool_compact_schema", "_tool_set_description_schema",
            "_tool_upscale_schema", "_tool_spawn_schema", "_tool_join_schema",
            "_tool_close_subagent_schema",
        ):
            setattr(schemas, name, lambda: {})

        return {
            "temporalio": temporalio,
            "temporalio.exceptions": exceptions,
            "frigate_genai.config": config,
            "frigate_genai.activities.genai_turn": genai_turn,
            "frigate_genai.activities.tool_apply": tool_apply,
            "frigate_genai.tools": tools,
            "frigate_genai.tools.schemas": schemas,
        }

    @staticmethod
    def _session_input():
        return {
            "msg_path": "unused", "provider_path": "unused", "model": "gemini",
            "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
            "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
        }


if __name__ == "__main__":
    unittest.main()
