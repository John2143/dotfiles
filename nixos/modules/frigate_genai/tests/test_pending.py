"""PendingSceneWorkflow: the queue entity's ids and its model choice.

A scene can wait for days, so both must be pure and replay-stable."""

import os
import sys
import unittest
from pathlib import Path

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities.select_model import DEFAULT_MODEL  # noqa: E402
from frigate_genai.config import STRONG_MODEL  # noqa: E402
from frigate_genai.workflows.pending import (  # noqa: E402
    PendingSceneWorkflow,
    pending_ids,
    pending_model,
)

SCENE_ID = "cam05-1700000000"


class PendingIdsTests(unittest.TestCase):
    def test_plain_scene(self):
        self.assertEqual(
            pending_ids({"scene": {"scene_id": SCENE_ID}}),
            (f"pending-{SCENE_ID}", f"genai-{SCENE_ID}"),
        )

    def test_retry_gets_its_own_ids(self):
        self.assertEqual(
            pending_ids({"scene": {"scene_id": SCENE_ID}, "retry_of": SCENE_ID}),
            (f"pending-{SCENE_ID}-retry1", f"genai-{SCENE_ID}-retry1"),
        )


class PendingModelTests(unittest.TestCase):
    def test_explicit_model_wins(self):
        self.assertEqual(
            pending_model({"model": "ollama/other", "scene": {"priority": "must_keep"}}, True),
            "ollama/other",
        )

    def test_must_keep_with_vram_gets_the_strong_model(self):
        self.assertEqual(pending_model({"scene": {"priority": "must_keep"}}, True), STRONG_MODEL)

    def test_must_keep_without_vram_gets_the_default(self):
        self.assertEqual(pending_model({"scene": {"priority": "must_keep"}}, False), DEFAULT_MODEL)

    def test_low_priority_gets_the_default(self):
        self.assertEqual(pending_model({"scene": {"priority": "low_priority"}}, True), DEFAULT_MODEL)


class RegistrationTests(unittest.TestCase):
    def test_it_is_a_versioned_workflow(self):
        definition = getattr(PendingSceneWorkflow, "__temporal_workflow_definition")
        self.assertEqual(definition.name, "PendingSceneWorkflow")

    def test_it_auto_upgrades_so_long_waits_move_to_new_builds(self):
        # Pinned would strand a scene that waited through a deploy on the old
        # build, which then could never sunset.
        code = (Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                / "workflows" / "pending.py").read_text()
        self.assertIn("versioning_behavior=VersioningBehavior.AUTO_UPGRADE", code)


if __name__ == "__main__":
    unittest.main()
