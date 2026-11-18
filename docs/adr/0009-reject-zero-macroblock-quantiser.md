---
status: accepted
date: 2026-11-18
decision-makers: [Codex]
consulted: []
informed: [Future maintainers and agents working on this repository]
---

# Reject zero macroblock quantiser updates in strict MPEG decoding

## Context and Problem Statement

FFmpeg 9.0.2 checks zero quantiser scale in slice headers but accepts zero in
three macroblock update branches: intra, implicit zero motion and explicit
motion. Complete MPEG-2 streams for each branch yield three frames without a
packet/frame error under `err_detect=explode`. Changing only the update from
zero to two changes decoded luma. Acceptance establishes the implementation gap;
the standards establish that the input is malformed.

For MPEG-1, ISO/IEC 11172-2:1993 section 2.4.2.7 places the five-bit
`quantizer_scale` in the macroblock when `macroblock_quant` is set. Section
2.4.3.6 defines its range as 1 through 31 and excludes zero, including updates
at the macroblock layer. Section 2.4.3.5 gives the corresponding slice semantics.

For MPEG-2, H.262 (02/2000) section 6.2.5 includes the conditional macroblock
`quantiser_scale_code`. Section 6.3.16 defines codes 1 through 31 and carries
the selected value until another slice or macroblock update. Section 7.4.2.2,
Table 7-6 excludes code zero for both linear and nonlinear scale mappings.
This decision follows those syntax and semantic constraints, not an inference
from FFmpeg's existing slice check.

## Considered Options

* Check the three production macroblock reads under the established strict policy
* Reject zero updates regardless of the requested error-recognition policy
* Parse macroblocks again outside the decoder

## Decision Outcome

Patch each of the three reads to return `AVERROR_INVALIDDATA` when its resulting
scale is zero and `AV_EF_EXPLODE` is set. Both mappings in `mpeg_get_qscale`
produce zero only for code zero. Preserve every nonzero result. No replacement
scale, pixel correction or additional parser is introduced.

The check covers the common MPEG-1/2 macroblock reader. Rename the existing
coefficient-check predicate to `mpeg12_strict_checks` to express its shared
policy, preserving its condition. VCR2 assigns MPEG2VIDEO as its codec ID but
retains its established behavior through the VCR2 codec-tag exclusion. Without
`AV_EF_EXPLODE`, MPEG-1/2 also retain their existing behavior. EA TQI and IPU use
the shared block reader, not these macroblock update sites; they are unchanged.
The existing slice-zero check remains unchanged.

Zero here is malformed syntax, so InvalidData is appropriate. It is distinct
from the unsupported legal coefficient arithmetic that returns PatchWelcome
under ADR0008. Existing macroblock, slice and worker error propagation carries
the new error to packet submission or frame reception.

## Confirmation

Twelve deterministic MPEG-2 fixtures cover the three update branches with
code-zero/code-two pairs. The original six are 32x16, one slice per picture.
Six 32x32 variants keep the first slice valid and put the tested update in the
second slice. Public packet/frame checks require InvalidData for strict zero
updates, and three frames with baseline luma hashes for controls and lenient
zero inputs. Two-slice variants run with one and two slice threads.

Direct production-macroblock tests check all three branches for MPEG-1,
MPEG-2 linear and nonlinear scales, and VCR2, with and without strict recognition.
They require refusal immediately after the five-bit update, before residual
parsing; accepted cases consume their complete macroblocks. These checks cover
policy and read-site behavior, not full-stream coverage for MPEG-1 or VCR2.
Existing motion and coefficient regressions remain part of focused verification.
Full GNU/musl builds and other target checks remain release requirements.

## References

* [ISO/IEC 11172-2:1993](https://www.iso.org/standard/22411.html), sections
  2.4.2.7, 2.4.3.5 and 2.4.3.6. The
  [1993 standard scan](https://www.scribd.com/document/1050208938/Ansi-Incits-Iso-Iec-11172-2-1993)
  provides the consulted macroblock syntax and semantics.
* [ITU-T H.262 (02/2000)](https://www.itu.int/rec/T-REC-H.262-200002-S/en),
  sections 6.2.5, 6.3.16 and 7.4.2.2, Table 7-6.
* FFmpeg 9.0.2 `mpeg12dec.c` and `mpeg12.h`.
