---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# Windows builds use MSVC under MSYS2, once per C runtime

## Context and Problem Statement

Rust's usual Windows target is `x86_64-pc-windows-msvc`. A static library for it has to be built by
the MSVC compiler, against one of MSVC's two C runtimes. FFmpeg's build system is a shell script
and makefiles, which Windows cannot run on its own.

How are the Windows libraries built, and for which C runtime?

## Decision Drivers

* The libraries have to come from the same pinned, unpatched source archives and the same
  configure flags as on the other platforms, so that `BUILD-INFO` and the attached sources describe
  them fully.
* The result has to be decode-only: no encoders, muxers, network or hardware acceleration.
* A Rust program picks its C runtime with one compiler flag, and a static library only links
  cleanly with a program that uses the same one.
* The build should use what GitHub's Windows runner already has.

## Considered Options

* MSYS2 as the shell, with FFmpeg's `--toolchain=msvc`, built by `scripts/build.sh`
* The `ffmpeg` port of vcpkg with a static triplet
* MinGW-w64 GCC instead of MSVC

## Decision Outcome

Chosen option: "MSYS2 as the shell, with FFmpeg's `--toolchain=msvc`, built by `scripts/build.sh`",
because it is the only option that builds the pinned sources with this repository's flags, and
vcpkg runs the same combination underneath anyway.

`scripts/msvc-env.cmd` loads the 64-bit MSVC environment with `vcvarsall.bat` and starts
`scripts/build.sh` in the MSYS2 bash that the runner has in `C:\msys64`. MSYS2 only provides the
shell and the build tools around the compiler: make, nasm, pkgconf, `cmp`, tar and xz. The
compiler is `cl`, the librarian is `lib`, and nothing from MSYS2 or MinGW ends up in the
libraries. zlib builds with its own `win32/Makefile.msc` and dav1d with meson, both with `cl`.

The libraries are built twice:

| Archive | Compiler flag | For a Rust program built |
| --- | --- | --- |
| `x86_64-pc-windows-msvc` | `/MD`, the C runtime DLL | with Rust's defaults |
| `x86_64-pc-windows-msvc-crt-static` | `/MT`, the static C runtime | with `-C target-feature=+crt-static` |

Every object names its C runtime, so the linker warns or fails when the two kinds meet in one
program. Two archives are the only way to serve both kinds of program.

The build runs on `windows-2022`, the runner with the oldest Visual Studio (2022, MSVC 19.44).
Microsoft keeps its libraries compatible in one direction: a newer linker reads objects from an
older compiler. Building with the oldest compiler therefore gives the widest range of linkers.

The libraries use `BCryptGenRandom` for random numbers, as FFmpeg does on Windows by default. A
program has to link `bcrypt` itself, because `ffmpeg-sys-next` does not name system libraries when
it is given `FFMPEG_DIR`. README.md shows how.

`aarch64-pc-windows-msvc` is not built. FFmpeg and dav1d need `gas-preprocessor.pl` and perl to
assemble their arm64 code with MSVC's assembler. That means one more pinned download, Perl, and a
second way through the build for assembly. The target was wanted only if it came cheap, and this
is not cheap. Without the script the libraries would have no NEON code.

### Consequences

* Good, because Windows uses the same script, flags, checks and source archives as Linux and
  macOS.
* Good, because the smoke test links and runs each archive with its own C runtime setting.
* Bad, because every release carries two Windows archives and CI builds FFmpeg twice on Windows.
* Bad, because MSYS2 and its packages are whatever the runner image and `pacman` provide on the
  day of the build. `BUILD-INFO` records the compiler and nasm versions that ran.
* Bad, because a program needs the linker of Visual Studio 2022 version 17.14 or newer.
* Bad, because the archives are not reproducible. MSVC writes the build time into every object
  and the full path of the source file into many. `cl`, `lib` and nasm have switches against
  that, which this change does not try.
  [Issue 4](https://github.com/martinfrancois/ffmpeg-decode-static/issues/4) tracks it.

### Confirmation

The `build` job in `.github/workflows/build.yml` has one matrix entry per archive.
`scripts/smoke-test.sh` builds the test program with the matching C runtime setting, runs it, and
reads its imports with `dumpbin`: no FFmpeg, dav1d or zlib DLL for either archive, and no C runtime
DLL for the `crt-static` one.

## Pros and Cons of the Options

### MSYS2 as the shell, with FFmpeg's `--toolchain=msvc`, built by `scripts/build.sh`

* Good, because FFmpeg supports and documents this way of building with MSVC.
* Good, because the runner image already has MSYS2 and Visual Studio.
* Bad, because paths have to be translated between the two worlds in a few places of the script.

### The `ffmpeg` port of vcpkg with a static triplet

A trial ran on a `windows-2022` runner on 2026-11-13: vcpkg commit `9a5dfef` from 2026-10-30, port
`ffmpeg` 9.0.2 port-version 2, triplet `x64-windows-static-md`, features
`core,avcodec,avformat,avfilter,dav1d,zlib`.

* Good, because one command gives static MSVC libraries, in 23 minutes.
* Bad, because the port applies 14 patches to FFmpeg, so the libraries are not built from the
  upstream archive that a release attaches.
* Bad, because the port has no switch for a decode-only build. The result had 183 encoders, 184
  muxers, 28 hardware accelerators and 36 protocols including HTTP, TLS and RTMP. The port always
  passes `--enable-d3d11va --enable-d3d12va --enable-dxva2 --enable-mediafoundation
  --enable-schannel`, and a program then has to link eight more system libraries.
* Bad, because the versions come from the vcpkg checkout and not from `versions.env`. zlib was
  1.3.2 there.
* Neutral: its log shows it downloading MSYS2 and running FFmpeg's configure with
  `--toolchain=msvc`, the same combination as the chosen option.

### MinGW-w64 GCC instead of MSVC

* Good, because it needs no Visual Studio and can cross-compile from Linux.
* Bad, because the objects depend on MinGW's runtime and libgcc, which a program for
  `x86_64-pc-windows-msvc` does not link. It fits Rust's `x86_64-pc-windows-gnu` target, which
  nobody asked for.

## More Information

* FFmpeg's notes on building with MSVC: <https://ffmpeg.org/platform.html#Microsoft-Visual-C_002b_002b-or-Intel-C_002b_002b-Compiler-for-Windows>
* Microsoft on binary compatibility between Visual Studio versions:
  <https://learn.microsoft.com/en-us/cpp/porting/binary-compat-2015-2017>
