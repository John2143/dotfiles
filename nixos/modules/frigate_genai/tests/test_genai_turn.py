"""Unit tests for the pure helpers behind the token-cost reductions:
- _retain_recent_images (image retention cap, genai_turn.py)
- _build_nudge (blank-turn nudge text, genai_turn.py)
- _build_image_tool_result (two-message image tool result, s3_helpers.py)

The activity itself requires S3/state, so these tests target the pure
functions only. They import the real modules (temporalio is available in the
sidecar env); no Temporal server is needed.
"""

import copy
import os
import sys
import unittest

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities.genai_turn import (
    _IMAGE_PLACEHOLDER,
    _build_nudge,
    _retain_recent_images,
)
from frigate_genai.s3_helpers import _build_image_tool_result


def _img_msg() -> dict:
    """User message with a single image part (one displayed frame set)."""
    return {
        "role": "user",
        "content": [{"type": "image_url", "image_url": {"url": "[[f0]]"}}],
    }


class RetainRecentImagesTests(unittest.TestCase):

    def test_keeps_all_at_cap(self):
        msgs = [_img_msg() for _ in range(8)]
        before = copy.deepcopy(msgs)
        out = _retain_recent_images(msgs)
        self.assertEqual(out, before)
        self.assertIsNot(out, msgs)  # new list, but nothing stripped

    def test_strips_older_than_last_8_image_messages(self):
        msgs = [_img_msg() for _ in range(10)] + [{"role": "user", "content": "text"}]
        out = _retain_recent_images(msgs)
        self.assertEqual(len(out), 11)
        for m in out[:2]:
            self.assertTrue(all(p.get("type") != "image_url" for p in m["content"]))
        for m in out[2:10]:
            self.assertTrue(any(p.get("type") == "image_url" for p in m["content"]))
        self.assertEqual(out[-1], {"role": "user", "content": "text"})

    def test_placeholder_when_message_left_partless(self):
        msgs = [_img_msg()] + [_img_msg() for _ in range(9)]
        out = _retain_recent_images(msgs)
        self.assertEqual(out[0]["content"], [{"type": "text", "text": _IMAGE_PLACEHOLDER}])

    def test_keeps_text_parts_when_images_stripped(self):
        img_plus_text = {
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": "[[x]]"}},
                {"type": "text", "text": "5 frames at high resolution"},
            ],
        }
        msgs = [_img_msg(), img_plus_text] + [_img_msg() for _ in range(8)]
        out = _retain_recent_images(msgs)
        self.assertEqual(out[1]["content"], [{"type": "text", "text": "5 frames at high resolution"}])

    def test_never_mutates_input(self):
        msgs = [_img_msg() for _ in range(10)]
        before = copy.deepcopy(msgs)
        _retain_recent_images(msgs)
        self.assertEqual(msgs, before)

    def test_tool_role_and_string_content_untouched(self):
        tool = {"role": "tool", "tool_call_id": "tc1", "content": "done"}
        text = {"role": "user", "content": "plain text"}
        msgs = [tool, text] + [_img_msg() for _ in range(9)]
        out = _retain_recent_images(msgs)
        self.assertEqual(out[0], tool)
        self.assertEqual(out[1], text)


class BuildNudgeTests(unittest.TestCase):

    def test_matches_legacy_text_with_tools(self):
        self.assertEqual(
            _build_nudge("", ["show_frame", "crop"]),
            "You must call a tool function. Do NOT output plain text. "
            "Choose from: show_frame, crop. Continue your investigation.")

    def test_empty_tool_list_uses_fallback(self):
        self.assertEqual(
            _build_nudge("", []),
            "You must call a tool function. Do NOT output plain text. "
            "Choose from: available tools. Continue your investigation.")

    def test_urgency_prefix_prepended(self):
        out = _build_nudge("Only 3 turns remaining! ", ["crop"])
        self.assertTrue(out.startswith("Only 3 turns remaining! "))


class GenaiTurnModuleNamespaceTests(unittest.TestCase):
    """Guard against NameError-in-hot-path regressions: every name the activity
    body references must be bound in the module namespace at import time."""

    def test_hot_path_names_bound(self):
        import frigate_genai.activities.genai_turn as gt

        for name in ("MAX_OUTPUT_TOKENS", "_retain_recent_images",
                     "_build_nudge", "ApplicationError",
                     "run_genai_turn_activity"):
            self.assertTrue(
                hasattr(gt, name),
                f"frigate_genai.activities.genai_turn missing {name!r}")


class BuildImageToolResultTests(unittest.TestCase):

    def test_two_message_shape(self):
        parts = [{"type": "image_url", "image_url": {"url": "[[f1]]"}}]
        out = _build_image_tool_result("tc-7", "Shown 1 frame.", parts)
        self.assertEqual(
            out[0], {"role": "tool", "tool_call_id": "tc-7", "content": "Shown 1 frame."})
        self.assertEqual(out[1]["role"], "user")
        self.assertEqual(out[1]["content"], parts)

    def test_label_appended_as_trailing_text_part(self):
        parts = [{"type": "image_url", "image_url": {"url": "[[f1]]"}}]
        out = _build_image_tool_result("tc-7", "s", parts, "Detection snapshot (640x360).")
        self.assertEqual(
            out[1]["content"],
            parts + [{"type": "text", "text": "Detection snapshot (640x360)."}])

    def test_no_label_adds_no_text_part(self):
        parts = [{"type": "image_url", "image_url": {"url": "[[f1]]"}}]
        out = _build_image_tool_result("tc-7", "s", parts)
        self.assertEqual(out[1]["content"], parts)
        self.assertTrue(all(p.get("type") != "text" for p in out[1]["content"]))

    def test_input_image_parts_not_mutated(self):
        parts = [{"type": "image_url", "image_url": {"url": "[[f1]]"}}]
        before = copy.deepcopy(parts)
        _build_image_tool_result("tc-7", "s", parts, "label")
        self.assertEqual(parts, before)


if __name__ == "__main__":
    unittest.main()
