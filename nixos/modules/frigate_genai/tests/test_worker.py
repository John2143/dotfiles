"""Regression: worker mode registration matches the single-call pipeline —
the dispatcher owns DrainWorkflow and intake, the triggers worker owns
GenAIWorkflow, the LLM queue owns the describe activities, and the agent-loop
modes are gone.

Regression: SIGTERM drains Temporal workers instead of being ignored by PID 1
(_install_stop_signal_handlers, _run_until_stopped)."""

import asyncio
import os
import signal
import sys
import unittest
from pathlib import Path

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.worker import _install_stop_signal_handlers, _run_until_stopped

# Upper bound on any wait; only reached when a regression would hang.
_HANG_TIMEOUT = 3.0


class WorkerModeRegistrationTests(unittest.TestCase):
    def setUp(self):
        self.code = (Path(__file__).parent.parent / "worker.py").read_text()

    def test_dispatcher_owns_drain_and_intake(self):
        block = _block_after(self.code, "if mode == \"dispatcher\":", 20)
        self.assertIn("DrainWorkflow", block)
        for activity in ("collect_scenes_activity", "gate_status_activity",
                         "finish_drain_activity", "genai_paused_activity",
                         "label_only_activity"):
            self.assertIn(activity, block, f"{activity} missing from the dispatcher worker")

    def test_triggers_owns_the_description_workflow(self):
        block = _block_after(self.code, "if mode == \"triggers\":", 12)
        self.assertIn("GenAIWorkflow", block)
        self.assertNotIn("AgentSessionWorkflow", block)
        # record_result must be callable on the workflow's own queue.
        core = _block_after(self.code, "core_activities = [", 8)
        self.assertIn("record_result_activity", core)

    def test_llm_queue_owns_the_model_activities(self):
        block = _block_after(self.code, "elif mode == \"genai-ollama\":", 12)
        for activity in ("run_describe_scene", "pick_keyframes_activity", "crop_detection_activity"):
            self.assertIn(activity, block)

    def test_cloud_and_agent_modes_are_gone(self):
        for gone in ("genai-gemini", "AgentSessionWorkflow", "SubAgentWorkflow",
                     "run_genai_turn_activity", "init_agent_state_activity"):
            self.assertNotIn(gone, self.code)


def _block_after(code: str, marker: str, line_count: int) -> str:
    lines = code.splitlines()
    for i, line in enumerate(lines):
        if marker in line:
            return "\n".join(lines[i : i + line_count])
    raise AssertionError(f"Marker {marker!r} not found")


class _FakeWorker:
    """Stand-in for temporalio.worker.Worker with its shutdown semantics:
    shutdown() stops polling (ends run()) and then waits for run() to return
    normally. On a worker whose run() raised it therefore never completes, as
    temporalio's shutdown-complete event is only set at the end of a clean run."""

    def __init__(self, crash: bool = False):
        self._crash = crash
        self._poll_stopped = asyncio.Event()
        self.running = asyncio.Event()
        self.run_returned = asyncio.Event()
        self.shutdown_calls = 0

    async def run(self) -> None:
        if self._crash:
            raise RuntimeError("boom")
        self.running.set()
        await self._poll_stopped.wait()
        self.run_returned.set()

    async def shutdown(self) -> None:
        self.shutdown_calls += 1
        self._poll_stopped.set()
        await self.run_returned.wait()


class GracefulShutdownTests(unittest.TestCase):
    """async_main runs its workers through _run_until_stopped with the event
    from _install_stop_signal_handlers; SIGTERM must end in a drained exit."""

    async def _within(self, aw, what: str, timeout: float = _HANG_TIMEOUT):
        try:
            return await asyncio.wait_for(aw, timeout)
        except TimeoutError:
            self.fail(f"{what} did not finish within {timeout}s")

    def test_stop_shuts_down_every_running_worker_once(self):
        async def scenario():
            workers = [_FakeWorker(), _FakeWorker()]
            stop = asyncio.Event()
            task = asyncio.create_task(_run_until_stopped(workers, stop))
            for w in workers:
                await self._within(w.running.wait(), "worker start")
            self.assertFalse(task.done(), "returned before stop was set")
            self.assertEqual([w.shutdown_calls for w in workers], [0, 0])

            stop.set()
            await self._within(task, "_run_until_stopped after stop")
            self.assertEqual([w.shutdown_calls for w in workers], [1, 1])
            self.assertTrue(all(w.run_returned.is_set() for w in workers),
                            "returned before every worker's run() drained")

        asyncio.run(scenario())

    def test_crashed_worker_error_propagates_without_shutting_it_down(self):
        """No stop signal: the crash alone ends the run. The healthy worker is
        drained; the crashed one is skipped, since shutdown() on it never
        returns and would wedge the pod until SIGKILL instead of restarting."""
        async def scenario():
            healthy, crashed = _FakeWorker(), _FakeWorker(crash=True)
            with self.assertRaisesRegex(RuntimeError, "^boom$"):
                await self._within(
                    _run_until_stopped([healthy, crashed], asyncio.Event()),
                    "_run_until_stopped after a worker crash",
                )
            self.assertEqual(healthy.shutdown_calls, 1)
            self.assertTrue(healthy.run_returned.is_set())
            self.assertEqual(crashed.shutdown_calls, 0)

        asyncio.run(scenario())

    def test_no_workers_waits_for_stop(self):
        """mqtt-listener and dashboard modes run no Temporal worker: the call
        must keep the process alive until stop, then return."""
        async def scenario():
            stop = asyncio.Event()
            task = asyncio.create_task(_run_until_stopped([], stop))
            for _ in range(5):
                await asyncio.sleep(0)
            self.assertFalse(task.done(), "returned without a stop signal")

            stop.set()
            await self._within(task, "_run_until_stopped([]) after stop")

        asyncio.run(scenario())

    def test_sigterm_and_sigint_set_stop_event(self):
        """Delivers a real signal to this process. A fallback Python handler is
        installed first so a missing loop handler fails the test rather than
        killing the test runner; prior handlers are restored afterwards."""
        delivered: list[int] = []

        async def scenario(sig: int):
            loop = asyncio.get_running_loop()
            stop = _install_stop_signal_handlers(loop)
            try:
                self.assertFalse(stop.is_set())
                os.kill(os.getpid(), sig)
                await self._within(stop.wait(), f"stop event after {sig.name}", timeout=1.0)
            finally:
                for s in (signal.SIGTERM, signal.SIGINT):
                    loop.remove_signal_handler(s)

        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig.name):
                previous = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
                try:
                    for s in previous:
                        signal.signal(s, lambda signum, frame: delivered.append(signum))
                    asyncio.run(scenario(sig))
                finally:
                    for s, handler in previous.items():
                        signal.signal(s, handler)
                self.assertEqual(delivered, [], "signal bypassed the loop handler")


if __name__ == "__main__":
    unittest.main()
