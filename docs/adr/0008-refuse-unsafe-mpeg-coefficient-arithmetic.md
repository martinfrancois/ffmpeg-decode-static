---
status: accepted
date: 2026-11-18
decision-makers: [martinfrancois]
consulted: []
informed: [Future maintainers and agents working on this repository]
---

# Refuse unsafe MPEG coefficient arithmetic in strict decoding

## Context and Problem Statement

FFmpeg 9.0.2 stores MPEG-1/2 inverse-quantized coefficients without the saturation
required by the standards. Its simple 8-bit IDCT also stores row intermediates
in 16 bits. Legal in-range coefficients can overflow that storage. Neither
failure produces a packet/frame API error under `err_detect=explode`.

For example, MPEG-2 escape level 2047 at horizontal position 3, with the default
intra matrix and quantizer scale 4, reconstructs to 11258 before saturation.
The normative coefficient is 2047. A separate block with row coefficients
[1088, 2044, 2042, 2046, 0, 0, 0, 0] needs no saturation, but its simple-IDCT row
intermediate reaches 71976. Both cases decode to wrong pixels without an error.
An escaped zero is a different defect: that representation is forbidden syntax,
although zero coefficients represented by runs or end-of-block are legal.

Consumers using bitexact flags and the simple integer IDCT need an API error
when reconstruction exceeds that transform's arithmetic range. The helper must
expose that error without relying on log messages or requiring consumers to
parse macroblocks again.

## Considered Options

* Saturation plus an existing reference or floating-point IDCT
* Saturation plus a new wide integer transform, or a per-block fallback
* Source-level refusal before unsupported arithmetic
* A second MPEG parser in each consumer

## Decision Outcome

Use source-level refusal under `AV_EF_EXPLODE`. Check inverse-quantized
coefficients before narrowing in all four MPEG-1/2 intra/inter readers. Reject
forbidden escape representations before inverse quantization. Preserve the
shared MPEG-1 reader's existing behavior for EA TQI and IPU by disabling its
new checks at those call sites. VCR2 uses the normal MPEG-2 decoder and assigns
MPEG2VIDEO as its codec ID. Exclude its VCR2 codec tag from all new coefficient
and IDCT checks, independently of that codec ID.

For full-resolution decoding explicitly using `FF_IDCT_SIMPLE`, check the
transform's arithmetic before reconstruction. Normalize the block through the
selected IDCT permutation, evaluate the fixed-point row sums in 64 bits, and
check their signed 16-bit storage range. Preserve the existing DC-only shortcut.
Check signed 32-bit column sums and x86's signed 16-bit addition of its column
rounding offset. The accepted range is shared by the scalar and x86 paths;
scalar-only decoding also refuses a block that fails that x86 rounding step.

This covers the actual implementations selected by `idct=simple` on the helper's
x86-64 and ARM64 targets. On x86-64 these are the C, SSE2 and AVX simple transforms;
on ARM64 the explicit option retains the C implementation. AUTO, SIMPLEAUTO,
other IDCT choices and low-resolution decoding are not covered by this transform
check. Coefficient and escape checks do not depend on the IDCT choice.

The magnitude shortcut is an acceptance proof, not a refusal threshold. When
the sum of coefficient magnitudes is at most 2047, the largest row multiplier
22725 and shift 11 bound every row result below 22725. For each column, the sum
of row magnitudes is bounded by 22725 * 2047 / 2048 plus rounding for eight rows.
Multiplication by 22725 and the column rounding bias remains below 2^30. Larger
blocks receive the exact checks. Accepted blocks still use the upstream IDCT;
no output pixel or coefficient is substituted.

The API returns `AVERROR_INVALIDDATA` for forbidden escape representations and
invalid intra DC ranges. It returns `AVERROR_PATCHWELCOME` for unsupported legal
coefficient or transform arithmetic. FFmpeg defines PatchWelcome as a feature
not yet implemented; other video decoders use it for unsupported valid syntax.
Consumers can therefore report unsupported decoding separately from damage.

Block, macroblock, slice and frame readers preserve the error. The slice-thread
executor collects worker return values and propagates them before frame error
concealment can replace them with generic InvalidData. Both callers check the
executor result, at the end of a packet and at picture start between paired
fields. This also preserves other
strict worker errors. Legal streams requiring coefficient saturation or unsafe
simple-IDCT arithmetic remain unsupported. This is a conservative completeness
limit, not a claim of full MPEG conformance or a replacement inverse transform.

## Why not an existing IDCT?

The integer reference option, `idct=int`, fixes the two-coefficient example but
still fails the three-coefficient example. It is not a complete correction.
The existing `idct=faani` keeps floating-point intermediates and fixes both
in-range examples. One bounded source experiment added normative MPEG-2 intra
saturation before mismatch control and used `faani`; the large-coefficient row
then matched [255, 65, 0, 0, 255, 255, 207, 0]. That combination is a real
alternative for a consumer willing to adopt a different transform contract.

A global switch changes ordinary pixels. Prior unmodified-library comparisons
recorded these visible-luma FNV-1a hashes:

| Control | simple | faani |
| --- | --- | --- |
| 50-frame coefficient control | 96c9af6fed4e5045 | 14e89acfe6699725 |
| MPEG-1 motion control | 296527333e1ed1b7 | be8242c81c3665c8 |
| MPEG-2 motion control | f9c7804fd81d24fc | 658f094444e911f3 |

`faanidct.c` uses float temporaries and `lrintf`. Replacing the integer path
requires cross-platform rounding validation and changes the established sample
pins. Existing 32-bit simple-IDCT entry points serve 10-bit MPEG-4 Studio output;
they are not drop-in 8-bit MPEG-1/2 transforms. A per-block floating fallback
would preserve ordinary blocks but needs coefficient permutation conversion and
integration at reconstruction sites, plus a new cross-platform output contract
for fallback blocks. Refusal avoids that additional dispatch and preserves the
accepted-stream contract while making unsupported input observable.

No performance measurement establishes that FAAN is too slow, or that these
checks are free. Performance is not the reason for rejecting that alternative.
A full correction can supersede this decision when it supplies a suitable
8-bit transform and platform evidence. Changing output pins alone is not proof.

## Confirmation

The committed streams exercise the public packet/frame API. Original issue
examples, legal coefficient endpoints, legal zero AC, a safe near-limit row,
row/column overflow, x86 rounding overflow, and MPEG-1/2 intra/inter twins are
covered. Accepted controls retain independently measured unmodified-library
hashes. Refusal must arise from packet submission or frame reception, not input
opening. The smoke test runs native dispatch, forced scalar dispatch and SSE2
where available, restoring CPU flags before subsequent checks. One- and two-thread
runs include generated two-slice pictures, so the typed error is checked through
the worker path as well as the serial path. Paired-field inputs check that the
first field's typed error survives the second picture header. VCR2 tests submit
sequence-header-free packets with a VCR2 codec tag and explicit dimensions,
forcing its initializer. Their hashes preserve unmodified FFmpeg behavior,
including its existing C/SIMD difference on the saturation example. These tests
do not establish VCR2 conformance or extend the supported MPEG arithmetic.

The existing verified patch series carries this correction after the motion
patch. Original source checksums and the first patch stay unchanged. The file
manifest covers every modified source, including shared-reader call sites.
Full target builds and review remain necessary before release.

## References

* [ITU-T H.262](https://www.itu.int/rec/T-REC-H.262), sections 7.2.2.3, 7.4.2.3,
  7.4.3, 7.4.4 and 7.5, and Table B.16
* FFmpeg 9.0.2 `mpeg12.c`, `mpeg12dec.c`, `simple_idct_template.c`,
  `x86/simple_idct10_template.asm`, `idctdsp.c` and `faanidct.c`
