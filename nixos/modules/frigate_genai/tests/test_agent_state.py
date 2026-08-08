"""Unit tests for the quick-pass label prompts (high-volume labels like car).

Quick labels get a bounded agent session (max_turns=MAX_TURNS_QUICK in
genai.py) and a fast-conclusion system prompt instead of the two-phase
forensic deep dive. These tests pin the prompt contract so the quick pass
can't silently regress into the expensive behavior.
"""

import os
import sys
import unittest

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities.agent_state import _QUICK_PASS_PROMPT
from frigate_genai.config import MAX_TURNS_QUICK, QUICK_LABELS


class QuickPassTests(unittest.TestCase):

    def test_car_is_a_quick_label(self):
        self.assertIn("car", QUICK_LABELS)

    def test_quick_turn_cap_is_small(self):
        self.assertLessEqual(MAX_TURNS_QUICK, 3)

    def test_quick_prompt_instructs_fast_conclusion(self):
        self.assertIn("2-3 tool calls", _QUICK_PASS_PROMPT)
        self.assertIn("set_description()", _QUICK_PASS_PROMPT)

    def test_quick_prompt_omits_two_phase_deep_dive(self):
        self.assertNotIn("TWO PHASES", _QUICK_PASS_PROMPT)
        self.assertNotIn("PHASE 1", _QUICK_PASS_PROMPT)

    def test_quick_prompt_bans_expensive_tools(self):
        for banned in ("never upscale", "never transcode", "never spawn"):
            self.assertIn(banned, _QUICK_PASS_PROMPT)


if __name__ == "__main__":
    unittest.main()
