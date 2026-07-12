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
        self.child_workflows = []
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

    def start_child_workflow(self, _workflow_type, arg=None, **kwargs):
        self.child_workflows.append(kwargs.get("id", "unknown"))
        return asyncio.Future()

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


class ResolveImageRefsTests(unittest.TestCase):
    """Unit tests for _resolve_image_refs parser."""

    @staticmethod
    def _module_stubs():
        temporalio = types.ModuleType("temporalio")
        wf = types.ModuleType("temporalio.workflow")
        wf.defn = staticmethod(lambda cls: cls)
        wf.run = staticmethod(lambda fn: fn)
        temporalio.workflow = wf

        exceptions = types.ModuleType("temporalio.exceptions")
        exceptions.ApplicationError = type("ApplicationError", (Exception,), {})
        temporalio.exceptions = exceptions

        config = types.ModuleType("frigate_genai.config")
        config._GENAI_RETRY = object()
        config._ACTIVITY_RETRY = object()

        genai_turn = types.ModuleType("frigate_genai.activities.genai_turn")
        genai_turn.run_genai_turn_activity = object()
        tool_apply = types.ModuleType("frigate_genai.activities.tool_apply")
        tool_apply.apply_tool_messages_activity = object()

        tools = types.ModuleType("frigate_genai.tools")
        tools._TOOL_ACTIVITIES = {}
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
            "temporalio.workflow": wf,
            "temporalio.exceptions": exceptions,
            "frigate_genai.config": config,
            "frigate_genai.activities.genai_turn": genai_turn,
            "frigate_genai.activities.tool_apply": tool_apply,
            "frigate_genai.tools": tools,
            "frigate_genai.tools.schemas": schemas,
        }

    def _load_module(self):
        modules = self._module_stubs()
        with patch.dict(sys.modules, modules, clear=False):
            spec = importlib.util.spec_from_file_location(
                "_resolve_refs_test",
                Path(__file__).parents[1] / "workflows" / "agent_session.py",
            )
            module = importlib.util.module_from_spec(spec)
            sys.modules["_resolve_refs_test"] = module
            spec.loader.exec_module(module)
            return module

    def test_crop_simple(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["crop://0"], "events/e1/agent/")
        self.assertIn("events/e1/agent/crop_000.jpg", keys)
        self.assertEqual(errs, [])

    def test_crop_with_suffix(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["crop://5@max"], "events/e1/agent/")
        self.assertIn("events/e1/agent/crop_005.jpg", keys)
        self.assertEqual(errs, [])

    def test_frame_simple(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["frame://3"], "events/e1/agent/")
        self.assertIn("events/e1/frames/frame_003.jpg", keys)
        self.assertEqual(errs, [])

    def test_frame_with_frames_dir(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["frame://3"], "events/e1/agent/", frames_dir="events/e1")
        self.assertIn("events/e1/frames/frame_003.jpg", keys)
        self.assertEqual(errs, [])

    def test_frame_subagent_correct_key(self):
        """Subagent at events/e1/agent/sub/s0/ with frames_dir should get correct key."""
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(
            ["frame://0"], "events/e1/agent/sub/s0/", frames_dir="events/e1"
        )
        self.assertIn("events/e1/frames/frame_000.jpg", keys)
        self.assertEqual(errs, [])

    def test_crop_empty_spec(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["crop://"], "events/e1/agent/")
        self.assertEqual(keys, [])
        self.assertIn("crop://", errs)

    def test_crop_non_numeric(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["crop://abc"], "events/e1/agent/")
        self.assertEqual(keys, [])
        self.assertIn("crop://abc", errs)

    def test_crop_negative(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["crop://-1"], "events/e1/agent/")
        self.assertIn("events/e1/agent/crop_-01.jpg", keys)
        self.assertEqual(errs, [])
    def test_unknown_scheme_ignored(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["upscale://1"], "events/e1/agent/")
        self.assertEqual(keys, [])
        self.assertEqual(errs, [])

    def test_snapshot_ignored(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["snapshot://"], "events/e1/agent/")
        self.assertEqual(keys, [])
        self.assertEqual(errs, [])

    def test_empty_list(self):
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs([], "events/e1/agent/")
        self.assertEqual(keys, [])
        self.assertEqual(errs, [])

    def test_frame_fallback_no_frames_dir(self):
        """Without frames_dir, frame:// should derive from parent of agent_dir."""
        mod = self._load_module()
        keys, errs = mod._resolve_image_refs(["frame://2"], "events/e1/agent/")
        self.assertIn("events/e1/frames/frame_002.jpg", keys)
        self.assertEqual(errs, [])


class SpawnValidationTests(unittest.TestCase):
    """Integration-style tests for spawn validation in AgentSessionWorkflow."""

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
        tools._TOOL_ACTIVITIES = {"spawn": object()}
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

        models = types.ModuleType("frigate_genai.models")
        class _SpawnTask:
            """Stub for frigate_genai.models.SpawnTask using manual validation."""
            task: str
            image_refs: list
            max_turns: int

            def __init__(self, **data):
                for k, v in data.items():
                    setattr(self, k, v)

            @classmethod
            def model_validate(cls, data: dict) -> "_SpawnTask":
                if not isinstance(data, dict):
                    raise TypeError("SpawnTask requires a dict")
                task = data.get("task")
                if not isinstance(task, str) or not task.strip():
                    raise ValueError("task must be a non-empty string")
                refs = data.get("image_refs", [])
                if refs is not None:
                    if not isinstance(refs, list):
                        raise ValueError("image_refs must be a list")
                    for r in refs:
                        if not isinstance(r, str):
                            raise ValueError(f"image_refs element must be a string, got {type(r).__name__}")
                turns = data.get("max_turns", 8)
                if not isinstance(turns, int) or turns < 1:
                    raise ValueError("max_turns must be a positive integer")
                return cls(task=task, image_refs=refs or [], max_turns=turns)
        models.SpawnTask = _SpawnTask

        subagent_mod = types.ModuleType("frigate_genai.workflows.subagent")
        class _FakeSubAgent:
            pass
        subagent_mod.SubAgentWorkflow = _FakeSubAgent
        work_subagent = types.ModuleType("frigate_genai.workflows")
        work_subagent.subagent = subagent_mod

        return {
            "temporalio": temporalio,
            "temporalio.exceptions": exceptions,
            "frigate_genai.config": config,
            "frigate_genai.activities.genai_turn": genai_turn,
            "frigate_genai.activities.tool_apply": tool_apply,
            "frigate_genai.tools": tools,
            "frigate_genai.tools.schemas": schemas,
            "frigate_genai.models": models,
            "frigate_genai.workflows": work_subagent,
            "frigate_genai.workflows.subagent": subagent_mod,
        }

    @staticmethod
    def _run_workflow(genai_activity, apply_activity):
        """Run one turn of an AgentSessionWorkflow with the given genai activity.
        Returns the workflow instance (with .applied_outcomes and .child_workflows)."""
        outcome = {"messages": []}
        workflow = _FakeWorkflow(genai_activity, apply_activity, outcome)
        modules = SpawnValidationTests._module_stubs(workflow, genai_activity, apply_activity)
        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_spawn_validation"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                session_input = {
                    "msg_path": "unused", "provider_path": "unused", "model": "gemini",
                    "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
                    "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
                }
                asyncio.run(module.AgentSessionWorkflow().run(session_input))
            finally:
                sys.modules.pop(module_name, None)
        return workflow

    def test_missing_task_field(self):
        """Spawn with missing 'task' field should produce a tool error."""
        genai_activity = object()
        apply_activity = object()

        def side_effect(activity, **kw):
            if activity is genai_activity:
                return {
                    "tool_calls": [
                        {"id": "spawn-call-1", "name": "spawn",
                         "args": {"tasks": [{"image_refs": ["crop://1"]}]}}
                    ]
                }
            if activity is apply_activity:
                return None
            raise AssertionError(f"Unexpected activity: {activity}")

        wf = _FakeWorkflow(genai_activity, apply_activity, {})

        async def mock_exec(activity, **kw):
            result = side_effect(activity, **kw)
            if activity is apply_activity:
                wf.applied_outcomes = kw["arg"]["outcomes"]
            return result
        wf.execute_activity = mock_exec
        wf._genai_activity = genai_activity
        wf._apply_activity = apply_activity

        modules = self._module_stubs(wf, genai_activity, apply_activity)
        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_spawn_missing_task"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                session_input = {
                    "msg_path": "unused", "provider_path": "unused", "model": "gemini",
                    "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
                    "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
                }
                asyncio.run(module.AgentSessionWorkflow().run(session_input))
            finally:
                sys.modules.pop(module_name, None)

        self.assertTrue(hasattr(wf, 'applied_outcomes') and wf.applied_outcomes is not None)
        spawn_outcome = next((o for o in wf.applied_outcomes if
                             any(m.get("content", "").startswith("Spawn task validation failed") for m in o.get("messages", []))), None)
        self.assertIsNotNone(spawn_outcome,
            msg="Expected tool error for missing 'task' field, got: " + str(wf.applied_outcomes))

    def test_image_refs_not_a_list(self):
        """Spawn with non-list image_refs should produce a tool error."""
        genai_activity = object()
        apply_activity = object()

        def side_effect(activity, **kw):
            if activity is genai_activity:
                return {
                    "tool_calls": [
                        {"id": "spawn-call-1", "name": "spawn",
                         "args": {"tasks": [{"task": "analyze", "image_refs": "not-a-list"}]}}
                    ]
                }
            if activity is apply_activity:
                return None
            raise AssertionError(f"Unexpected activity: {activity}")

        wf = _FakeWorkflow(genai_activity, apply_activity, {})
        async def mock_exec(activity, **kw):
            result = side_effect(activity, **kw)
            if activity is apply_activity:
                wf.applied_outcomes = kw["arg"]["outcomes"]
            return result
        wf.execute_activity = mock_exec
        wf._genai_activity = genai_activity
        wf._apply_activity = apply_activity

        modules = self._module_stubs(wf, genai_activity, apply_activity)
        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_spawn_bad_refs_type"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                session_input = {
                    "msg_path": "unused", "provider_path": "unused", "model": "gemini",
                    "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
                    "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
                }
                asyncio.run(module.AgentSessionWorkflow().run(session_input))
            finally:
                sys.modules.pop(module_name, None)

        spawn_outcome = next((o for o in wf.applied_outcomes if
                             any(m.get("content", "").startswith("Spawn task validation failed") for m in o.get("messages", []))), None)
        self.assertIsNotNone(spawn_outcome,
            msg="Expected tool error for non-list image_refs, got: " + str(wf.applied_outcomes))

    def test_valid_spawn_starts_child_workflows(self):
        """Valid spawn with valid refs should start child workflows."""
        genai_activity = object()
        apply_activity = object()

        def side_effect(activity, **kw):
            if activity is genai_activity:
                return {
                    "tool_calls": [
                        {"id": "spawn-call-1", "name": "spawn",
                         "args": {"tasks": [{"task": "analyze", "image_refs": ["crop://1"]}]}}
                    ]
                }
            if activity is apply_activity:
                return None
            raise AssertionError(f"Unexpected activity: {activity}")

        wf = _FakeWorkflow(genai_activity, apply_activity, {})
        async def mock_exec(activity, **kw):
            result = side_effect(activity, **kw)
            if activity is apply_activity:
                wf.applied_outcomes = kw["arg"]["outcomes"]
            return result
        wf.execute_activity = mock_exec
        wf._genai_activity = genai_activity
        wf._apply_activity = apply_activity

        modules = self._module_stubs(wf, genai_activity, apply_activity)
        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_spawn_valid"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                session_input = {
                    "msg_path": "unused", "provider_path": "unused", "model": "gemini",
                    "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
                    "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
                }
                asyncio.run(module.AgentSessionWorkflow().run(session_input))
            finally:
                sys.modules.pop(module_name, None)

        self.assertGreater(len(wf.child_workflows), 0,
            msg=f"Expected child workflows to be started, got: child_workflows={wf.child_workflows}, outcomes={wf.applied_outcomes}")
        spawn_success = next((o for o in wf.applied_outcomes if
                             any("Spawned 1 subagents" in m.get("content", "") for m in o.get("messages", []))), None)
        self.assertIsNotNone(spawn_success,
            msg="Expected 'Spawned' message for valid spawn")

    def test_invalid_ref_rejected(self):
        """Spawn with invalid crop ref should produce a tool error."""
        genai_activity = object()
        apply_activity = object()

        def side_effect(activity, **kw):
            if activity is genai_activity:
                return {
                    "tool_calls": [
                        {"id": "spawn-call-1", "name": "spawn",
                         "args": {"tasks": [{"task": "analyze", "image_refs": ["crop://bad"]}]}}
                    ]
                }
            if activity is apply_activity:
                return None
            raise AssertionError(f"Unexpected activity: {activity}")

        wf = _FakeWorkflow(genai_activity, apply_activity, {})
        async def mock_exec(activity, **kw):
            result = side_effect(activity, **kw)
            if activity is apply_activity:
                wf.applied_outcomes = kw["arg"]["outcomes"]
            return result
        wf.execute_activity = mock_exec
        wf._genai_activity = genai_activity
        wf._apply_activity = apply_activity

        modules = self._module_stubs(wf, genai_activity, apply_activity)
        with patch.dict(sys.modules, modules, clear=False):
            module_name = "_test_spawn_bad_ref"
            try:
                spec = importlib.util.spec_from_file_location(
                    module_name, Path(__file__).parents[1] / "workflows" / "agent_session.py"
                )
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                session_input = {
                    "msg_path": "unused", "provider_path": "unused", "model": "gemini",
                    "event_id": "event", "camera": "camera", "label": "person", "max_turns": 1,
                    "max_frames": 1, "start_time": 0, "end_time": 1, "genai_queue": "genai",
                }
                asyncio.run(module.AgentSessionWorkflow().run(session_input))
            finally:
                sys.modules.pop(module_name, None)

        ref_error = next((o for o in wf.applied_outcomes if
                         any("image_refs resolution failed" in m.get("content", "") for m in o.get("messages", []))), None)
        self.assertIsNotNone(ref_error,
            msg="Expected ref resolution error for bad crop ref")
        self.assertEqual(len(wf.child_workflows), 0,
            msg="No child workflows should be started on invalid refs")
if __name__ == "__main__":
    unittest.main()
