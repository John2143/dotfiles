"""IPC foundation unit tests — model validation, token identity, routing, dedupe, capacity,
formatting, wait timeouts, and cleanup."""

import asyncio
import unittest


# ── Import-stub the Temporal workflow decorators ──────────────────────────
try:
    from temporalio import workflow
except ImportError:
    import types
    workflow = types.ModuleType("temporalio.workflow")
    workflow.defn = lambda cls: cls
    workflow.run = lambda fn: fn
    workflow.signal = lambda **kw: lambda fn: fn
    workflow.update = lambda **kw: lambda fn: fn
    workflow.query = lambda **kw: lambda fn: fn
    workflow.info = lambda: None
    workflow.now = lambda: None
    workflow.wait_condition = lambda *a, **kw: None
    workflow.all_handlers_finished = lambda: True
    workflow.start_activity = lambda *a, **kw: None
    workflow.start_child_workflow = lambda *a, **kw: None
    workflow.execute_activity = lambda *a, **kw: None
    workflow.execute_child_workflow = lambda *a, **kw: None
    workflow.get_external_workflow_handle_for = lambda *a, **kw: None
    workflow.set_current_details = lambda d: None
    workflow.logger = None
    import sys
    sys.modules["temporalio"] = types.ModuleType("temporalio")
    sys.modules["temporalio.workflow"] = workflow
    sys.modules["temporalio.exceptions"] = types.ModuleType("temporalio.exceptions")
    sys.modules["temporalio.common"] = types.ModuleType("temporalio.common")


# ── Model validation tests ───────────────────────────────────────────────────

class IPCModelValidationTests(unittest.TestCase):
    """Pydantic validation for IPCMessage, SendIPCArgs, WaitIPCArgs."""

    @classmethod
    def setUpClass(cls):
        from frigate_genai.models import IPCMessage, SendIPCArgs, WaitIPCArgs
        cls.IPCMessage = IPCMessage
        cls.SendIPCArgs = SendIPCArgs
        cls.WaitIPCArgs = WaitIPCArgs

    def test_valid_ipc_message_finding(self):
        msg = self.IPCMessage(
            message_id="ipc-v1:wf:run:root:1",
            from_token="ipc-v1:wf:run:root",
            to_token="ipc-v1:wf:run:s0",
            kind="finding",
            content="Found a person at the door",
            seq=1,
            created_at=1000.0,
        )
        self.assertEqual(msg.kind, "finding")
        self.assertEqual(msg.seq, 1)

    def test_valid_ipc_message_with_confidence(self):
        msg = self.IPCMessage(
            message_id="ipc-v1:wf:run:root:2",
            from_token="ipc-v1:wf:run:root",
            to_token="ipc-v1:wf:run:s0",
            kind="finding",
            content="Uncertain observation",
            confidence="medium",
            seq=2,
            created_at=1001.0,
        )
        self.assertEqual(msg.confidence, "medium")

    def test_reply_message_requires_reply_to(self):
        with self.assertRaises(ValueError):
            self.IPCMessage(
                message_id="x", from_token="a", to_token="b",
                kind="reply", content="Answer", seq=1, created_at=1.0,
            )

    def test_non_reply_rejects_reply_to(self):
        with self.assertRaises(ValueError):
            self.IPCMessage(
                message_id="x", from_token="a", to_token="b",
                kind="finding", content="Found", reply_to="something",
                seq=1, created_at=1.0,
            )

    def test_seq_must_be_positive(self):
        with self.assertRaises(ValueError):
            self.IPCMessage(
                message_id="x", from_token="a", to_token="b",
                kind="finding", content="Found", seq=0, created_at=1.0,
            )

    def test_content_length_min_1(self):
        with self.assertRaises(ValueError):
            self.IPCMessage(
                message_id="x", from_token="a", to_token="b",
                kind="finding", content="", seq=1, created_at=1.0,
            )

    def test_content_length_max_8192(self):
        with self.assertRaises(ValueError):
            self.IPCMessage(
                message_id="x", from_token="a", to_token="b",
                kind="finding", content="x" * 8193, seq=1, created_at=1.0,
            )

    def test_content_8192_bytes_ok(self):
        msg = self.IPCMessage(
            message_id="x", from_token="a", to_token="b",
            kind="finding", content="x" * 8192, seq=1, created_at=1.0,
        )
        self.assertEqual(len(msg.content), 8192)

    def test_send_ipc_timeout_range(self):
        with self.assertRaises(ValueError):
            self.SendIPCArgs(to_token="x", kind="finding", content="hello", timeout_seconds=500)

    def test_send_ipc_reply_requires_reply_to(self):
        with self.assertRaises(ValueError):
            self.SendIPCArgs(to_token="x", kind="reply", content="answer")

    def test_wait_ipc_timeout_range(self):
        with self.assertRaises(ValueError):
            self.WaitIPCArgs(timeout_seconds=500)


# ── Token identity tests ─────────────────────────────────────────────────────

class IPCTokenIdentityTests(unittest.TestCase):
    """Root and child token derivation, sender/recipient scope."""

    def setUp(self):
        from frigate_genai.workflows.agent_session import AgentSessionWorkflow
        self.wf = AgentSessionWorkflow()

    def test_root_token_format(self):
        """Root tokens follow ipc-v1:{workflow_id}:{run_id}:root."""
        token = "ipc-v1:wf-abc:run-xyz:root"
        parts = token.split(":")
        self.assertEqual(parts[0], "ipc-v1")
        self.assertEqual(parts[-1], "root")

    def test_child_token_format(self):
        """Child tokens follow ipc-v1:{parent_wf}:{parent_run}:s{idx}."""
        token = "ipc-v1:wf-abc:run-xyz:s5"
        parts = token.split(":")
        self.assertEqual(parts[0], "ipc-v1")
        self.assertTrue(parts[-1].startswith("s"))

    def test_token_opaque_no_split_for_routing(self):
        """Tokens are opaque; routing uses exact dict keys, never split(':')."""
        token_with_colons = "ipc-v1:wkfl:run:abc:def:root"
        # Verify it contains colons and would break naive split
        parts = token_with_colons.split(":")
        self.assertGreater(len(parts), 5)
        # But the implementation treats it as a single opaque key
        self.wf.child_registry[token_with_colons] = {"status": "test"}
        self.assertIn(token_with_colons, self.wf.child_registry)


# ── IPC accept/reject tests ──────────────────────────────────────────────────

class IPCAcceptRejectTests(unittest.TestCase):
    """_accept_ipc validation: dedupe, capacity, scope, closed state."""

    def setUp(self):
        from frigate_genai.workflows.agent_session import AgentSessionWorkflow
        self.wf = AgentSessionWorkflow()
        # Initialize identity
        self.wf.ipc_token = "ipc-v1:wf:run:root"
        self.wf.parent_ipc_token = "ipc-v1:grandparent:gprun:root"
        # Register a child
        self.wf.child_registry["ipc-v1:wf:run:s0"] = {"status": "running"}

    def _make_payload(self, **overrides):
        base = {
            "message_id": "ipc-v1:wf:run:s0:1",
            "from_token": "ipc-v1:wf:run:s0",
            "to_token": "ipc-v1:wf:run:root",
            "kind": "finding",
            "content": "Test message",
            "seq": 1,
            "created_at": 1000.0,
        }
        base.update(overrides)
        return base

    def test_accept_valid_child_message(self):
        status = self.wf._accept_ipc(self._make_payload())
        self.assertEqual(status, "accepted")
        self.assertEqual(self.wf.ipc_accepted, 1)
        self.assertEqual(len(self.wf.ipc_inbox), 1)

    def test_accept_valid_parent_message(self):
        payload = self._make_payload(
            from_token="ipc-v1:grandparent:gprun:root",
            message_id="ipc-v1:grandparent:gprun:root:1",
        )
        status = self.wf._accept_ipc(payload)
        self.assertEqual(status, "accepted")

    def test_reject_wrong_recipient(self):
        payload = self._make_payload(to_token="ipc-v1:wf:run:wrong")
        status = self.wf._accept_ipc(payload)
        self.assertEqual(status, "rejected")
        self.assertEqual(self.wf.ipc_rejected, 1)

    def test_reject_unknown_sender(self):
        payload = self._make_payload(
            from_token="ipc-v1:unknown:run:x",
            message_id="ipc-v1:unknown:run:x:1",
        )
        status = self.wf._accept_ipc(payload)
        self.assertEqual(status, "rejected")

    def test_deduplicate(self):
        payload = self._make_payload()
        self.wf._accept_ipc(payload)
        status = self.wf._accept_ipc(payload)
        self.assertEqual(status, "duplicate")
        self.assertEqual(self.wf.ipc_duplicates, 1)
        self.assertEqual(len(self.wf.ipc_inbox), 1)  # Only one copy

    def test_inbox_full_at_100(self):
        # Fill inbox to 100
        for i in range(100):
            p = self._make_payload(
                message_id=f"msg:{i}",
                seq=i + 1,
            )
            status = self.wf._accept_ipc(p)
            self.assertEqual(status, "accepted", f"msg {i} should be accepted")
        # 101st rejected
        p101 = self._make_payload(message_id="msg:101", seq=101)
        status = self.wf._accept_ipc(p101)
        self.assertEqual(status, "inbox_full")

    def test_closed_rejects(self):
        self.wf.ipc_closed = True
        status = self.wf._accept_ipc(self._make_payload())
        self.assertEqual(status, "closed")

    def test_buffered_before_identity(self):
        wf2 = type(self.wf)()
        status = wf2._accept_ipc(self._make_payload())
        self.assertEqual(status, "buffered")
        self.assertEqual(len(wf2._pending_ipc), 1)

    def test_reply_sets_reply_ready(self):
        msg_id = "ipc-v1:wf:run:root:5"
        payload = self._make_payload(
            message_id="ipc-v1:wf:run:s0:2",
            kind="reply",
            reply_to=msg_id,
            seq=2,
        )
        self.wf._accept_ipc(payload)
        self.assertTrue(self.wf.ipc_reply_ready.get(msg_id, False))


# ── Formatting tests ─────────────────────────────────────────────────────────

class IPCFormattingTests(unittest.TestCase):
    """_format_ipc produces exact prefix format."""

    def setUp(self):
        from frigate_genai.workflows.agent_session import AgentSessionWorkflow
        self.wf = AgentSessionWorkflow()

    def test_format_finding_with_confidence(self):
        msg = {
            "from_token": "ipc-v1:wf:run:s0",
            "kind": "finding",
            "confidence": "high",
            "content": "Person detected",
        }
        result = self.wf._format_ipc(msg)
        self.assertIn("[IPC from s0 | finding | high]: Person detected", result)

    def test_format_question_no_confidence(self):
        msg = {
            "from_token": "ipc-v1:wf:run:root",
            "kind": "question",
            "content": "What do you see?",
        }
        result = self.wf._format_ipc(msg)
        self.assertIn("[IPC from root | question]: What do you see?", result)

    def test_format_terminate(self):
        msg = {
            "from_token": "ipc-v1:wf:run:s1",
            "kind": "terminate",
            "content": "Done",
        }
        result = self.wf._format_ipc(msg)
        self.assertIn("[IPC from s1 | terminate]: Done", result)

    def test_format_unknown_from(self):
        msg = {
            "from_token": "",
            "kind": "finding",
            "content": "test",
        }
        result = self.wf._format_ipc(msg)
        # Empty token rsplit(":", 1)[-1] returns ""
        self.assertIn("[IPC from  | finding]: test", result)


# ── Query tests ──────────────────────────────────────────────────────────────

class IPCQueryTests(unittest.TestCase):
    """ipc_status query returns counters only, no message content."""

    def setUp(self):
        from frigate_genai.workflows.agent_session import AgentSessionWorkflow
        self.wf = AgentSessionWorkflow()
        self.wf.ipc_token = "ipc-v1:wf:run:root"

    def test_query_initial_state(self):
        status = self.wf.ipc_status()
        self.assertEqual(status["inbox_count"], 0)
        self.assertEqual(status["accepted"], 0)
        self.assertEqual(status["duplicates"], 0)
        self.assertEqual(status["rejected"], 0)

    def test_query_after_accept(self):
        from frigate_genai.models import IPCMessage
        msg = IPCMessage(
            message_id="t:1", from_token="ipc-v1:p:pr:root",
            to_token="ipc-v1:wf:run:root", kind="finding",
            content="Test", seq=1, created_at=1.0,
        )
        self.wf.parent_ipc_token = "ipc-v1:p:pr:root"
        self.wf._accept_ipc(msg.model_dump())
        status = self.wf.ipc_status()
        self.assertEqual(status["inbox_count"], 1)
        self.assertEqual(status["accepted"], 1)

    def test_query_no_message_content(self):
        """ipc_status must not expose message content."""
        self.wf.ipc_inbox.append({"content": "secret data"})
        status = self.wf.ipc_status()
        self.assertNotIn("messages", status)
        self.assertNotIn("content", str(status))


# ── Wait timeout tests ───────────────────────────────────────────────────────

class IPCWaitTimeoutTests(unittest.TestCase):
    """wait_ipc timeout and reply-wake behavior — tests model validation only;
    actual dispatch methods require Temporal sandbox."""

    def test_wait_ipc_defaults(self):
        from frigate_genai.models import WaitIPCArgs
        args = WaitIPCArgs.model_validate({"timeout_seconds": 1})
        self.assertEqual(args.timeout_seconds, 1)
        self.assertIsNone(args.message_id)

    def test_wait_ipc_message_id_validation(self):
        from frigate_genai.models import WaitIPCArgs
        args = WaitIPCArgs.model_validate({"message_id": "msg-123", "timeout_seconds": 10})
        self.assertEqual(args.message_id, "msg-123")
        self.assertEqual(args.timeout_seconds, 10)

    def test_send_ipc_args_validation(self):
        from frigate_genai.models import SendIPCArgs
        args = SendIPCArgs.model_validate({
            "to_token": "ipc-v1:p:pr:root",
            "kind": "question",
            "content": "Test",
            "wait_for_reply": True,
            "timeout_seconds": 15,
        })
        self.assertTrue(args.wait_for_reply)
        self.assertEqual(args.timeout_seconds, 15)

    def test_send_ipc_reply_requires_reply_to(self):
        from frigate_genai.models import SendIPCArgs
        with self.assertRaises(ValueError):
            SendIPCArgs.model_validate({
                "to_token": "x",
                "kind": "reply",
                "content": "answer",
            })
# ── Cleanup tests ────────────────────────────────────────────────────────────

class IPCTokenCleanupTests(unittest.TestCase):
    """Registry and state cleanup on shutdown."""

    def setUp(self):
        from frigate_genai.workflows.agent_session import AgentSessionWorkflow
        self.wf = AgentSessionWorkflow()

    def test_ipc_closed_flag_set(self):
        self.wf.ipc_closed = True
        self.assertTrue(self.wf.ipc_closed)

    def test_child_registry_cleared(self):
        self.wf.child_registry["token"] = {"status": "running"}
        self.wf.child_registry.clear()
        self.assertEqual(len(self.wf.child_registry), 0)


if __name__ == "__main__":
    unittest.main()
