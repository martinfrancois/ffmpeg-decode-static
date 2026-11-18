# Invalid MPEG motion-code fixtures

These are generated testsrc2 pictures, not third-party footage. FFmpeg 8.1.3
created each valid 30-frame stream with this command, replacing CODEC with
mpeg1video or mpeg2video and FILE with mpeg1-valid.m1v or mpeg2-valid.m2v:

```sh
ffmpeg -nostdin -v error -y -f lavfi -i testsrc2=size=176x144:rate=25:duration=1.2 \
  -an -c:v CODEC -q:v 12 -bf 2 -g 12 -ps 1 FILE
```

The invalid twins overwrite selected last bytes of B-picture slices with zeros.
`mutations.json` records every byte offset and the input/output SHA-256 digests.
`python3 samples/mpeg-motion/mutate.py` reconstructs them from the pinned twins
and refuses another encoder output. No container or header bytes are replaced.
The invalid all-zero motion VLC previously became vector 65535 without an error.

The smoke test sets one thread, bitexact, simple IDCT and
`err_detect=+crccheck+buffer+compliant+explode`. Both damaged inputs MUST return
InvalidData from packet submission or frame reception. An open/demux error is
not evidence of the correction. Both valid twins MUST yield 30 frames with
unchanged visible luma, hashed row by row with FNV-1a 64:

| File | Luma hash |
| --- | --- |
| mpeg1-valid.m1v | 296527333e1ed1b7 |
| mpeg2-valid.m2v | f9c7804fd81d24fc |

These control hashes were measured with an independent, unmodified FFmpeg 9.0.2
static decoder before applying the patch, then checked against a separate minimal
unmodified build. They do not come from the corrected smoke test itself. All
four streams were decoded by the unmodified library; the invalid twins had no
reported errors. The corrected library refuses both invalid twins.

The retained [direct macroblock test](../../tests/mpeg-motion-branches.c) exercises
all ten motion-reader call sites. On Linux, with Clang and an existing native,
in-tree static FFmpeg build, run from the repository root:

```sh
bash tests/mpeg-motion-branches.sh /path/to/patched/ffmpeg-source
```

The source directory must contain the final patched sources, configure output,
and built libavformat, libavcodec and libavutil archives. A minimal build with
MPEG-1/2 decoding is sufficient. Use the build's compiler via `CC` if needed.
The runner checks the patched file hashes against this checkout's manifest,
compiles only the test, and removes its temporary output under `build/`.
It does not configure or rebuild FFmpeg, or modify the supplied source tree.

The test includes production `mpeg12dec.c` and calls `mpeg_decode_mb` directly.
Its 35 cases comprise 20 invalid component positions, eight legal negative-vector
controls and seven direct motion-helper checks. Invalid macroblocks must return
InvalidData and stop at the invalid VLC; controls must retain the negative vector
and consume the expected bits. Modes include frame, field-picture 16x8, field
prediction in frame and field pictures, dual-prime in frame and field pictures,
and intra concealment in frame and field pictures. The helper checks also cover
predictor wrapping and residual bits.

These direct tests do not exercise complete demux, slice or thread propagation
for each mode or every list/field combination. The stream fixtures above cover
frame-coded MPEG-1/2 B pictures.
