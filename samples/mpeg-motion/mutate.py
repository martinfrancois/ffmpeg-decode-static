#!/usr/bin/env python3
"""Recreate invalid motion-code fixtures from the exact valid encoder outputs."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
for codec, case in json.loads((root / "mutations.json").read_text()).items():
    source = root / f"{codec}-valid.{case['extension']}"
    data = bytearray(source.read_bytes())
    assert hashlib.sha256(data).hexdigest() == case["input_sha256"], source
    for offset in case["zero_offsets"]:
        data[offset] = 0
    assert hashlib.sha256(data).hexdigest() == case["output_sha256"], codec
    (root / f"{codec}-invalid.{case['extension']}").write_bytes(data)
