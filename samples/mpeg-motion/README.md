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

Direct macroblock tests during patch development exercised all ten callers,
including field, 16x8, dual-prime and concealment vectors, with negative-vector
controls. These committed stream fixtures cover frame-coded MPEG-1/2 B pictures.
They do not establish complete-stream coverage of those other prediction modes.
