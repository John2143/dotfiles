"""Regression: SubAgentWorkflow init_subagent_state_activity is registered
on model-specific workers, not only the base TASK_QUEUE."""

import unittest
from pathlib import Path


class WorkerActivityRegistrationTests(unittest.TestCase):
    def test_init_subagent_state_on_gemini_and_ollama_workers(self):
        """init_subagent_state_activity must appear in both genai-gemini
        and genai-ollama worker activity lists — SubAgentWorkflow runs on
        the model-specific queue with no explicit task_queue override."""
        source = Path(__file__).parent.parent / "worker.py"
        code = source.read_text()

        # Gemini mode block: find the Worker construction that runs on
        # GEMINI_TASK_QUEUE and verify its activity list.
        gemini_block = _block_after(code, "task_queue=GEMINI_TASK_QUEUE,", 20)
        self.assertIn(
            "init_subagent_state_activity",
            gemini_block,
            "init_subagent_state_activity missing from genai-gemini worker",
        )

        # Same for Ollama.
        ollama_block = _block_after(code, "task_queue=OLLAMA_TASK_QUEUE,", 20)
        self.assertIn(
            "init_subagent_state_activity",
            ollama_block,
            "init_subagent_state_activity missing from genai-ollama worker",
        )


def _block_after(code: str, marker: str, line_count: int) -> str:
    lines = code.splitlines()
    for i, line in enumerate(lines):
        if marker in line:
            return "\n".join(lines[i : i + line_count])
    raise AssertionError(f"Marker {marker!r} not found")


if __name__ == "__main__":
    unittest.main()
