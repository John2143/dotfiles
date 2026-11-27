"""describe_scene: one schema-constrained call, and graceful degradation.

The fake client captures exactly what would be sent, so the request contract
(response_format, image count, temperature, max_tokens) is pinned here.
"""

import asyncio
import json
import os
import sys
import types
import unittest
from unittest.mock import patch

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities import describe  # noqa: E402

_JPEG = b"\xff\xd8\xff\xe0fake-jpeg"


class _FakeCompletions:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        content = reply if isinstance(reply, str) else json.dumps(reply)
        message = types.SimpleNamespace(content=content, tool_calls=None)
        usage = types.SimpleNamespace(prompt_tokens=11, completion_tokens=22)
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=message, finish_reason="stop")],
            usage=usage,
        )


class _FakeClient:
    def __init__(self, replies):
        self.chat = types.SimpleNamespace(completions=_FakeCompletions(replies))


def _arg(**overrides):
    arg = {
        "scene_id": "cam06-1000",
        "camera": "cam06",
        "keyframes": ["events/e1/frames/frame_000.jpg", "events/e1/frames/frame_004.jpg"],
        "crop": "events/e1/crop.jpg",
        "labels": ["person"],
        "camera_note": "Driveway and front of house.",
        "label_hints": {"person": "Describe clothing and what they carry."},
        "model": "ollama/gemma4:12b",
        "members": [
            {"id": "e1", "label": "person", "start_time": 1000.0, "end_time": 1010.0},
        ],
        "provider_path": "/unused",
    }
    arg.update(overrides)
    return arg


_GOOD = {
    "scene": "A person walks up the driveway and sets a parcel on the porch.",
    "subjects": [
        {"label": "person", "present": True, "count": 1, "details": "grey hoodie, dark trousers"},
        {"label": "package", "present": True, "count": 2, "details": "two small boxes"},
    ],
    "action": "delivers a parcel",
    "confidence": "high",
    "needs_review": False,
}


class DescribeSceneTests(unittest.TestCase):
    def _run(self, replies, arg=None):
        client = _FakeClient(replies)
        with patch.object(describe, "_resolve_provider", return_value=(client, "gemma4:12b")), \
                patch.object(describe, "_s3_get", return_value=_JPEG), \
                patch.object(describe, "load_json", return_value={"model": ["ollama/gemma4:12b"]}):
            result = asyncio.run(describe.run_describe_scene(arg or _arg()))
        return result, client

    def test_request_contract(self):
        result, client = self._run([_GOOD])
        self.assertEqual(len(client.chat.completions.calls), 1)
        call = client.chat.completions.calls[0]
        self.assertEqual(call["model"], "gemma4:12b")
        self.assertEqual(call["temperature"], 0)
        self.assertEqual(call["max_tokens"], 500)
        self.assertEqual(call["extra_body"], {"reasoning_effort": "none"})
        self.assertEqual(call["response_format"]["type"], "json_schema")
        self.assertEqual(call["response_format"]["json_schema"]["name"], "scene")
        self.assertIs(call["response_format"]["json_schema"]["strict"], True)

        # user message: 2 keyframes + the crop
        parts = call["messages"][-1]["content"]
        images = [p for p in parts if p["type"] == "image_url"]
        self.assertEqual(len(images), 3)
        self.assertTrue(images[0]["image_url"]["url"].startswith("data:image/jpeg;base64,"))

        # camera note and label hint reach the system message
        system = call["messages"][0]["content"]
        self.assertIn("Driveway and front of house.", system)
        self.assertIn("Describe clothing", system)

        self.assertEqual(result["confidence"], "high")
        self.assertFalse(result["needs_review"])
        self.assertIn("parcel", result["description"])
        self.assertIn("2 package", result["description"])
        self.assertEqual(result["model"], "ollama/gemma4:12b")
        self.assertEqual(result["prompt_tokens"], 11)

    def test_image_cap(self):
        keys = [f"events/e1/frames/frame_{i:03d}.jpg" for i in range(12)]
        _, client = self._run([_GOOD], _arg(keyframes=keys, crop=None))
        parts = client.chat.completions.calls[0]["messages"][-1]["content"]
        self.assertEqual(len([p for p in parts if p["type"] == "image_url"]), describe.MAX_IMAGES)

    def test_two_malformed_replies_degrade(self):
        result, client = self._run(["not json at all", "still { not json"])
        self.assertEqual(len(client.chat.completions.calls), 2)
        self.assertEqual(result["confidence"], "low")
        self.assertTrue(result["needs_review"])
        self.assertTrue(result["description"])

    def test_malformed_then_good(self):
        result, _ = self._run(["nope", _GOOD])
        self.assertEqual(result["confidence"], "high")
        self.assertFalse(result["needs_review"])

    def test_missing_required_key_is_malformed(self):
        broken = dict(_GOOD)
        del broken["needs_review"]
        result, _ = self._run([broken])
        self.assertEqual(result["confidence"], "low")
        self.assertTrue(result["needs_review"])

    def test_fenced_json_is_accepted(self):
        fenced = "```json\n" + json.dumps(_GOOD) + "\n```"
        result, _ = self._run([fenced])
        self.assertEqual(result["confidence"], "high")

    def test_response_format_rejection_falls_back(self):
        result, client = self._run([RuntimeError("400: response_format json_schema unsupported"), _GOOD])
        self.assertEqual(len(client.chat.completions.calls), 2)
        first, second = client.chat.completions.calls
        self.assertIn("response_format", first)
        self.assertNotIn("response_format", second)
        self.assertIn("JSON schema", second["messages"][0]["content"])
        self.assertEqual(result["confidence"], "high")

    def test_no_images(self):
        with patch.object(describe, "_resolve_provider", return_value=(_FakeClient([_GOOD]), "m")), \
                patch.object(describe, "_s3_get", return_value=None), \
                patch.object(describe, "load_json", return_value={"model": ["ollama/gemma4:12b"]}):
            result = asyncio.run(describe.run_describe_scene(_arg()))
        self.assertEqual(result["confidence"], "low")
        self.assertTrue(result["needs_review"])
        self.assertIn("No frames", result["description"])


if __name__ == "__main__":
    unittest.main()
