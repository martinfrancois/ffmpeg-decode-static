---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# dav1d and zlib are merged into libavcodec

## Context and Problem Statement

libavcodec and libavformat call dav1d and zlib. With `FFMPEG_DIR` set, the build script of
`ffmpeg-sys-next` 9.1 tells cargo to link `avcodec`, `avfilter`, `avformat` and `avutil`, and
nothing else. It does not know that this FFmpeg needs two more libraries.

How do dav1d and zlib reach the linker?

## Decision Drivers

* A Rust program should need `FFMPEG_DIR` and the `static` feature, and no build script of its
  own.
* It has to work with GNU ld, which resolves static libraries in the order they are named. A
  library named before the one that needs it contributes nothing.

## Considered Options

* Merge the objects of dav1d and zlib into `libavcodec.a`
* Ship `libdav1d.a` and `libz.a` next to the FFmpeg libraries and let each program link them
* Have programs find FFmpeg through pkg-config

## Decision Outcome

Chosen option: "Merge the objects of dav1d and zlib into `libavcodec.a`", because it is the only
option where the four libraries that `ffmpeg-sys-next` already links are complete.

`scripts/build.sh` appends both libraries to `libavcodec.a`, with an `ar` script on Linux and with
`libtool -static` on macOS, and removes `-ldav1d`, `-lz` and the build paths from the pkg-config
files. libavformat needs zlib too. It always links together with libavcodec, so the copy in
libavcodec serves both.

### Consequences

* Good, because a Rust program links the archive with no extra configuration.
* Bad, because the libraries export the plain `inflate`, `deflate` and `dav1d_*` symbols. A
  program that also links another static zlib or dav1d can get duplicate symbol errors. The README
  says so.
* Neutral: both licences allow it. The licence texts of dav1d and zlib are in `licenses/`, and
  `BUILD-INFO` says that `libavcodec.a` holds them.

### Confirmation

The smoke test depends on `ffmpeg-next` only, has no build script, and decodes AV1 and APNG, which
need dav1d and zlib. `scripts/build.sh` fails if a pkg-config file still names dav1d or `-lz`.

## Pros and Cons of the Options

### Ship `libdav1d.a` and `libz.a` next to the FFmpeg libraries

* Good, because every library stays as its own project built it.
* Bad, because each program needs a build script that names the two libraries. rustc puts the
  libraries of a crate before those of the crates it depends on, so the two would come before
  libavcodec on the link line, where GNU ld ignores them.

### Have programs find FFmpeg through pkg-config

* Good, because pkg-config files can carry private dependencies.
* Bad, because `ffmpeg-sys-next` only uses pkg-config when `FFMPEG_DIR` is unset, the build
  machine then needs pkg-config, and Windows machines normally have none.
