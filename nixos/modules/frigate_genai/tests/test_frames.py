"""Detector-box geometry: the crop must land on the object whatever shape
Frigate (or a vision model) hands us, and refuse nonsense instead of producing
a 1x1 crop."""

import io
import os
import sys
import unittest

from PIL import Image

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities.frames import (  # noqa: E402
    CROP_MAX_LONG_SIDE,
    CROP_PADDING,
    centre_box,
    crop_bytes,
    normalise_box,
)
from frigate_genai.activities.records import prune_done  # noqa: E402

W, H = 1920, 1080


class NormaliseBoxTests(unittest.TestCase):
    def test_pixels(self):
        box = normalise_box([960, 540, 1440, 810], W, H)
        self.assertEqual(box, (0.5, 0.5, 0.75, 0.75))

    def test_fractions_as_edges(self):
        self.assertEqual(normalise_box([0.5, 0.5, 0.75, 0.75], W, H), (0.5, 0.5, 0.75, 0.75))

    def test_fractions_as_xywh(self):
        # [x, y, w, h] where w/h place the far edge behind the origin: read as size.
        self.assertEqual(normalise_box([0.5, 0.5, 0.2, 0.2], W, H), (0.5, 0.5, 0.7, 0.7))

    def test_thousand_grid(self):
        box = normalise_box([500, 500, 750, 750], W, H)
        self.assertAlmostEqual(box[0], 0.5)
        self.assertAlmostEqual(box[2], 0.75)

    def test_degenerate_rejected(self):
        self.assertIsNone(normalise_box([0.5, 0.5, 0.0, 0.0], W, H))  # zero-size [x,y,w,h]
        self.assertIsNone(normalise_box([0.0, 0.0, 0.001, 0.5], W, H))

    def test_garbage_rejected(self):
        for bad in (None, [], [1, 2], "0,0,1,1", [float("nan"), 0, 1, 1], [None, 0, 1, 1]):
            self.assertIsNone(normalise_box(bad, W, H), bad)

    def test_out_of_range_clamped(self):
        box = normalise_box([-0.2, -0.1, 1.4, 1.2], W, H)
        self.assertEqual(box, (0.0, 0.0, 1.0, 1.0))


class CropTests(unittest.TestCase):
    def _jpeg(self):
        image = Image.new("RGB", (W, H), (10, 20, 30))
        for x in range(880, 1040):
            for y in range(460, 620):
                image.putpixel((x, y), (255, 255, 255))
        out = io.BytesIO()
        image.save(out, format="JPEG", quality=95)
        return out.getvalue()

    def test_crop_contains_the_object(self):
        data = crop_bytes(self._jpeg(), (400 / W, 400 / H, 600 / W, 700 / H))
        image = Image.open(io.BytesIO(data))
        self.assertLess(image.width, W)
        self.assertGreater(image.width, 100)

    def test_crop_is_context_sized_and_capped(self):
        # Context crop = 2.2x linear, then the long side is capped so a 4K
        # frame does not inflate the prompt.
        self.assertAlmostEqual(CROP_PADDING, 0.6)
        image = Image.open(io.BytesIO(crop_bytes(self._jpeg(), (0.30, 0.30, 0.70, 0.70))))
        self.assertLessEqual(max(image.size), CROP_MAX_LONG_SIDE)
        # A small box still gets a usable crop, not a 1-pixel sliver.
        small = Image.open(io.BytesIO(crop_bytes(self._jpeg(), (0.49, 0.49, 0.51, 0.51))))
        self.assertGreater(min(small.size), 20)

    def test_centre_box_is_60_percent(self):
        x1, y1, x2, y2 = centre_box()
        self.assertAlmostEqual(x2 - x1, 0.6)
        self.assertAlmostEqual(y2 - y1, 0.6)
        self.assertAlmostEqual(x1, y1)


class DoneIndexTests(unittest.TestCase):
    def test_prune_keeps_eight_days(self):
        now = 1_000_000.0
        ids = {"old": now - 9 * 86400, "edge": now - 8 * 86400, "new": now - 60}
        self.assertEqual(set(prune_done(ids, now)), {"edge", "new"})


if __name__ == "__main__":
    unittest.main()
