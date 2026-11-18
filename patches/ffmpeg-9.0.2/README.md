# FFmpeg 9.0.2 modifications

The upstream source archive remains unchanged. This series modifies
`libavcodec/mpeg12dec.c` to return an error for invalid MPEG-1/2 motion codes.
All ten motion callers check the status before using the vector. Legal signed motion
vectors keep their existing decoding. The second patch checks MPEG-1/2 coefficients before narrowing and refuses
unsupported simple-IDCT arithmetic under AV_EF_EXPLODE. It preserves the shared
reader behavior of EA TQI and IPU. VCR2 uses the MPEG-2 decoder and is excluded
from all new coefficient and IDCT checks by its codec tag. Full-resolution FF_IDCT_SIMPLE decoding is
checked against the C and x86 arithmetic ranges. Other transform selections are
outside that check. Forbidden escapes are malformed syntax; legal streams needing
saturation or wider intermediates are unsupported, not thereby malformed.
Malformed escape representations return InvalidData; unsupported arithmetic
returns PatchWelcome, preserved through serial and threaded slice decoding.
Accepted blocks retain their existing pixels. Modified files record the date.
The patch is under the same LGPL-2.1-or-later terms as the FFmpeg files it changes;
the complete licence is in the original archive's COPYING.LGPLv2.1.

`series` lists patch SHA-256 digests in application order. `files` lists the
before and after SHA-256 digests of every modified file. Both are checked by
`scripts/apply-patches.sh` in the helper repository. BUILD-INFO identifies that
repository revision and records the patch archive digest and build commands.

To reconstruct the modified source, extract the original ffmpeg-9.0.2.tar.xz,
extract this patch archive into a separate directory, and run the helper's
`scripts/apply-patches.sh SOURCE_DIRECTORY PATCH_DIRECTORY`. It needs GNU patch,
GNU tar, xz and a SHA-256 tool. The helper build applies the same series before
configuration on every target. No encoder, muxer or hardware interface is added.

The third patch rejects zero macroblock quantiser updates in all three MPEG-1/2
read sites under AV_EF_EXPLODE, returning InvalidData. Nonzero scales, lenient
recognition and the VCR2 codec-tag exception retain their existing behavior.
No shared block-reader or slice-header policy changes. ADR0009 in the helper
repository records the normative basis and validation boundaries.
