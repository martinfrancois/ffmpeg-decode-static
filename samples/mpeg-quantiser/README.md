# MPEG macroblock quantiser fixtures

Run `python3 samples/mpeg-quantiser/generate.py` from the repository root.
The generator writes twelve tiny streams and `fixtures.json`, containing each
stream's SHA-256, exact bytes, update bit positions and control byte differences.
No encoder or downloaded footage is required.

All streams have three pictures at 25fps, default matrices, normal scan and
linear quantiser scale. Slice headers use code two. The first macroblock in
the tested slice changes between code zero and code two; the second macroblock
is intact. `intra` uses three I pictures and type `01`, quant+intra.
`zero-mv` and `motion` use an I picture followed by two P pictures; the P types
are `00001`, quant+pattern, and `00010`, quant+forward+pattern. The coded block
pattern is 32. The residual is an escape with run zero and level 16 followed by
end-of-block; explicit motion components are zero. The first intra DC difference
is +8. These literal syntax choices select the three production update branches.

Files without `-slices` are 32x16 with one slice per picture. The `-slices`
variants are 32x32 with two slices per picture. Their first slice always uses
code two, placing the tested update in the second slice for worker propagation.
Both one- and two-thread runs use slice threading and default concealment.

The public packet/frame smoke requires strict code-zero refusal as InvalidData.
Opening or probing failure does not count. Nonzero controls and lenient zero
inputs must retain three frames and these whole-stream visible-luma FNV-1a64
hashes, measured before patch 0003 with bitexact flags and the simple IDCT:

| Branch | Code two | Lenient code zero |
| --- | --- | --- |
| intra | 110e40993b7f4a80 | 32d50a37ebd41b25 |
| zero-mv, motion | 0be6a8b379544760 | 110e40993b7f4a80 |
| intra-slices | f788ccfacda27865 | c017a0739ee3d280 |
| zero-mv-slices, motion-slices | 2c501af938f19b65 | 67457cb500d66005 |

Strict baseline decoding also accepted every zero input with those same hashes.
The normative reason for refusal is recorded in
[ADR0009](../../docs/adr/0009-reject-zero-macroblock-quantiser.md).

For direct coverage of MPEG-1, both MPEG-2 scale mappings, lenient decoding and
the VCR2 codec-tag exception, use an existing native Linux static build containing
the final patched sources and libraries:

```sh
bash tests/mpeg-quantiser-branches.sh /path/to/patched/ffmpeg-source
```

This includes production `mpeg12dec.c` and checks 48 macroblock cases. The runner
verifies the patched source hashes and writes only temporary output under
`build/`. It does not rebuild FFmpeg. Direct checks do not establish complete
packet/frame propagation for MPEG-1 or VCR2.
