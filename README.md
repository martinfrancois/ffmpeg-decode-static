# ffmpeg-decode-static

Decode-only, LGPL, static FFmpeg builds for linking into Rust programs.

The scripts here build FFmpeg 9.0 as static libraries that can read and decode video, and nothing
else: no encoders, no muxers, no network, no hardware acceleration. A Rust program links them
through the [`ffmpeg-next`](https://crates.io/crates/ffmpeg-next) crate and ships as one binary
with no FFmpeg installed next to it. GitHub Actions builds every target on its own kind of machine
and runs a Rust test program against the result.

## What an archive holds

Each target has one archive, `ffmpeg-decode-static-<target>.tar.xz`:

```
BUILD-INFO          versions, source URLs and checksums, compiler, exact build commands
include/            FFmpeg headers (libavcodec, libavfilter, libavformat, libavutil)
lib/                libavcodec.a, libavfilter.a, libavformat.a, libavutil.a
lib/pkgconfig/      pkg-config files that point at the directory they are in
licenses/           licence texts of FFmpeg, dav1d and zlib
```

`libavcodec.a` also holds dav1d and zlib, so those four libraries are everything a program links
([why](docs/adr/0004-dav1d-and-zlib-inside-libavcodec.md)). Do not link a second copy of dav1d or
zlib into the same program.

## Targets

| Target | Built in | The libraries need |
| --- | --- | --- |
| `x86_64-unknown-linux-gnu` | AlmaLinux 8, GCC 14 | glibc 2.28 or newer |
| `aarch64-unknown-linux-gnu` | AlmaLinux 8, GCC 14 | glibc 2.28 or newer |
| `x86_64-unknown-linux-musl` | Alpine, GCC | musl, for a fully static binary |
| `aarch64-unknown-linux-musl` | Alpine, GCC | musl, for a fully static binary |

The reasons are in [docs/adr/0002-targets.md](docs/adr/0002-targets.md) and
[docs/adr/0003-glibc-2-28-baseline.md](docs/adr/0003-glibc-2-28-baseline.md). `versions.env` pins
the exact container images.

## What is in the build

| Part | State | Reason |
| --- | --- | --- |
| Decoders, demuxers, parsers, bitstream filters | all of FFmpeg's own | any file FFmpeg can read should decode |
| AV1 | through dav1d | FFmpeg's own AV1 decoder needs hardware acceleration |
| zlib | built in | PNG, APNG and compressed Matroska and MOV headers need it |
| Protocols | `file` and `pipe` | input is a local file or a stream on stdin |
| Filters | `bwdif`, `yadif`, `format`, plus the buffer source and sink | enough to deinterlace |
| Encoders, muxers, devices, network, hardware acceleration | off | not needed to decode |
| libswscale, libswresample, libavdevice | not built | `ffmpeg-next` builds without them |
| iconv, bzip2, lzma and every other system library | off | the result must not depend on what the build machine has |
| The `ffmpeg`, `ffprobe` and `ffplay` programs | not built | this is a library build |
| GPL and nonfree parts | off | the libraries stay LGPL-2.1-or-later |

The build fails if FFmpeg reports any licence other than "LGPL version 2.1 or later", if an
encoder, muxer, device or hardware accelerator gets enabled, or if one of the formats below goes
missing. [docs/adr/0001-decode-only-lgpl-configuration.md](docs/adr/0001-decode-only-lgpl-configuration.md)
has the details.

CI decodes a sample of each of these on every target and compares frame count, size, pixel format,
per-frame timestamps, colour tags and a SHA-256 of the pixels with values from an independent
decoder:

| Codec | Container | Notes |
| --- | --- | --- |
| H.264 | MP4, Matroska | 8 bit, B-frames, one file with a variable frame rate |
| HEVC | Matroska | 10 bit, BT.2020 with PQ |
| AV1 | MP4 | |
| VP9, VP8 | WebM | |
| ProRes | MOV | 10 bit 4:2:2 |
| FFV1 | Matroska | 12 bit |
| MPEG-2 | MPEG-TS | interlaced, also run through `bwdif` and `yadif` |
| MPEG-4 Part 2, Motion JPEG | AVI | |
| DNxHR | MXF | |
| GIF, APNG, animated WebP | their own | |

FFmpeg decodes animated WebP since version 9.0, so it works here.

## Use it from Rust

1. Build the archive for your target ([below](#build-it-yourself)) and unpack it into an empty
   directory.
2. Depend on `ffmpeg-next` with the `static` feature and without its default features, which would
   ask for libraries that are not in the archive:

   ```toml
   [dependencies]
   ffmpeg-next = { version = "=9.1.0", default-features = false, features = ["codec", "filter", "format", "static"] }
   ```

3. Build with `FFMPEG_DIR` set to the directory you unpacked into:

   ```sh
   FFMPEG_DIR=/path/to/unpacked cargo build --release
   ```

`ffmpeg-sys-next` generates its bindings at build time, so the build machine needs libclang and a
C compiler. FFmpeg itself does not need to be installed. [smoke-test/](smoke-test) is a complete
program that works this way.

Things to know:

- `ffmpeg-next` versions follow FFmpeg's. Use a crate version that supports the FFmpeg version in
  `versions.env`.
- cargo does not notice when the libraries under `FFMPEG_DIR` change. Run
  `cargo clean -p ffmpeg-sys-next` after you replace them.
- For a `*-linux-musl` target built on a glibc machine, bindgen needs the musl headers. On Debian
  and Ubuntu that is the `musl-tools` package. The resulting binary is fully static.
- For a `*-linux-gnu` target, the libraries need glibc 2.28, but the glibc your own binary needs is
  set by the machine you link on. To run on old distributions, link on one.

## Licence and source code

The scripts in this repository are under the [MIT licence](LICENSE).

The libraries they produce are a different matter. FFmpeg is licensed under the GNU Lesser General
Public License, version 2.1 or later. dav1d is under the BSD 2-Clause licence and zlib under the
zlib licence. Every archive carries the three licence texts in `licenses/`.

If you ship a program that links these libraries, the LGPL asks you to let your users replace the
FFmpeg part. Two things make that possible:

- `BUILD-INFO` in every archive names the upstream URL and SHA-256 of each source archive and the
  full configure command of each library.
- The build scripts are in this repository, and `BUILD-INFO` names the revision that ran.

This describes how the archives are put together. It is not legal advice.

## Reproducible archives

Two builds of one commit gave byte-identical archives for both x86_64 Linux targets. The aarch64
targets go through the same steps but have not been compared yet.

The archive entries are sorted and carry the commit's time, and the libraries hold no timestamp,
user name or build path. The sources and the container images are pinned by checksum. The compiler
and the other build tools are not: the build installs them from the distribution's package
repository, so a package update there can change the bytes. `BUILD-INFO` records the compiler and
nasm versions that ran.

## Build it yourself

You need podman or docker for the Linux targets. The machine's architecture has to match the
target's.

```sh
scripts/fetch-sources.sh
scripts/build-linux.sh x86_64-unknown-linux-gnu
scripts/smoke-test.sh x86_64-unknown-linux-gnu
```

The archive lands in `dist/`. [AGENTS.md](AGENTS.md) lists every command, including how to update
a pinned version.
