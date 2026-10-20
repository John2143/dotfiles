"""Regression tests for the ffmpeg thread cap (transcode OOM loop).

Without -threads, ffmpeg sizes its decode/filter/encode pools to the host CPU
count (64 on `big`) instead of the pod's CPU limit; each 4K HEVC decode then
held ~3-4 GiB and two concurrent transcodes OOM-killed the 8 GiB ffmpeg pod.
ffmpeg options are positional: `-threads` before `-i` sets decoder threads,
`-threads` after `-i` sets encoder threads, `-filter_threads` is global and
must precede the output. Both ffmpeg call sites must carry all three.

subprocess.run is patched in each module's namespace, so no ffmpeg runs.
"""

import os
import subprocess
import sys
import unittest
from unittest.mock import patch

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from frigate_genai.activities import frame_extraction
from frigate_genai.config import FFMPEG_THREADS
from frigate_genai.tools import transcode


class _RecordingRun:
    """Stand-in for subprocess.run: records each argv, writes no frames,
    reports success."""

    def __init__(self):
        self.cmds: list[list[str]] = []

    def __call__(self, cmd, **kwargs):
        self.cmds.append(list(cmd))
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")


def _pair_indices(cmd: list[str], flag: str) -> list[int]:
    """Indices of `flag` that are immediately followed by FFMPEG_THREADS."""
    return [i for i in range(len(cmd) - 1)
            if cmd[i] == flag and cmd[i + 1] == FFMPEG_THREADS]


class FfmpegThreadCapTests(unittest.TestCase):

    def _run(self, module, fn, *args, expected=0, **kwargs) -> list[str]:
        # transcode_into_parts returns the frame count; _transcode_frames still
        # returns the frame bytes, so each caller states what it expects.
        rec = _RecordingRun()
        with patch.object(module.subprocess, "run", rec):
            frames = fn(*args, **kwargs)
        self.assertEqual(frames, expected)
        self.assertEqual(len(rec.cmds), 1, rec.cmds)
        cmd = rec.cmds[0]
        self.assertEqual(cmd[0], "ffmpeg")
        return cmd

    def _assert_threads_capped(self, cmd: list[str]) -> None:
        self.assertEqual(cmd.count("-i"), 1, cmd)
        i_idx = cmd.index("-i")
        out_idx = len(cmd) - 1  # output pattern is the final argument
        self.assertTrue(cmd[out_idx].endswith(".jpg"), cmd)

        threads = _pair_indices(cmd, "-threads")
        filter_threads = _pair_indices(cmd, "-filter_threads")
        self.assertTrue(any(t < i_idx for t in threads),
                        f"no decoder-side -threads {FFMPEG_THREADS} before -i: {cmd}")
        self.assertTrue(any(t < i_idx for t in filter_threads),
                        f"no -filter_threads {FFMPEG_THREADS} before -i: {cmd}")
        self.assertTrue(any(i_idx < t < out_idx for t in threads),
                        f"no encoder-side -threads {FFMPEG_THREADS} between -i and output: {cmd}")

    def test_transcode_into_parts_caps_decoder_filter_and_encoder_threads(self):
        for fps in (1, None):
            with self.subTest(fps=fps):
                cmd = self._run(frame_extraction, frame_extraction.transcode_into_parts,
                                "cam01", 0, 5, "events/test", fps)
                self._assert_threads_capped(cmd)

    def test_transcode_frames_caps_decoder_filter_and_encoder_threads(self):
        for fps in (None, 2):
            with self.subTest(fps=fps):
                cmd = self._run(transcode, transcode._transcode_frames,
                                "cam01", 0, 5, 0, 1.0, fps, expected=[])
                self._assert_threads_capped(cmd)

    def test_transcode_into_parts_uploads_by_frame_number_not_string_sort(self):
        # ffmpeg writes frame_%03d.jpg, so frame 1000 must not sort before
        # frame_999: the upload index has to come from the numeric suffix.
        numbers = (1, 2, 999, 1000, 1001)

        def fake_run(cmd, **kwargs):
            pattern = cmd[-1]
            for n in numbers:
                with open(pattern % n, "wb") as f:
                    f.write(str(n).encode())
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        uploaded: list[tuple[str, bytes]] = []

        with patch.object(frame_extraction.subprocess, "run", fake_run):
            with patch.object(frame_extraction, "_s3_put",
                              lambda key, body: uploaded.append((key, body))):
                count = frame_extraction.transcode_into_parts(
                    "cam01", 0, 5, "events/e", 1)

        self.assertEqual(count, 5)
        self.assertEqual([key for key, _ in uploaded],
                         [f"events/e/frames/frame_{i:03d}.jpg" for i in range(5)])
        self.assertEqual([body for _, body in uploaded],
                         [b"1", b"2", b"999", b"1000", b"1001"])

    def test_thread_cap_is_an_explicit_count(self):
        # "0" is ffmpeg's "auto" (host CPU count): the pre-fix behavior.
        self.assertTrue(FFMPEG_THREADS.isdigit(), FFMPEG_THREADS)
        self.assertGreater(int(FFMPEG_THREADS), 0)


if __name__ == "__main__":
    unittest.main()
