#!/usr/bin/env python3
"""Write identical USTAR headers regardless of the platform's GNU tar version."""
import sys
import tarfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('cannot package patches "arguments": pass one patch directory')
root = Path(sys.argv[1])
with tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.USTAR_FORMAT) as archive:
    # Path ordering ignores case on Windows; archive ordering must not.
    for path in sorted(root.iterdir(), key=lambda path: path.name):
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f'cannot package patch "{path.name}": expected a regular file')
        entry = tarfile.TarInfo(path.name)
        entry.size = path.stat().st_size
        entry.mode = 0o644
        entry.uid = entry.gid = entry.mtime = 0
        entry.uname = entry.gname = ""
        with path.open("rb") as data:
            archive.addfile(entry, data)
