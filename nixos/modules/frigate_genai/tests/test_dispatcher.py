"""Dispatcher: intake over a recorded Frigate page, the seat gate, and the
drain starter. All network and S3 I/O is patched; the logic under test is the
classification, the merge, the persisted state and the fail-closed gate."""

import asyncio
import json
import os
import sys
import unittest
from unittest.mock import patch

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities import dispatcher, lifecycle  # noqa: E402

NOW = 1_700_000_000.0


def ev(event_id, camera, label, start, duration=10.0, score=0.9, zones=(), box=None):
    return {
        "id": event_id,
        "camera": camera,
        "label": label,
        "start_time": NOW - 3600 + start,
        "end_time": NOW - 3600 + start + duration,
        "top_score": score,
        "entered_zones": list(zones),
        "data": {"box": box or [0.4, 0.4, 0.2, 0.2], "top_score": score},
    }


FIXTURE = [
    ev("audio1", "cam05", "speech", 0),
    ev("car-road", "cam02", "car", 10, zones=["in_court"]),
    ev("street-pass", "cam01", "person", 20, duration=12, zones=["road_speed_zone"]),
    ev("pkg1", "cam05", "package", 30, duration=8),
    ev("person1", "cam06", "person", 40, duration=20, zones=["front_driveway"]),
    ev("cat1", "cam04", "cat", 120, duration=10),
    ev("cat2", "cam04", "cat", 200, duration=10),
]


class CollectScenesTests(unittest.TestCase):
    def _collect(self, events=FIXTURE, done=None, watermark=0.0):
        saved = {"done": None, "watermark": None, "spend": None}

        def fake_save_done(ids, now):
            saved["done"] = dict(ids)
            return len(ids)

        def fake_save_watermark(value):
            saved["watermark"] = value

        def fake_save_spend(counts, day=None):
            saved["spend"] = dict(counts)

        with patch.object(dispatcher, "fetch_events", return_value=events), \
                patch.object(dispatcher, "fetch_zone_polygons", return_value={}), \
                patch.object(dispatcher, "load_done", return_value=dict(done or {})), \
                patch.object(dispatcher, "load_watermark", return_value=watermark), \
                patch.object(dispatcher, "save_done", side_effect=fake_save_done), \
                patch.object(dispatcher, "save_watermark", side_effect=fake_save_watermark), \
                patch.object(dispatcher, "load_spend", return_value={}), \
                patch.object(dispatcher, "save_spend", side_effect=fake_save_spend):
            result = asyncio.run(dispatcher.collect_scenes_activity(NOW))
        return result, saved

    def test_scenes_and_skips(self):
        result, saved = self._collect()
        scene_ids = {s["scene_id"] for s in result["scenes"]}
        # package + person, and the two cam04 cats merged into one scene
        self.assertEqual(len(result["scenes"]), 3, scene_ids)
        self.assertIn("cam04-%d" % (NOW - 3600 + 120), scene_ids)  # cat1+cat2 merged
        self.assertIn("cam05-%d" % (NOW - 3600 + 30), scene_ids)

        reasons = {item["id"]: item["reason"] for item in result["labelled"]}
        self.assertEqual(reasons, {
            "audio1": "audio",
            "car-road": "vehicle-outside-zones",
            "street-pass": "street-pass-by",
        })
        self.assertEqual(saved["spend"]["skipped"], 3)
        self.assertEqual(saved["spend"]["scenes"], 3)
        self.assertIn("audio1", saved["done"])
        self.assertNotIn("person1", saved["done"])

    def test_package_scene_is_ordered_first(self):
        result, _ = self._collect()
        # P1 (package, cat, wildlife) before P2 (person).
        self.assertEqual(result["scenes"][0]["labels"], ["package"])
        self.assertEqual(result["scenes"][1]["labels"], ["cat"])
        self.assertEqual(result["scenes"][2]["labels"], ["person"])

    def test_done_ids_are_not_reprocessed(self):
        result, saved = self._collect(done={"person1": NOW})
        ids = {m["id"] for scene in result["scenes"] for m in scene["members"]}
        self.assertNotIn("person1", ids)
        self.assertIn("pkg1", ids)
        # The index keeps handled ids (it is pruned by age, not by success).
        self.assertIn("person1", saved["done"])

    def test_watermark_advances(self):
        _, saved = self._collect()
        self.assertEqual(saved["watermark"], max(e["end_time"] for e in FIXTURE))

    def test_still_there_repeat_is_dropped(self):
        events = [
            ev("cat1", "cam04", "cat", 0, box=[0.40, 0.40, 0.2, 0.2]),
            ev("cat2", "cam04", "cat", 300, box=[0.41, 0.41, 0.2, 0.2]),
        ]
        result, saved = self._collect(events=events)
        self.assertEqual(len(result["scenes"]), 1, result["scenes"])
        self.assertEqual(result["scenes"][0]["members"][0]["id"], "cat1")
        self.assertEqual(saved["spend"]["still_there"], 1)


class ZonePolygonFetchTests(unittest.TestCase):
    def test_parses_only_household_zones(self):
        config = {"cameras": {
            "cam06": {"zones": {
                "front_driveway": {"coordinates": "0,0,1,0,1,1,0,1"},
                "house": {"coordinates": "0,0,0.2,0,0.2,0.2"},
            }},
            "cam02": {"zones": {
                "in_court": {"coordinates": "0,0,1,0,1,1,0,1"},
                "in_back_yard": {"coordinates": "0.1,0.1,0.4,0.1,0.4,0.4"},
            }},
        }}

        class _Resp:
            def read(self):
                return json.dumps(config).encode()

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        with patch.object(dispatcher.urllib.request, "urlopen", return_value=_Resp()):
            polygons = dispatcher.fetch_zone_polygons()

        self.assertEqual(set(polygons), {"cam06", "cam02"})
        self.assertIn("front_driveway", polygons["cam06"])
        # cam02's in_court is the road, so it is never part of the household map.
        self.assertNotIn("in_court", polygons["cam02"])
        self.assertEqual(polygons["cam06"]["front_driveway"][2], (1.0, 1.0))

    def test_fetch_failure_disables_zone_skips(self):
        with patch.object(dispatcher.urllib.request, "urlopen", side_effect=OSError("boom")):
            self.assertEqual(dispatcher.fetch_zone_polygons(), {})


class GateTests(unittest.TestCase):
    def _gate(self, values):
        def fake_query(expr, timeout=10.0):
            for key, value in values.items():
                if key in expr:
                    return value
            return None

        with patch.object(dispatcher, "_query", side_effect=fake_query), \
                patch.object(dispatcher.time, "time", return_value=NOW):
            return dispatcher.gate_status()

    def test_open_when_idle_with_vram(self):
        status = self._gate({
            "gate_open": 1.0, "mtime": NOW - 60, "free_vram": 13000.0, "loaded": 0.0,
        })
        self.assertTrue(status["open"])
        self.assertFalse(status["strong_ok"])

    def test_strong_model_threshold(self):
        status = self._gate({
            "gate_open": 1.0, "mtime": NOW - 60, "free_vram": 22000.0, "loaded": 1.0,
        })
        self.assertTrue(status["open"])
        self.assertTrue(status["strong_ok"])

    def test_stale_file_closes(self):
        status = self._gate({
            "gate_open": 1.0, "mtime": NOW - 301, "free_vram": 22000.0, "loaded": 0.0,
        })
        self.assertFalse(status["open"])
        self.assertIn("stale", status["reason"])

    def test_missing_series_closes(self):
        status = self._gate({"gate_open": 1.0, "mtime": NOW - 10})
        self.assertFalse(status["open"])
        self.assertIn("missing", status["reason"])

    def test_low_vram_closes(self):
        status = self._gate({
            "gate_open": 1.0, "mtime": NOW - 10, "free_vram": 9000.0, "loaded": 0.0,
        })
        self.assertFalse(status["open"])
        self.assertIn("free_vram", status["reason"])

    def test_seated_closes(self):
        status = self._gate({
            "gate_open": 0.0, "mtime": NOW - 10, "free_vram": 22000.0, "loaded": 0.0,
        })
        self.assertFalse(status["open"])


class SkipLabelTests(unittest.TestCase):
    def test_skip_writes_one_line_reason(self):
        seen = []
        with patch.object(lifecycle, "update_event_description",
                          side_effect=lambda eid, text: seen.append((eid, text)) or True):
            asyncio.run(lifecycle.label_only_activity("evt-1", "street-pass-by"))
        self.assertEqual(seen, [("evt-1", "Skipped: street-pass-by")])


class _FakeClient:
    def __init__(self, error=None):
        self.error = error
        self.starts = []

    async def start_workflow(self, *args, **kwargs):
        self.starts.append((args, kwargs))
        if self.error:
            raise self.error


class DrainStartTests(unittest.TestCase):
    def _start(self, client):
        with patch("frigate_genai.worker._temporal_client", client):
            asyncio.run(__import__("frigate_genai.worker", fromlist=["x"])._start_drain("/p", "/pr"))
        return client

    def test_starts_when_idle(self):
        client = self._start(_FakeClient())
        self.assertEqual(len(client.starts), 1)
        args, kwargs = client.starts[0]
        self.assertEqual(kwargs["id"], "drain-current")
        self.assertEqual(args[1]["prompts_path"], "/p")

    def test_already_running_is_not_an_error(self):
        self._start(_FakeClient(error=Exception("workflow already started")))


if __name__ == "__main__":
    unittest.main()
