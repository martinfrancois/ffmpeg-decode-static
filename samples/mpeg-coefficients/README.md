# MPEG coefficient fixtures

These are generated 32x16 elementary streams, not third-party footage.
`plain.m2v` is a generated 50-frame I-picture control. `generate.py` checks its
SHA-256 and reconstructs the coefficient variants by replacing slice payloads. It also emits three-picture MPEG-1/2 intra/inter
streams from literal headers and coefficients. Two-slice variants are 32x32 and
exercise error propagation with two decoder threads. The generator needs only
Python's standard library. `SHA256SUMS` pins every stream.

Run `python3 samples/mpeg-coefficients/generate.py` from the repository root.
The existing plain seed and the five original coefficient variants remain byte-for-byte
identical to the files that reproduced the problem on unmodified FFmpeg 9.0.2.

## Encoded values and expected refusal

The original variants use the default intra matrix, normal zigzag scan, linear
quantizer scale 4, 8-bit DC precision, and a first DC difference of +8. The
predictor starts at 128, so the reconstructed DC coefficient is 1088.

| Fixture | Actual encoded values and effect | Required API error |
| --- | --- | --- |
| zero | Escape level bits 000000000000, forbidden by H.262 Table B.16 | InvalidData |
| lowest | Escape level bits 100000000000, reserved by Table B.16 | InvalidData |
| edge-up | run 5, level 2047: 2047 * 22 * 4 / 16 = 11258 before required saturation | PatchWelcome |
| two-in-range | run 0/level 511 then run 3/level 430: row [1088,2044,2042,0,0,0,0,0] | PatchWelcome |
| three-in-range | preceding pair plus run 0/level 372: adds 2046 at horizontal position 3 | PatchWelcome |
| rounding-overflow | row intermediate 32755 fits int16, but x86 adds 32 in a 16-bit lane | PatchWelcome |
| column-overflow | generated bounded coefficients fit every row store but overflow the column sum | PatchWelcome |

The two-coefficient row needs intermediates 52728 and 36773. The three-coefficient
row needs 71976. These exceed int16 even though every reconstructed coefficient
is legal. Mismatch control adds 1 at [7][7] and does not repair row zero.
The legal arithmetic cases are unsupported by this transform, not malformed
syntax. Section 7.4.3 of H.262 requires saturation before mismatch control;
sections 7.4.4 and 7.5 then require mismatch control and a conforming IDCT.

The `mpeg1-*` and `mpeg2-*` files separately reach each intra/inter reader.
Their `large` variants use quantizer code 31 and escape level 255 for MPEG-1 or
2047 for MPEG-2. Their `zero` variants use an escaped zero, rather than a legal
zero run. For the `inter` cases, the first picture is supported and subsequent
P pictures code the first luma block with zero motion. For `slices`, the first
slice is supported and the second carries the case. Large variants require
PatchWelcome, zero variants InvalidData.

## Accepted controls

The smoke test requires all frames and exact visible-luma FNV-1a hashes. These
hashes were measured with the independent, unmodified pinned FFmpeg 9.0.2 library
before applying the coefficient patch. They are preservation checks, not claims
that an unmodified decoder proves correctness on the refused cases.

| File stem | Frames | Luma hash |
| --- | --- | --- |
| plain | 50 | 96c9af6fed4e5045 |
| zero-ac | 50 | 2c91d1050d22f325 |
| positive-2047 | 50 | 90ab866ab88ffde5 |
| negative-2048 | 50 | 910009160f9bd0a5 |
| single-2046 | 50 | f646d3bdfedaf275 |
| row-safe | 50 | 03243c7f51ce3725 |
| mpeg1-intra-valid | 3 | a259477846ce4a25 |
| mpeg1-inter-valid | 3 | 49a4fd068305ef05 |
| mpeg2-intra-valid | 3 | 1d0b79a292aa4bd5 |
| mpeg2-inter-valid | 3 | a55fb7cf6667338b |
| mpeg1-slices-valid | 3 | f49a544bd7227125 |
| mpeg2-slices-valid | 3 | 6ca04f6f198b0b85 |

`zero-ac` uses end-of-block with no AC values and remains readable.
`positive-2047` reconstructs 2047 from level 862, weight 19 and scale 2.
`negative-2048` reconstructs -2048 from legal level -512, weight 16 and scale 4.
The reserved encoded level -2048 is distinct from that legal reconstructed value.
`row-safe` reaches row intermediate 32711 and remains supported. `single-2046`
also remains supported despite exceeding the check's cheap acceptance bound.

Tests use bitexact flags, simple IDCT and explode. Native, scalar and SSE2
where available run with one and two threads. Only packet submission or frame
reception counts as refusal; an input-open error does not satisfy the test.
The existing motion controls remain in the suite.

See [ADR 0008](../../docs/adr/0008-refuse-unsafe-mpeg-coefficient-arithmetic.md)
for the source paths, alternative transforms and limits of this correction.

## Paired fields and VCR2 preservation

`mpeg2-fields-large.m2v` and `mpeg2-fields-zero.m2v` contain two field pictures
forming one 32x64 frame, with two slices in each field. The first top-field slice
contains the oversized coefficient or forbidden escape; all later slices are
intact. The second picture header must not discard the first field's worker
result. With one or two threads, the large case requires PatchWelcome and the
zero case InvalidData. These tests check error propagation, not additional
field-picture support.

The four `vcr2-*.packet` files contain a picture header and one slice, without a
sequence header. The public decoder test supplies a VCR2 codec tag and dimensions
32x16, so it must use `vcr2_init_sequence()`. That initializer assigns the normal
MPEG-2 codec ID. Exclusion therefore uses the codec tag in all new checks.
The separate shared-reader call with checks disabled belongs to IPU, not VCR2;
EA TQI and IPU retain their existing shared-reader behavior.

Each VCR2 packet must return one frame under explode. Hashes were measured with
the independent unmodified FFmpeg 9.0.2 library before applying the review fix:

| Packet | Scalar hash | x86 SSE2/AVX hash |
| --- | --- | --- |
| vcr2-valid | a11059efd172cb25 | a11059efd172cb25 |
| vcr2-zero | a11059efd172cb25 | a11059efd172cb25 |
| vcr2-idct-overflow | 058eef4eb2a34a0c | 058eef4eb2a34a0c |
| vcr2-large | 5aa58ab3fed0db85 | 7c9506c3dd061b25 |

The pre-existing difference on the large case is retained deliberately. These
are preservation checks for a decoder excluded from the correction, not claims
that its arithmetic is conforming.
