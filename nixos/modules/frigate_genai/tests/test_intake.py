"""Intake policy: what gets described, what collapses into a scene."""

import os
import sys
import unittest

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.intake import (  # noqa: E402
    Decision,
    Scene,
    classify,
    iou,
    merge_scenes,
    parse_zone_polygon,
    point_in_polygon,
    still_there,
)


def event(
    event_id="e1",
    camera="cam05",
    label="person",
    start=1000.0,
    duration=10.0,
    top_score=0.9,
    zones=(),
    box=None,
):
    return {
        "id": event_id,
        "camera": camera,
        "label": label,
        "start_time": start,
        "end_time": start + duration,
        "top_score": top_score,
        "entered_zones": list(zones),
        "data": {"box": box or [0.4, 0.4, 0.2, 0.2], "top_score": top_score},
    }


class ClassifyTests(unittest.TestCase):
    def test_audio_is_skipped(self):
        self.assertEqual(classify(event(label="speech")), (Decision.SKIP, "audio"))

    def test_vehicle_outside_zones_is_skipped(self):
        self.assertEqual(
            classify(event(camera="cam02", label="car", zones=["in_court"])),
            (Decision.SKIP, "vehicle-outside-zones"),
        )

    def test_vehicle_inside_household_zone_is_kept(self):
        decision, _ = classify(event(camera="cam06", label="car", zones=["front_driveway"]))
        self.assertEqual(decision, Decision.LOW_PRIORITY)

    def test_cam02_in_court_is_the_road(self):
        """cam02's in_court is the left-edge road wedge, not our property."""
        # A vehicle down there is off-property; a long person event is still
        # described (only short street pass-bys are dropped, and cam02 is not
        # a street camera).
        self.assertEqual(
            classify(event(camera="cam02", label="car", duration=45, zones=["in_court"]))[0],
            Decision.SKIP,
        )
        self.assertEqual(
            classify(event(camera="cam02", label="person", duration=45, zones=["in_court"]))[0],
            Decision.MUST_KEEP,
        )

    def test_zone_less_camera_keeps_vehicles(self):
        self.assertEqual(classify(event(camera="cam03", label="car", zones=[]))[0], Decision.LOW_PRIORITY)

    def test_street_pass_by(self):
        self.assertEqual(
            classify(event(camera="cam01", label="person", duration=20, zones=["road_speed_zone"])),
            (Decision.SKIP, "street-pass-by"),
        )
        # 29 s goes, 31 s stays.
        self.assertEqual(
            classify(event(camera="cam01", label="person", duration=31, zones=[]))[0],
            Decision.MUST_KEEP,
        )

    def test_flicker_boundary(self):
        yard = ["front_driveway"]
        self.assertEqual(
            classify(event(label="person", camera="cam06", duration=2.9, top_score=0.79, zones=yard)),
            (Decision.SKIP, "flicker"),
        )
        self.assertEqual(
            classify(event(label="person", camera="cam06", duration=2.9, top_score=0.81, zones=yard))[0],
            Decision.MUST_KEEP,
        )
        self.assertEqual(
            classify(event(label="person", camera="cam06", duration=3.1, top_score=0.5, zones=yard))[0],
            Decision.MUST_KEEP,
        )

    def test_short_package_survives(self):
        self.assertEqual(
            classify(event(label="package", camera="cam05", duration=1.0, top_score=0.4))[0],
            Decision.MUST_KEEP,
        )

    def test_cam05_short_event_survives(self):
        self.assertEqual(
            classify(event(label="cat", camera="cam05", duration=1.0, top_score=0.4))[0],
            Decision.MUST_KEEP,
        )

    def test_carrier_counts_as_must_keep(self):
        self.assertEqual(classify(event(label="amazon", camera="cam06", duration=12))[0], Decision.MUST_KEEP)

    def test_low_priority_short_or_weak(self):
        self.assertEqual(
            classify(event(label="umbrella", camera="cam06", duration=4.0))[0], Decision.SKIP
        )
        self.assertEqual(
            classify(event(label="umbrella", camera="cam06", duration=40.0, top_score=0.7))[0],
            Decision.SKIP,
        )
        self.assertEqual(
            classify(event(label="umbrella", camera="cam06", duration=40.0, top_score=0.8))[0],
            Decision.LOW_PRIORITY,
        )


# A square covering the middle of the frame, as a stand-in for a real polygon.
MIDDLE = [(0.3, 0.3), (0.7, 0.3), (0.7, 0.7), (0.3, 0.7)]
ZONES = {"cam06": {"front_driveway": MIDDLE}}


class ZoneGeometryTests(unittest.TestCase):
    def test_parse_zone_polygon(self):
        self.assertEqual(parse_zone_polygon("0.1,0.2,0.3,0.4,0.5,0.6"),
                         [(0.1, 0.2), (0.3, 0.4), (0.5, 0.6)])
        self.assertEqual(parse_zone_polygon(""), [])
        self.assertEqual(parse_zone_polygon("0.1,0.2,oops,0.4,0.5,0.6"),
                         [(0.1, 0.2), (0.5, 0.6)])

    def test_point_in_polygon(self):
        self.assertTrue(point_in_polygon(0.5, 0.5, MIDDLE))
        self.assertFalse(point_in_polygon(0.1, 0.5, MIDDLE))
        self.assertFalse(point_in_polygon(0.5, 0.9, MIDDLE))
        self.assertFalse(point_in_polygon(0.5, 0.5, [(0, 0), (1, 1)]))

    def test_box_on_the_driveway_is_property(self):
        """No entered_zones (0.18 dropped it): the box decides."""
        ev = event(camera="cam06", label="person", duration=5,
                   box=[0.45, 0.45, 0.60, 0.65])
        self.assertEqual(classify(ev, ZONES)[0], Decision.MUST_KEEP)

    def test_box_off_the_driveway_is_a_street_pass_by(self):
        ev = event(camera="cam06", label="person", duration=5,
                   box=[0.02, 0.30, 0.10, 0.45])
        self.assertEqual(classify(ev, ZONES), (Decision.SKIP, "street-pass-by"))

    def test_missing_polygons_never_skip(self):
        ev = event(camera="cam06", label="person", duration=5,
                   box=[0.02, 0.30, 0.10, 0.45])
        self.assertEqual(classify(ev)[0], Decision.MUST_KEEP)
        self.assertEqual(classify(ev, {})[0], Decision.MUST_KEEP)

    def test_event_without_box_never_skips_on_geometry(self):
        ev = event(camera="cam06", label="person", duration=5)
        ev["data"].pop("box")
        self.assertEqual(classify(ev, ZONES)[0], Decision.MUST_KEEP)

    def test_cam02_road_box_is_not_property(self):
        road = [(0.0, 0.0), (0.4, 0.0), (0.4, 1.0), (0.0, 1.0)]
        yard = [(0.5, 0.0), (0.9, 0.0), (0.9, 1.0), (0.5, 1.0)]
        zones = {"cam02": {"in_court": road, "in_back_yard": yard}}
        in_road = event(camera="cam02", label="car", duration=20, box=[0.1, 0.4, 0.2, 0.6])
        self.assertEqual(classify(in_road, zones), (Decision.SKIP, "vehicle-outside-zones"))
        in_yard = event(camera="cam02", label="car", duration=20, box=[0.6, 0.4, 0.7, 0.6])
        self.assertEqual(classify(in_yard, zones)[0], Decision.LOW_PRIORITY)

    def test_entered_zones_still_wins_when_present(self):
        ev = event(camera="cam06", label="person", duration=5,
                   zones=["front_driveway"], box=[0.02, 0.30, 0.10, 0.45])
        self.assertEqual(classify(ev, ZONES)[0], Decision.MUST_KEEP)


class MergeTests(unittest.TestCase):
    def test_gap_boundary(self):
        events = [
            event("a", start=1000.0, duration=10.0),
            event("b", start=1120.0, duration=10.0),  # 110 s after a ends → merged
            event("c", start=1250.0, duration=10.0),  # 120 s after b ends → merged
        ]
        self.assertEqual(len(merge_scenes(events)), 1)

        events[2]["start_time"] = 1250.1
        events[2]["end_time"] = 1260.1
        self.assertEqual(len(merge_scenes(events)), 2)

    def test_span_cap(self):
        events = [event(str(i), start=1000.0 + 100 * i, duration=10.0) for i in range(8)]
        scenes = merge_scenes(events)
        self.assertEqual(len(scenes), 2)
        self.assertTrue(all(s.end - s.start <= 600.0 for s in scenes))

    def test_priority_and_labels(self):
        events = [
            event("a", camera="cam06", label="person", start=1000.0, duration=10.0,
                  zones=["front_driveway"]),
            event("b", camera="cam06", label="dog", start=1030.0, duration=10.0,
                  zones=["front_driveway"]),
        ]
        (scene,) = merge_scenes(events)
        self.assertEqual(scene.priority, Decision.MUST_KEEP.value)
        self.assertEqual(scene.labels, {"person", "dog"})
        self.assertEqual(scene.primary["id"], "a")

    def test_cameras_never_merge(self):
        events = [
            event("a", camera="cam06", start=1000.0, duration=10.0),
            event("b", camera="cam04", start=1005.0, duration=10.0),
        ]
        self.assertEqual(len(merge_scenes(events)), 2)

    def test_scene_dict_is_json_safe(self):
        (scene,) = merge_scenes([event("a")])
        payload = scene.to_dict()
        self.assertEqual(payload["scene_id"], "cam05-1000")
        self.assertEqual(payload["primary"]["id"], "a")
        self.assertEqual(payload["labels"], ["person"])


class StillThereTests(unittest.TestCase):
    def _scene(self, event_id, start, label="cat", box=(0.4, 0.4, 0.2, 0.2)):
        return merge_scenes([event(event_id, camera="cam04", label=label, start=start, box=list(box))])[0]

    def test_same_object_same_place(self):
        first = self._scene("a", 1000.0)
        second = self._scene("b", 1200.0)
        self.assertTrue(still_there(second, first))

    def test_window(self):
        first = self._scene("a", 1000.0)
        # first ends at 1010; 1800 s window → 2810 ok, 2811 not
        self.assertTrue(still_there(self._scene("b", 2810.0), first))
        self.assertFalse(still_there(self._scene("b", 2811.0), first))

    def test_person_and_package_never_still_there(self):
        for label in ("person", "package"):
            first = self._scene("a", 1000.0, label=label)
            self.assertFalse(still_there(self._scene("b", 1100.0, label=label), first))

    def test_box_moved(self):
        first = self._scene("a", 1000.0, box=(0.1, 0.1, 0.2, 0.2))
        moved = self._scene("b", 1100.0, box=(0.6, 0.6, 0.2, 0.2))
        self.assertFalse(still_there(moved, first))

    def test_unknown_label_box_refused(self):
        first = self._scene("a", 1000.0, label="cat")
        second = merge_scenes([event("b", camera="cam04", label="dog", start=1100.0)])[0]
        self.assertFalse(still_there(second, first))

    def test_no_previous(self):
        self.assertFalse(still_there(self._scene("a", 1000.0), None))


class IouTests(unittest.TestCase):
    def test_identical(self):
        self.assertAlmostEqual(iou([0, 0, 1, 1], [0, 0, 1, 1]), 1.0)

    def test_disjoint(self):
        self.assertEqual(iou([0, 0, 0.2, 0.2], [0.5, 0.5, 0.2, 0.2]), 0.0)

    def test_half_overlap(self):
        # [0,0,1,1] and [0.5,0,1.5,1]: inter 0.5, union 1.5
        self.assertAlmostEqual(iou([0, 0, 1, 1], [0.5, 0, 1.5, 1]), 1 / 3)


if __name__ == "__main__":
    unittest.main()
