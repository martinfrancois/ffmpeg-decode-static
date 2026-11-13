---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# A decode-only FFmpeg under the LGPL

## Context and Problem Statement

The libraries are linked statically into programs that only read video: they open a file, decode
its frames and look at timestamps and colour tags. Those programs ship as one binary under a
permissive licence. A default FFmpeg build carries encoders, muxers, network protocols and
hardware interfaces that such a program never calls, and several optional parts change FFmpeg's
licence to the GPL.

Which parts of FFmpeg go into the libraries?

## Decision Drivers

* A program that links the libraries must be able to stay under a permissive licence, so the
  libraries have to be LGPL-2.1-or-later.
* Any file that FFmpeg's own decoders can read should decode, without a list of formats that
  someone has to extend later.
* The result must be the same on every build machine, whatever libraries that machine has.
* Code that parses untrusted input but is never called should not be in the binary.
* `ffmpeg-next` has to build against the result.

## Considered Options

* Disable whole groups and keep every native decoder, demuxer, parser and bitstream filter
* Start from `--disable-everything` and enable a list of formats
* A default FFmpeg build

## Decision Outcome

Chosen option: "Disable whole groups and keep every native decoder, demuxer, parser and bitstream
filter", because it reads every format FFmpeg can read without a list to maintain, and still
leaves out everything a decoding program does not call.

The details, all in `scripts/build.sh`:

* `--disable-autodetect` turns off every external library that FFmpeg would otherwise pick up
  from the build machine. `--disable-iconv` is needed on top of it, because FFmpeg still looks
  for an iconv inside the C library.
* `--disable-encoders --disable-muxers --disable-devices --disable-hwaccels --disable-network`
  remove what decoding does not use. `--disable-protocols --enable-protocol=file,pipe` leaves
  local files and standard input.
* `--disable-filters --enable-filter=bwdif,format,yadif` keeps two deinterlacers and the pixel
  format filter. The buffer source and sink are part of libavfilter and need no flag.
* `--disable-avdevice --disable-swresample --disable-swscale`. `ffmpeg-next` compiles with only
  its `codec`, `format` and `filter` features, so none of the three is needed. A program that
  links these libraries converts colours itself.
* `--enable-libdav1d` for AV1, because FFmpeg's own AV1 decoder only works with hardware
  acceleration. dav1d is under the BSD 2-Clause licence.
* `--enable-zlib`, which PNG, APNG and compressed headers in Matroska and MOV need. zlib is under
  the zlib licence.
* `--enable-gpl`, `--enable-nonfree` and `--enable-version3` are never passed.
* `--disable-programs --disable-doc --disable-debug --enable-pic`.

### Consequences

* Good, because the licence is LGPL-2.1-or-later and the build proves it: `scripts/build.sh` stops
  if `config.h` reports another licence.
* Good, because a new FFmpeg release brings its new decoders without a change here.
* Bad, because every audio and subtitle decoder is built too, which makes `libavcodec.a` about
  25 MB. A linker drops what the program does not reach, so the program does not grow by that
  much.
* Bad, because files that need bzip2 or lzma (some Matroska tracks, some TIFF images) do not
  decode, and there is no scaler. A filter graph that needs a format conversion fails to
  configure.

### Confirmation

`scripts/build.sh` reads FFmpeg's generated `config.h` and `config_components.h` after configure.
It fails unless the licence is "LGPL version 2.1 or later", no encoder, muxer, device or hardware
accelerator is enabled, the protocols are exactly `file` and `pipe`, the filters are exactly
`bwdif`, `format` and `yadif`, and every decoder and demuxer in its `required_decoders` and
`required_demuxers` lists is present. The smoke test repeats the licence, encoder, muxer and
protocol checks at run time against the linked libraries.

## Pros and Cons of the Options

### Start from `--disable-everything` and enable a list of formats

* Good, because the libraries would be smaller.
* Bad, because a file in a format nobody listed fails at run time, and the list needs a release
  for every addition.
* Bad, because the list has to track which parsers and bitstream filters each demuxer needs.

### A default FFmpeg build

* Good, because it needs no flags.
* Bad, because it links whatever the build machine has installed, so two machines give two
  different libraries.
* Bad, because it ships network code and encoders that the programs never call.
