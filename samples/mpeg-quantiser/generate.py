#!/usr/bin/env python3
"""Generate literal MPEG-2 macroblock quantiser updates and their controls."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BRANCHES = ("intra", "zero-mv", "motion")


def packed(bits):
    bits += "0" * (-len(bits) % 8)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))


def unit(code, bits):
    return b"\0\0\1" + bytes([code]) + packed(bits)


def escape(run, level):
    return "000001" + f"{run:06b}{level & 4095:012b}"


def empty(block):
    return ("100" if block < 4 else "00") + "10"


def intra(qscale):
    prefix = "00010" + "0" + "1"  # Slice scale 2, no extra data, address 1.
    prefix += "1" if qscale is None else "01"  # Intra or quant+intra.
    update = None if qscale is None else len(prefix)
    bits = prefix + ("" if qscale is None else f"{qscale:05b}")
    bits += "1101000" + escape(0, 16) + "10"  # First DC difference +8.
    bits += "".join(empty(n) for n in range(1, 6))
    bits += "11" + "".join(empty(n) for n in range(6))  # Intact second MB.
    return bits, update


def inter(branch, qscale):
    prefix = "00010" + "0" + "1"
    prefix += "00001" if branch == "zero-mv" else "00010"
    bits = prefix + f"{qscale:05b}"
    bits += "" if branch == "zero-mv" else "11"  # Zero motion components.
    bits += "1010" + escape(0, 16) + "10"  # CBP 32, one residual, EOB.
    bits += "1" + "001" + "11"  # Intact second MB: forward, no residual.
    return bits, len(prefix)


def stream(branch, qscale, rows):
    # 32x16 or 32x32, 25fps; sequence extension; default matrices.
    data = bytes.fromhex("000001b302001013ffffe018000001b5148a00010000")
    if rows == 2:
        data = data[:6] + b"\x20" + data[7:]
    extension = unit(0xb5, "1000" + "0001" * 4 + "00" + "11" + "0100000110")
    updates = []
    for frame in range(3):
        predicted = branch != "intra" and frame > 0
        header = f"{frame:010b}" + ("010" if predicted else "001") + "1" * 16
        if predicted:
            header += "0111"  # MPEG-2 header f_code 7; extension supplies 1.
        data += unit(0, header + "0") + extension
        for row in range(rows):
            # Two-slice variants leave the first slice valid, testing the second worker.
            scale = qscale if row == rows - 1 else 2
            bits, update = inter(branch, scale) if predicted else intra(
                scale if branch == "intra" else None
            )
            if update is not None and row == rows - 1:
                updates.append({"byte": len(data) + 4 + update // 8,
                                "bit_msb": update % 8, "width": 5})
            data += unit(row + 1, bits)
    return data + b"\0\0\1\xb7", updates


def main():
    manifest = {}
    for rows in (1, 2):
        for branch in BRANCHES:
            prefix = branch if rows == 1 else f"{branch}-slices"
            for qscale in (0, 2):
                data, updates = stream(branch, qscale, rows)
                name = f"{prefix}-q{qscale}.m2v"
                (ROOT / name).write_bytes(data)
                manifest[name] = {"sha256": hashlib.sha256(data).hexdigest(),
                                  "bytes": len(data), "hex": data.hex(), "updates": updates}
            zero = (ROOT / f"{prefix}-q0.m2v").read_bytes()
            control = (ROOT / f"{prefix}-q2.m2v").read_bytes()
            assert len(zero) == len(control)
            manifest[f"{prefix}-q0.m2v"]["control_byte_differences"] = [
                {"offset": i, "zero": a, "control": b}
                for i, (a, b) in enumerate(zip(zero, control)) if a != b
            ]
    (ROOT / "fixtures.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
