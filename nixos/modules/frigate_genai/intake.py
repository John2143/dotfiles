"""Intake rules: which Frigate events deserve a description, and how repeats
collapse into one scene.

Pure functions and data — no I/O, no Temporal, no S3. Every threshold is a
module-level constant so the tests can pin behaviour and an operator can see
the policy in one screen.

Zones come from `dotfiles/nixos/modules/frigate.nix`. A camera with no zones
(cam03 garage, cam04 backyard, cam08 server room) has no street in frame, so
its events are never treated as off-property.
"""

from dataclasses import dataclass, field
from enum import Enum

# ── Property ──────────────────────────────────────────────────────────────
# Zones that lie inside our property, per camera. cam01's `road_speed_zone`
# and cam02's `in_court` are the street: cam02's is the left-edge road wedge
# that 91% of its car events and 22.8 person events/day pass through.
HOUSEHOLD_ZONES: dict[str, frozenset[str]] = {
    "cam01": frozenset({"inside_walkway_to_house", "in_court"}),
    "cam02": frozenset({"side_door", "in_back_yard", "actual_side_door"}),
    "cam05": frozenset({"front_door", "porch"}),
    "cam06": frozenset({"house", "driveway_gate", "front_driveway"}),
}

# Cameras that look over a public street.
STREET_CAMERAS = frozenset({"cam01", "cam06"})

# ── Labels ────────────────────────────────────────────────────────────────
AUDIO_LABELS = frozenset({"speech", "bark", "yell"})
VEHICLE_LABELS = frozenset({"car", "motorcycle", "bicycle", "school_bus", "boat"})
CARRIER_LABELS = frozenset({
    "amazon", "fedex", "ups", "usps", "dhl", "an_post", "purolator",
    "postnl", "nzpost", "postnord", "gls", "dpd", "royal_mail", "canada_post",
})
WILDLIFE_LABELS = frozenset({"bird", "deer", "horse", "bear", "cow", "fox", "raccoon"})

MUST_KEEP_LABELS = frozenset({"person", "package", "cat", "dog"}) | WILDLIFE_LABELS | CARRIER_LABELS
LOW_PRIORITY_LABELS = frozenset({
    "face", "license_plate", "umbrella", "robot_lawnmower",
}) | VEHICLE_LABELS

# ── Thresholds ────────────────────────────────────────────────────────────
FLICKER_SECONDS = 3.0
FLICKER_SCORE = 0.80
STREET_PASS_SECONDS = 30.0
LOW_PRIORITY_SECONDS = 5.0
LOW_PRIORITY_SCORE = 0.75

MERGE_GAP_SECONDS = 120.0
MERGE_MAX_SPAN_SECONDS = 600.0
STILL_THERE_WINDOW_SECONDS = 1800.0
STILL_THERE_IOU = 0.5
STILL_THERE_LABELS = frozenset({"person", "package"})


class Decision(str, Enum):
    SKIP = "skip"
    MUST_KEEP = "must_keep"
    LOW_PRIORITY = "low_priority"


def _duration(event: dict) -> float:
    start = float(event.get("start_time") or 0)
    end = float(event.get("end_time") or start)
    return max(0.0, end - start)


def _score(event: dict) -> float:
    score = event.get("top_score")
    if score is None:
        score = (event.get("data") or {}).get("top_score")
    try:
        return float(score)
    except (TypeError, ValueError):
        return 0.0


def _entered_zones(event: dict) -> set[str]:
    zones = event.get("entered_zones")
    if zones is None:
        zones = (event.get("data") or {}).get("entered_zones") or []
    return set(zones or [])


def parse_zone_polygon(coordinates: str) -> list[tuple[float, float]]:
    """Frigate zones are a flat "x,y,x,y,..." string of normalised points."""
    values = [p for p in (coordinates or "").replace(" ", "").split(",") if p]
    points: list[tuple[float, float]] = []
    for i in range(0, len(values) - 1, 2):
        try:
            points.append((float(values[i]), float(values[i + 1])))
        except ValueError:
            continue
    return points


def point_in_polygon(x: float, y: float, polygon: list[tuple[float, float]]) -> bool:
    """Ray casting, boundary-exclusive. A degenerate polygon matches nothing."""
    if len(polygon) < 3:
        return False
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _box(event: dict) -> list[float] | None:
    box = (event.get("data") or {}).get("box") or event.get("data_box")
    if isinstance(box, (list, tuple)) and len(box) == 4:
        try:
            return [float(v) for v in box]
        except (TypeError, ValueError):
            return None
    return None


def _feet_and_middle(event: dict) -> list[tuple[float, float]]:
    box = _box(event)
    if box is None:
        return []
    x1, y1, x2, y2 = min(box[0], box[2]), min(box[1], box[3]), max(box[0], box[2]), max(box[1], box[3])
    return [((x1 + x2) / 2, y2), ((x1 + x2) / 2, (y1 + y2) / 2)]


def on_property(
    event: dict,
    zone_polygons: dict[str, dict[str, list[tuple[float, float]]]] | None = None,
) -> bool | None:
    """True inside a household zone, False outside, None when it cannot be told.

    Frigate 0.18's event API no longer returns `entered_zones`, so membership is
    computed from the detection box against the zone polygons in /api/config:
    the box's feet and centre are tested. When the polygons are unavailable the
    answer is None, and the callers below then keep the event rather than drop
    it — a missing config must never silently suppress descriptions.
    """
    camera = event.get("camera", "")
    household = HOUSEHOLD_ZONES.get(camera)
    if household is None:
        return None

    entered = _entered_zones(event)
    if entered:
        return bool(household & entered)

    polygons = (zone_polygons or {}).get(camera) or {}
    points = _feet_and_middle(event)
    if not polygons or not points:
        return None
    for name, polygon in polygons.items():
        if name not in household:
            continue
        for x, y in points:
            if point_in_polygon(x, y, polygon):
                return True
    return False


def classify(
    event: dict,
    zone_polygons: dict[str, dict[str, list[tuple[float, float]]]] | None = None,
) -> tuple[Decision, str]:
    """Decide what to do with one Frigate event. First match wins."""
    label = event.get("label", "")
    camera = event.get("camera", "")
    duration = _duration(event)
    score = _score(event)
    inside = on_property(event, zone_polygons)

    if label in AUDIO_LABELS:
        return Decision.SKIP, "audio"

    if label in VEHICLE_LABELS and inside is False:
        return Decision.SKIP, "vehicle-outside-zones"

    if (
        camera in STREET_CAMERAS
        and label in {"person", "dog"}
        and inside is False
        and duration < STREET_PASS_SECONDS
    ):
        return Decision.SKIP, "street-pass-by"

    # Short, low-confidence blips. Package and cam05 (porch) are excluded:
    # this rule would otherwise drop 16% of all package events.
    if (
        label in MUST_KEEP_LABELS
        and label != "package"
        and camera != "cam05"
        and duration < FLICKER_SECONDS
        and score < FLICKER_SCORE
    ):
        return Decision.SKIP, "flicker"

    if label in LOW_PRIORITY_LABELS and (duration < LOW_PRIORITY_SECONDS or score < LOW_PRIORITY_SCORE):
        return Decision.SKIP, "short-or-weak"

    if label in MUST_KEEP_LABELS:
        return Decision.MUST_KEEP, "must-keep"

    return Decision.LOW_PRIORITY, "low-priority"


# ── Scenes ────────────────────────────────────────────────────────────────
_PRIORITY_RANK = {
    Decision.MUST_KEEP: 2,
    Decision.LOW_PRIORITY: 1,
    Decision.SKIP: 0,
}


@dataclass
class Scene:
    """A run of related events on one camera, described with one LLM call."""

    scene_id: str
    camera: str
    start: float
    end: float
    members: list[dict] = field(default_factory=list)
    labels: frozenset[str] = frozenset()
    priority: str = Decision.LOW_PRIORITY.value
    zone_polygons: dict[str, dict[str, list[tuple[float, float]]]] | None = None

    @property
    def primary(self) -> dict:
        """The member the frames and the crop come from: the longest one."""
        return max(self.members, key=_duration)

    @property
    def event_ids(self) -> list[str]:
        return [m["id"] for m in self.members]

    def to_dict(self) -> dict:
        primary = self.primary
        return {
            "scene_id": self.scene_id,
            "camera": self.camera,
            "start": self.start,
            "end": self.end,
            "labels": sorted(self.labels),
            "priority": self.priority,
            "members": [
                {
                    "id": m["id"],
                    "label": m.get("label", ""),
                    "start_time": m.get("start_time"),
                    "end_time": m.get("end_time"),
                    "duration": round(_duration(m), 1),
                    "top_score": round(_score(m), 2),
                    "sub_label": m.get("sub_label") or (m.get("data") or {}).get("sub_label"),
                    "entered_zones": sorted(_entered_zones(m)),
                    "on_property": on_property(m, self.zone_polygons),
                }
                for m in self.members
            ],
            "primary": {
                "id": primary["id"],
                "label": primary.get("label", ""),
                "start_time": primary.get("start_time"),
                "end_time": primary.get("end_time"),
                "data_box": (primary.get("data") or {}).get("box") or primary.get("data_box"),
            },
        }


def merge_scenes(
    events: list[dict],
    gap_s: float = MERGE_GAP_SECONDS,
    max_span_s: float = MERGE_MAX_SPAN_SECONDS,
    zone_polygons: dict[str, dict[str, list[tuple[float, float]]]] | None = None,
) -> list[Scene]:
    """Group events into scenes: same camera, next event starts within `gap_s`
    of the previous end, and the scene never spans more than `max_span_s`."""
    by_camera: dict[str, list[dict]] = {}
    for event in events:
        by_camera.setdefault(event.get("camera", ""), []).append(event)

    scenes: list[Scene] = []
    for camera, camera_events in sorted(by_camera.items()):
        camera_events.sort(key=lambda e: float(e.get("start_time") or 0))
        current: list[dict] = []
        for event in camera_events:
            if current:
                previous_end = max(float(m.get("end_time") or 0) for m in current)
                scene_start = min(float(m.get("start_time") or 0) for m in current)
                starts = float(event.get("start_time") or 0)
                ends = float(event.get("end_time") or starts)
                if starts - previous_end > gap_s or ends - scene_start > max_span_s:
                    scenes.append(_build_scene(camera, current, zone_polygons))
                    current = []
            current.append(event)
        if current:
            scenes.append(_build_scene(camera, current, zone_polygons))

    scenes.sort(key=lambda s: s.start)
    return scenes


def _build_scene(
    camera: str,
    members: list[dict],
    zone_polygons: dict[str, dict[str, list[tuple[float, float]]]] | None = None,
) -> Scene:
    start = min(float(m.get("start_time") or 0) for m in members)
    end = max(float(m.get("end_time") or 0) for m in members)
    labels = frozenset(m.get("label", "") for m in members)
    priority = max(
        (classify(m, zone_polygons)[0] for m in members),
        key=lambda d: _PRIORITY_RANK.get(d, 0),
    )
    return Scene(
        scene_id=f"{camera}-{int(start)}",
        camera=camera,
        start=start,
        end=end,
        members=members,
        labels=labels,
        priority=priority.value,
        zone_polygons=zone_polygons,
    )


def _box_of(event: dict) -> dict[str, list[float]]:
    """label -> box for one event (Frigate keeps the box in data.box)."""
    label = event.get("label", "")
    box = (event.get("data") or {}).get("box") or event.get("data_box")
    if label and isinstance(box, (list, tuple)) and len(box) == 4:
        return {label: [float(v) for v in box]}
    return {}


def iou(a: list[float], b: list[float]) -> float:
    """IoU of two boxes. Frigate mixes [x, y, w, h] and [x1, y1, x2, y2]
    depending on endpoint; normalise by treating both as edges of a rect."""
    if len(a) != 4 or len(b) != 4:
        return 0.0
    ax1, ay1, ax2, ay2 = min(a[0], a[2]), min(a[1], a[3]), max(a[0], a[2]), max(a[1], a[3])
    bx1, by1, bx2, by2 = min(b[0], b[2]), min(b[1], b[3]), max(b[0], b[2]), max(b[1], b[3])
    inter_w = max(0.0, min(ax2, bx2) - max(ax1, bx1))
    inter_h = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter = inter_w * inter_h
    if inter <= 0:
        return 0.0
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def still_there(scene: Scene, last_described: Scene | None) -> bool:
    """True when this scene shows the same uninterrupted thing the previous
    described scene showed: no person/package involved, same camera, starting
    within the window, and every label's box overlapping the earlier box.

    Measured from the last *described* scene, never chained — chains otherwise
    reach 23 scenes over 2 h and one of 12.5 h.
    """
    if last_described is None or scene.camera != last_described.camera:
        return False
    if scene.labels & STILL_THERE_LABELS or last_described.labels & STILL_THERE_LABELS:
        return False
    if scene.start - last_described.end > STILL_THERE_WINDOW_SECONDS:
        return False

    before: dict[str, list[float]] = {}
    for member in last_described.members:
        before.update(_box_of(member))

    for label in scene.labels:
        previous = before.get(label)
        current = None
        for member in scene.members:
            if member.get("label") == label:
                box = (member.get("data") or {}).get("box") or member.get("data_box")
                if isinstance(box, (list, tuple)) and len(box) == 4:
                    current = [float(v) for v in box]
                    break
        if previous is None or current is None:
            return False
        if iou(previous, current) < STILL_THERE_IOU:
            return False
    return bool(scene.labels)
