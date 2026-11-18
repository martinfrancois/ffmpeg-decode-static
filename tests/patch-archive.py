#!/usr/bin/env python3
"""Check archive bytes with both POSIX and Windows path ordering."""
import hashlib
import io
import runpy
import sys
import unittest
from contextlib import nullcontext
from pathlib import Path, PureWindowsPath
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
PINS = dict(
    line.split("=", 1)
    for line in (REPO / "versions.env").read_text().splitlines()
    if line.startswith(("FFMPEG_VERSION=", "FFMPEG_PATCH_SHA256="))
)


class WindowsOrderedPath:
    def __init__(self, path):
        self.path = path

    def __getattr__(self, name):
        return getattr(self.path, name)

    def __lt__(self, other):
        return PureWindowsPath(str(self.path)) < PureWindowsPath(str(other.path))


native_iterdir = Path.iterdir


def windows_iterdir(root):
    return (WindowsOrderedPath(path) for path in native_iterdir(root))


class PatchArchiveTest(unittest.TestCase):
    def test_pinned_bytes_under_both_path_orderings(self):
        root = REPO / "patches" / ("ffmpeg-" + PINS["FFMPEG_VERSION"])
        entries = list(windows_iterdir(root))
        self.assertNotEqual([path.name for path in sorted(entries)],
                            sorted(path.name for path in entries))
        for windows_order in (False, True):
            with self.subTest(windows_order=windows_order):
                output = io.BytesIO()
                args = ["make-patch-archive.py", str(root)]
                ordering = patch.object(Path, "iterdir", windows_iterdir) if windows_order else nullcontext()
                with ordering, patch.object(sys, "argv", args), \
                        patch.object(sys, "stdout", SimpleNamespace(buffer=output)):
                    runpy.run_path(str(REPO / "scripts/make-patch-archive.py"), run_name="__main__")
                self.assertEqual(hashlib.sha256(output.getvalue()).hexdigest(),
                                 PINS["FFMPEG_PATCH_SHA256"])


if __name__ == "__main__":
    unittest.main()
