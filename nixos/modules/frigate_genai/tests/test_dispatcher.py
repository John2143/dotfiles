"""Dispatcher: intake over a recorded Frigate page, the seat gate, admission,
the model release and the drain starter. All network and S3 I/O is patched;
the logic under test is the classification, the merge, the persisted state,
the queueing and the fail-closed gate."""

import asyncio
import json
import os
import sys
import unittest
from unittest.mock import patch

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError

from frigate_genai.activities import dispatcher, lifecycle  # noqa: E402
from frigate_genai.intake import Scene  # noqa: E402

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

PKG_SCENE = "cam05-%d" % (NOW - 3600 + 30)
CAT_SCENE = "cam04-%d" % (NOW - 3600 + 120)
PERSON_SCENE = "cam06-%d" % (NOW - 3600 + 40)


class _FakeStartClient:
    """Records the PendingSceneWorkflow starts the collect activity makes."""

    def __init__(self, error=None):
        self.error = error
        self.starts = []

    async def start_workflow(self, workflow, input_data, **kwargs):
        if self.error:
            raise self.error
        self.starts.append((workflow, input_data, kwargs))

    def ids(self):
        return [kwargs["id"] for _, _, kwargs in self.starts]


class CollectScenesTests(unittest.TestCase):
    def _collect(self, events=FIXTURE, done=None, watermark=NOW - 3600,
                 in_progress=(), last_scenes=None, client=None, label_ok=True):
        saved = {"done": None, "watermark": None, "spend": None,
                 "fetch_after": None, "last_scenes": None, "labelled": []}
        client = client or _FakeStartClient()

        def fake_fetch(after, before):
            saved["fetch_after"] = after
            return list(events)

        def fake_label(event_id, text):
            saved["labelled"].append((event_id, text))
            return label_ok

        with patch.object(dispatcher, "fetch_events", side_effect=fake_fetch), \
                patch.object(dispatcher, "fetch_in_progress_starts",
                             return_value=list(in_progress)), \
                patch.object(dispatcher, "fetch_zone_polygons", return_value={}), \
                patch.object(dispatcher, "load_done", return_value=dict(done or {})), \
                patch.object(dispatcher, "load_watermark", return_value=watermark), \
                patch.object(dispatcher, "load_last_scenes", return_value=dict(last_scenes or {})), \
                patch.object(dispatcher, "save_last_scenes",
                             side_effect=lambda scenes: saved.__setitem__("last_scenes", dict(scenes))), \
                patch.object(dispatcher, "save_done",
                             side_effect=lambda ids, now: saved.__setitem__("done", dict(ids))), \
                patch.object(dispatcher, "save_watermark",
                             side_effect=lambda value: saved.__setitem__("watermark", value)), \
                patch.object(dispatcher, "load_spend", return_value={}), \
                patch.object(dispatcher, "save_spend",
                             side_effect=lambda counts, day=None: saved.__setitem__("spend", dict(counts))), \
                patch.object(dispatcher, "update_event_description", side_effect=fake_label), \
                patch.object(dispatcher.activity, "client", return_value=client), \
                patch.object(dispatcher.activity, "heartbeat", lambda *a, **k: None):
            result = asyncio.run(dispatcher.collect_scenes_activity(
                {"now": NOW, "prompts_path": "/p", "provider_path": "/pr"}))
        return result, saved, client

    def test_scenes_are_enqueued_in_priority_order(self):
        result, saved, client = self._collect()
        self.assertEqual(client.ids(),
                         [f"pending-{PKG_SCENE}", f"pending-{CAT_SCENE}",
                          f"pending-{PERSON_SCENE}"])
        expected = [("p0", "package"), ("p0", "cat"), ("p1", "person")]
        for (_, _, kwargs), (rank, labels) in zip(client.starts, expected):
            attrs = kwargs["search_attributes"]
            self.assertEqual(attrs.get(dispatcher._SEARCH_SCENE_PRIORITY), rank)
            self.assertEqual(attrs.get(dispatcher._SEARCH_SCENE_LABELS), labels)
            self.assertEqual(kwargs["task_queue"], dispatcher.DISPATCHER_TASK_QUEUE)
            self.assertIs(kwargs["id_reuse_policy"], WorkflowIDReusePolicy.REJECT_DUPLICATE)
        self.assertEqual(result["enqueued"], 3)
        self.assertEqual(result["duplicates"], 0)

    def test_scene_input_matches_the_description_workflow(self):
        _, _, client = self._collect()
        _, input_data, _ = client.starts[0]
        self.assertEqual(input_data["event_id"], "pkg1")
        self.assertEqual(input_data["camera"], "cam05")
        self.assertEqual(input_data["label"], "package")
        self.assertEqual(input_data["prompts_path"], "/p")
        self.assertEqual(input_data["provider_path"], "/pr")
        self.assertEqual(input_data["scene"]["scene_id"], PKG_SCENE)
        self.assertEqual(input_data["scene"]["primary"]["id"], "pkg1")

    def test_skip_labels_are_written(self):
        result, saved, _ = self._collect()
        self.assertEqual(sorted(saved["labelled"]), [
            ("audio1", "Skipped: audio"),
            ("car-road", "Skipped: vehicle-outside-zones"),
            ("street-pass", "Skipped: street-pass-by"),
        ])
        self.assertEqual(result["skipped"], 3)
        self.assertEqual(result["label_failures"], 0)

    def test_old_skips_are_handled_but_not_labelled(self):
        events = FIXTURE + [ev("old-audio", "cam05", "speech", -25 * 3600)]
        result, saved, _ = self._collect(events=events)
        self.assertNotIn("old-audio", [eid for eid, _ in saved["labelled"]])
        self.assertIn("old-audio", saved["done"])
        self.assertEqual(result["skipped"], 4)

    def test_failed_label_is_counted_not_raised(self):
        result, _, _ = self._collect(label_ok=False)
        self.assertEqual(result["label_failures"], 3)
        self.assertEqual(result["enqueued"], 3)

    def test_every_handled_event_is_marked_done(self):
        result, saved, _ = self._collect()
        for event in FIXTURE:
            self.assertIn(event["id"], saved["done"], event["id"])
        # The enqueued scenes are covered too, so the next drain (whose
        # watermark may sit up to 24 h back) does not re-enqueue them.
        self.assertEqual(len(saved["done"]), len(FIXTURE))

    def test_done_ids_are_not_reprocessed(self):
        result, saved, client = self._collect(done={"person1": NOW})
        ids = [input_data["event_id"] for _, input_data, _ in client.starts]
        self.assertNotIn("person1", ids)
        self.assertIn("pkg1", ids)
        # The index keeps handled ids (it is pruned by age, not by success).
        self.assertIn("person1", saved["done"])

    def test_watermark_advances_to_now(self):
        _, saved, _ = self._collect()
        self.assertEqual(saved["watermark"], NOW)

    def test_missing_watermark_starts_at_now(self):
        _, saved, _ = self._collect(watermark=None)
        self.assertEqual(saved["fetch_after"], NOW)
        self.assertEqual(saved["watermark"], NOW)

    def test_watermark_holds_at_an_in_progress_event(self):
        _, saved, _ = self._collect(in_progress=[NOW - 600])
        self.assertEqual(saved["watermark"], NOW - 600)

    def test_watermark_ignores_ancient_in_progress_events(self):
        _, saved, _ = self._collect(in_progress=[NOW - 30 * 3600])
        self.assertEqual(saved["watermark"], NOW)

    def test_existing_watermark_is_never_rewound(self):
        _, saved, _ = self._collect(watermark=NOW - 100, in_progress=[NOW - 5000])
        self.assertEqual(saved["watermark"], NOW - 100)

    def test_still_there_inside_one_drain(self):
        events = [
            ev("cat1", "cam04", "cat", 0, box=[0.40, 0.40, 0.2, 0.2]),
            ev("cat2", "cam04", "cat", 300, box=[0.41, 0.41, 0.2, 0.2]),
        ]
        result, saved, _ = self._collect(events=events)
        self.assertEqual(result["enqueued"], 1)
        self.assertEqual(saved["spend"]["still_there"], 1)

    def test_still_there_across_drains(self):
        last = {"cam04": Scene(
            scene_id="cam04-previous",
            camera="cam04",
            start=NOW - 4000,
            # 300 s before this scene starts: inside the 1800 s window.
            end=NOW - 3780,
            members=[{"id": "old-cat", "label": "cat", "data_box": [0.4, 0.4, 0.2, 0.2]}],
            labels=frozenset({"cat"}),
        )}
        events = [ev("cat1", "cam04", "cat", 120, box=[0.41, 0.41, 0.2, 0.2])]
        result, saved, _ = self._collect(events=events, last_scenes=last)
        self.assertEqual(result["enqueued"], 0)
        self.assertEqual(saved["spend"]["still_there"], 1)
        self.assertIn("cat1", saved["done"])

    def test_last_scenes_record_the_new_scene(self):
        _, saved, _ = self._collect()
        self.assertEqual(set(saved["last_scenes"]), {"cam04", "cam05", "cam06"})
        cat = saved["last_scenes"]["cam04"]
        self.assertEqual(cat.scene_id, CAT_SCENE)
        self.assertEqual(cat.members[0]["data"]["box"], [0.4, 0.4, 0.2, 0.2])

    def test_duplicates_are_counted_not_raised(self):
        client = _FakeStartClient(
            error=WorkflowAlreadyStartedError("exists", "PendingSceneWorkflow"))
        result, _, _ = self._collect(client=client)
        self.assertEqual(result["duplicates"], 3)
        self.assertEqual(result["enqueued"], 0)


class _Json:
    def __init__(self, payload):
        self.payload = payload

    def read(self):
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FetchEventsTests(unittest.TestCase):
    def _fetch(self, pages, start=50.0, limit=2):
        urls = []

        def fake_urlopen(url, timeout=None):
            urls.append(url)
            return _Json(pages[len(urls) - 1])

        with patch.object(dispatcher, "PAGE_LIMIT", limit), \
                patch.object(dispatcher.urllib.request, "urlopen", side_effect=fake_urlopen):
            events = dispatcher.fetch_events(start, NOW)
        return events, urls

    def test_walks_forward_and_dedupes_the_boundary_event(self):
        pages = [
            [ev("a", "cam01", "person", 0), ev("b", "cam01", "person", 100)],
            # The boundary event comes back, as Frigate's inclusive `after` does.
            [ev("b", "cam01", "person", 100), ev("c", "cam01", "person", 200)],
            [ev("d", "cam01", "person", 300)],
        ]
        events, urls = self._fetch(pages, start=NOW - 3600)
        self.assertEqual([e["id"] for e in events], ["a", "b", "c", "d"])
        self.assertIn("sort=date_asc", urls[0])
        self.assertIn("in_progress=0", urls[0])
        self.assertIn("after=%d" % (NOW - 3600 + 100), urls[1])
        self.assertIn("after=%d" % (NOW - 3600 + 200), urls[2])

    def test_stalled_cursor_stops(self):
        same = [ev("a", "cam01", "person", 0), ev("b", "cam01", "person", 0)]
        events, urls = self._fetch([same, same, same], start=NOW - 3600)
        self.assertEqual([e["id"] for e in events], ["a", "b"])
        self.assertEqual(len(urls), 1)

    def test_short_page_ends_paging(self):
        events, urls = self._fetch([[ev("a", "cam01", "person", 0)]])
        self.assertEqual(len(events), 1)
        self.assertEqual(len(urls), 1)

    def test_error_raises_instead_of_returning_a_partial_list(self):
        calls = []

        def fake_urlopen(url, timeout=None):
            calls.append(url)
            if len(calls) == 1:
                return _Json([ev("a", "cam01", "person", 0), ev("b", "cam01", "person", 100)])
            raise OSError("frigate down")

        with patch.object(dispatcher, "PAGE_LIMIT", 2), \
                patch.object(dispatcher.urllib.request, "urlopen", side_effect=fake_urlopen):
            with self.assertRaisesRegex(RuntimeError, "event fetch failed"):
                dispatcher.fetch_events(NOW - 3600, NOW)

    def test_in_progress_error_raises(self):
        with patch.object(dispatcher.urllib.request, "urlopen", side_effect=OSError("boom")):
            with self.assertRaisesRegex(RuntimeError, "in-progress fetch failed"):
                dispatcher.fetch_in_progress_starts()

    def test_in_progress_starts_are_parsed(self):
        page = [{"start_time": 100.0}, {"start_time": 200}, {"start_time": None}, {}]
        with patch.object(dispatcher.urllib.request, "urlopen", return_value=_Json(page)):
            self.assertEqual(dispatcher.fetch_in_progress_starts(), [100.0, 200.0])


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

        with patch.object(dispatcher.urllib.request, "urlopen", return_value=_Json(config)):
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


class _Execution:
    """Stand-in for a listed workflow execution: a plain dict answers the
    TypedSearchAttributes.get(key) the activity makes."""

    def __init__(self, workflow_id, start_time, priority=None, labels=None):
        self.id = workflow_id
        self.start_time = start_time
        self.typed_search_attributes = {}
        if priority is not None:
            self.typed_search_attributes[dispatcher._SEARCH_SCENE_PRIORITY] = priority
        if labels is not None:
            self.typed_search_attributes[dispatcher._SEARCH_SCENE_LABELS] = labels


class _Count:
    def __init__(self, count):
        self.count = count


class _Handle:
    def __init__(self, workflow_id, error=None):
        self.id = workflow_id
        self.error = error
        self.signals = []

    async def signal(self, name, arg):
        if self.error:
            raise self.error
        self.signals.append((name, arg))


class _CountOnlyClient:
    def __init__(self, in_flight):
        self.in_flight = in_flight

    async def count_workflows(self, query):
        return _Count(self.in_flight)


class _AdmitClient:
    def __init__(self, in_flight, executions, errors=None):
        self.in_flight = in_flight
        self.executions = executions
        self.errors = errors or {}
        self.handles = {}

    async def count_workflows(self, query):
        return _Count(self.in_flight)

    def list_workflows(self, query):
        executions = self.executions

        async def gen():
            for execution in executions:
                yield execution

        return gen()

    def get_workflow_handle(self, workflow_id):
        if workflow_id not in self.handles:
            self.handles[workflow_id] = _Handle(workflow_id, self.errors.get(workflow_id))
        return self.handles[workflow_id]

    def signalled(self):
        return [wid for wid, handle in self.handles.items() if handle.signals]


class AdmitTests(unittest.TestCase):
    def _admit(self, client, paused=(), max_in_flight=2, strong_ok=True):
        with patch.object(dispatcher, "_s3_list", return_value=list(paused)), \
                patch.object(dispatcher.activity, "client", return_value=client):
            return asyncio.run(dispatcher.admit_scenes_activity(
                {"max_in_flight": max_in_flight, "strong_ok": strong_ok}))

    def test_highest_priority_oldest_first(self):
        client = _AdmitClient(1, [
            _Execution("w1", NOW, "p3", "bird"),
            _Execution("w2", NOW + 1, "p0", "package"),
            _Execution("w3", NOW + 2, "p1", "person"),
            _Execution("w4", NOW + 3, "p0", "cat"),
        ])
        result = self._admit(client)
        self.assertEqual(client.signalled(), ["w2"])
        self.assertEqual(client.handles["w2"].signals, [("admit", True)])
        self.assertEqual(result, {"admitted": 1, "waiting": 4, "held_paused": 0, "in_flight": 1})

    def test_no_slots_when_full(self):
        client = _AdmitClient(2, [_Execution("w1", NOW, "p0", "package")])
        result = self._admit(client)
        self.assertEqual(client.signalled(), [])
        self.assertEqual(result["admitted"], 0)

    def test_oldest_of_equal_priority_wins(self):
        client = _AdmitClient(1, [
            _Execution("newer", NOW + 10, "p0", "cat"),
            _Execution("older", NOW, "p0", "package"),
        ])
        self._admit(client)
        self.assertEqual(client.signalled(), ["older"])

    def test_missing_search_attributes_rank_last(self):
        client = _AdmitClient(0, [
            _Execution("plain", NOW, None, None),
            _Execution("ranked", NOW + 10, "p0", "package"),
        ])
        self._admit(client, max_in_flight=1)
        self.assertEqual(client.signalled(), ["ranked"])

    def test_signal_error_does_not_stop_the_next(self):
        client = _AdmitClient(0, [
            _Execution("w1", NOW, "p0", "package"),
            _Execution("w2", NOW + 1, "p0", "cat"),
        ], errors={"w1": RuntimeError("workflow not found")})
        result = self._admit(client)
        self.assertEqual(client.signalled(), ["w2"])
        self.assertEqual(result["admitted"], 1)

    def test_paused_label_holds_the_scene(self):
        client = _AdmitClient(1, [
            _Execution("dog-scene", NOW, "p0", "dog"),
            _Execution("person-scene", NOW + 1, "p1", "person"),
        ])
        result = self._admit(client, paused=["_state/paused/genai-dog"])
        self.assertEqual(client.signalled(), ["person-scene"])
        self.assertEqual(result["held_paused"], 1)
        self.assertEqual(result["waiting"], 2)

    def test_all_held_reports_nothing_runnable(self):
        client = _AdmitClient(0, [_Execution("dog-scene", NOW, "p0", "dog")])
        result = self._admit(client, paused=["_state/paused/genai-dog"])
        self.assertEqual(result["admitted"], 0)
        self.assertEqual(result["in_flight"], 0)
        self.assertEqual(result["held_paused"], 1)


class FinishDrainTests(unittest.TestCase):
    def _finish(self, in_flight, loaded, release=("ollama/gemma4:12b", "ollama/gemma4:26b")):
        posts = []
        ps = [] if loaded is None else [{"name": name} for name in loaded]

        def fake_urlopen(target, timeout=None):
            if isinstance(target, str):
                return _Json({"models": ps})
            posts.append(json.loads(target.data))
            return _Json({})

        client = _CountOnlyClient(in_flight)
        with patch.object(dispatcher.activity, "client", return_value=client), \
                patch.object(dispatcher, "load_spend", return_value={}), \
                patch.object(dispatcher, "save_spend"), \
                patch.object(dispatcher.urllib.request, "urlopen", side_effect=fake_urlopen):
            result = asyncio.run(dispatcher.finish_drain_activity(
                {"started": 3, "gate_reason": "", "release_models": list(release)}))
        return result, posts

    def test_keeps_models_while_a_scene_is_in_flight(self):
        result, posts = self._finish(1, ["gemma4:12b"])
        self.assertEqual(posts, [])
        self.assertEqual(result["released"], [])

    def test_releases_only_resident_models(self):
        result, posts = self._finish(0, ["gemma4:12b"])
        self.assertEqual(posts, [{"model": "gemma4:12b", "keep_alive": 0}])
        self.assertEqual(result["released"], ["gemma4:12b"])

    def test_releases_nothing_when_ps_fails(self):
        result, posts = self._finish(0, None)
        self.assertEqual(posts, [])
        self.assertEqual(result["released"], [])


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
