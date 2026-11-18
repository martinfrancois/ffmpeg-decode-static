#!/usr/bin/env python3
"""Reconstruct coefficient regressions from the pinned generated I-picture seed."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def packed(bits):
    bits += '0' * (-len(bits) % 8)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))


def unit(code, bits):
    return b'\x00\x00\x01' + bytes([code]) + packed(bits)


def escape(run, level, mpeg1=False):
    if not mpeg1:
        value = f'{level & 4095:012b}'
    elif level == 0 or level > 127:
        value = '00000000' + f'{level:08b}'
    elif level <= -128:
        value = '10000000' + f'{level + 256:08b}'
    else:
        value = f'{level & 255:08b}'
    return '000001' + f'{run:06b}' + value


def empty_block(luma):
    return ('100' if luma else '00') + '10'


def intra_slice(scale, coefficients, mpeg1=False):
    first = '1101000' + ''.join(escape(r, v, mpeg1) for r, v in coefficients) + '10'
    mb0 = '11' + first + ''.join(empty_block(n < 4) for n in range(1, 6))
    mb1 = '11' + ''.join(empty_block(n < 4) for n in range(6))
    return unit(1, f'{scale:05b}' + '0' + mb0 + mb1)


def units(data):
    starts = []
    pos = 0
    while True:
        pos = data.find(b'\x00\x00\x01', pos)
        if pos < 0:
            break
        starts.append(pos)
        pos += 3
    return [data[a:b] for a, b in zip(starts, starts[1:] + [len(data)])]


seed = (ROOT / 'plain.m2v').read_bytes()
# The seed was generated from 32x16, I-only, 25 fps MPEG-2 pictures.
SEED_SHA256 = 'acc904ac272cd9d1b817c6732a5c3057399ff56d5455da9a4c6cf83248bcc03f'
assert hashlib.sha256(seed).hexdigest() == SEED_SHA256
variants = {
    'edge-up': (2, [(5, 2047)]),
    'two-in-range': (2, [(0, 511), (3, 430)]),
    'three-in-range': (2, [(0, 511), (3, 430), (0, 372)]),
    'zero': (2, [(0, 0)]),
    'lowest': (2, [(5, -2048)]),
    'zero-ac': (2, []),
    'positive-2047': (1, [(4, 862)]),
    'negative-2048': (2, [(0, -512)]),
    'single-2046': (2, [(5, 372)]),
    'row-safe': (2, [(0, 60), (3, 430)]),
    'rounding-overflow': (2, [(0, 61), (3, 430)]),
}
# Every row fits int16, but summing the transformed rows overflows a column.
zigzag = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
          12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
          35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
          58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
# First two columns of the default intra matrix, excluding row zero.
weights = [(16, 16), (19, 22), (22, 22), (22, 26), (26, 27), (26, 27), (27, 29)]
levels = {1: 60, 2: 430}
for row, (left, right) in enumerate(weights, 1):
    levels[row * 8] = 2040 * 4 // left
    levels[row * 8 + 1] = 1100 * 4 // right
coefficients = []
previous = 0
for scan, index in enumerate(zigzag[1:], 1):
    if index in levels:
        coefficients.append((scan - previous - 1, levels[index]))
        previous = scan
variants['column-overflow'] = (2, coefficients)

for name, (scale, coefficients) in variants.items():
    data = b''.join(intra_slice(scale, coefficients) if u[3] == 1 else u for u in units(seed))
    (ROOT / (name + '.m2v')).write_bytes(data)

# Three-picture streams exercise each intra/inter reader through AVCodec.
# Sequence header: 32x16, aspect 1, rate 25, variable bit rate, VBV size 3.
sequence = bytes.fromhex('000001b302001013ffffe018')
sequence_extension = bytes.fromhex('000001b5148a00010000')
# f_code=1, 8-bit DC, progressive frame, frame_pred_frame_dct=1,
# linear quantizer scale, default VLC table and zigzag scan.
picture_extension = unit(0xb5, '1000' + '0001' * 4 + '00' + '11' + '0100000110')
for mpeg1 in [True, False]:
    codec = 'mpeg1' if mpeg1 else 'mpeg2'
    suffix = '.m1v' if mpeg1 else '.m2v'
    for inter in [False, True]:
        for case, level in [('valid', 1), ('large', 255 if mpeg1 else 2047), ('zero', 0)]:
            scale = (31 if case == 'large' else 4) if mpeg1 else (31 if case == 'large' else 2)
            data = sequence + (b'' if mpeg1 else sequence_extension)
            for frame in range(3):
                predicted = inter and frame != 0
                header = f'{frame:010b}' + ('010' if predicted else '001') + '1' * 16
                if predicted:
                    header += '0001'  # full_pel_forward_vector=0, forward_f_code=1
                data += unit(0, header + '0')
                if not mpeg1:
                    data += picture_extension
                if predicted:
                    # Pattern-only P macroblock with zero motion, CBP=32.
                    # Only the first luma block is coded. The next macroblock
                    # has a forward vector (0,0), no coded residual.
                    residual = escape(5, level, mpeg1) + '10'
                    data += unit(1, f'{scale:05b}' + '0' + '1' + '01' + '1010' + residual + '1' + '001' + '11')
                else:
                    coefficients = [] if inter else [(5, level)]
                    data += intra_slice(4 if mpeg1 and inter else 2 if inter else scale, coefficients, mpeg1)
            data += b'\x00\x00\x01\xb7'
            name = f'{codec}-{"inter" if inter else "intra"}-{case}{suffix}'
            (ROOT / name).write_bytes(data)

# Two slice rows make thread_count=2 exercise threaded error propagation.
for mpeg1 in [True, False]:
    codec = 'mpeg1' if mpeg1 else 'mpeg2'
    suffix = '.m1v' if mpeg1 else '.m2v'
    for case in ['valid', 'large', 'zero']:
        source = (ROOT / f'{codec}-intra-{case}{suffix}').read_bytes()
        data = bytearray()
        for u in units(source):
            if u[3] == 0xb3:
                u = u[:4] + bytes.fromhex('020020') + u[7:]
            if u[3] == 1:
                # First slice is always supported; second carries the case.
                data += intra_slice(4 if mpeg1 else 2, [(5, 1)], mpeg1)
                u = u[:3] + b'\x02' + u[4:]
            data += u
        (ROOT / f'{codec}-slices-{case}{suffix}').write_bytes(data)

# A single frame made from two field pictures, with two slices per field.
# Keep the second field intact so errors in the first must survive picture start.
for case, coefficients in [('large', [(5, 2047)]), ('zero', [(0, 0)])]:
    data = bytes.fromhex('000001b302004013ffffe018000001b5148200010000')
    for structure in [1, 2]:
        data += unit(0, '0' * 10 + '001' + '1' * 16 + '0')
        data += unit(0xb5, '1000' + '0001' * 4 + '00' + f'{structure:02b}' + '0' * 10)
        data += intra_slice(2, coefficients if structure == 1 else [])
        second = intra_slice(2, [])
        data += second[:3] + b'\x02' + second[4:]
    data += b'\x00\x00\x01\xb7'
    (ROOT / f'mpeg2-fields-{case}.m2v').write_bytes(data)

# VCR2 receives dimensions and its codec tag from the caller. No sequence header
# is included: decoding these packets must use vcr2_init_sequence().
for case, coefficients in [('valid', []), ('large', [(5, 2047)]),
                            ('idct-overflow', [(0, 511), (3, 430)]), ('zero', [(0, 0)])]:
    packet = unit(0, '0' * 10 + '001' + '1' * 16 + '0') + intra_slice(2, coefficients)
    (ROOT / f'vcr2-{case}.packet').write_bytes(packet)
