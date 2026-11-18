#!/usr/bin/env python3
"""Check archive bytes with both POSIX and Windows path ordering."""
import hashlib
import io
import runpy
import sys
import unittest
from pathlib import Path, PureWindowsPath
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
PINS = dict(
    line.split("=", 1)
    for line in (REPO / "versions.env").read_text().splitlines()
    if line.startswith(("FFMPEG_VERSION=", "FFMPEG_PATCH_SHA256="))
)


class WindowsOrderedPath(type(Path())):
    def __lt__(self, other):
        return PureWindowsPath(str(self)) < PureWindowsPath(str(other))


class PatchArchiveTest(unittest.TestCase):
    def test_pinned_bytes_under_both_path_orderings(self):
        for path_type in (Path, WindowsOrderedPath):
            with self.subTest(path_type=path_type.__name__):
                output = io.BytesIO()
                args = ["make-patch-archive.py", str(REPO / "patches" / (
                    "ffmpeg-" + PINS["FFMPEG_VERSION"]))]
                with patch("pathlib.Path", path_type), patch.object(sys, "argv", args), \
                        patch.object(sys, "stdout", SimpleNamespace(buffer=output)):
                    runpy.run_path(str(REPO / "scripts/make-patch-archive.py"), run_name="__main__")
                self.assertEqual(hashlib.sha256(output.getvalue()).hexdigest(),
                                 PINS["FFMPEG_PATCH_SHA256"])


if __name__ == "__main__":
    unittest.main()
