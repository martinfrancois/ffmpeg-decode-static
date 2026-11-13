---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# Which targets are built, and where

## Context and Problem Statement

The libraries are for Rust programs, so a target here is a Rust target triple. Each one costs a CI
job on every pull request and a place where the build can break.

Which targets does the repository build, and on what machine does each one build?

## Decision Drivers

* The owner asked for Linux on x86_64 and aarch64, with glibc for ordinary distributions and musl
  for fully static binaries, and for macOS on Apple silicon and Intel with a stated oldest macOS.
* A cross-compiled FFmpeg cannot be tested on the machine that built it. A broken build should
  fail in the job that made it.
* GitHub's hosted runners are free for public repositories and exist for x86_64 and aarch64
  Linux and for both kinds of Mac.

## Considered Options

* Build every target on a runner of its own architecture, the Linux ones inside a container that
  fixes the C library
* Cross-compile every target from one x86_64 Linux runner

## Decision Outcome

Chosen option: "Build every target on a runner of its own architecture, the Linux ones inside a
container that fixes the C library", because the job that builds a target can link the smoke test
against the result and run it.

| Target | Runner | Build environment |
| --- | --- | --- |
| `x86_64-unknown-linux-gnu` | `ubuntu-24.04` | AlmaLinux 8 container |
| `aarch64-unknown-linux-gnu` | `ubuntu-24.04-arm` | AlmaLinux 8 container |
| `x86_64-unknown-linux-musl` | `ubuntu-24.04` | Alpine container |
| `aarch64-unknown-linux-musl` | `ubuntu-24.04-arm` | Alpine container |
| `aarch64-apple-darwin` | `macos-15` | the runner's Xcode, `MACOSX_DEPLOYMENT_TARGET=11.0` |
| `x86_64-apple-darwin` | `macos-15-intel` | the runner's Xcode and Homebrew's nasm, `MACOSX_DEPLOYMENT_TARGET=11.0` |
| `x86_64-pc-windows-msvc` | `windows-2022` | the runner's Visual Studio 2022 and MSYS2, `/MD` |
| `x86_64-pc-windows-msvc-crt-static` | `windows-2022` | the runner's Visual Studio 2022 and MSYS2, `/MT` |

`scripts/build.sh` refuses to run when the machine's architecture differs from the target's.

The musl libraries are built in Alpine because its compiler targets musl natively. The smoke test
for them runs on the runner itself, with Rust's own `*-unknown-linux-musl` target, because that is
how a Rust program links them. Rust brings its own copy of musl, which can be older than Alpine's.
The smoke test is the check that the two fit together.

The macOS libraries run on macOS 11.0 or newer. macOS 11 is the first release for Apple silicon,
so it is the oldest possible value for `aarch64-apple-darwin` and also Rust's own minimum for that
target. The Intel build uses the same number, so both archives make one promise. Rust would allow
an older macOS on Intel, and nobody asked for one. `versions.env` holds the value, and the build
stops unless every object records it. nasm only records it when the source asks, so on Intel the
build runs nasm through a wrapper that adds the request. The two macOS targets are separate
archives and not one universal library, because a Rust build links for one target at a time.

The two Windows archives are for one Rust target and differ in the C runtime.
[0006-windows-builds-with-msvc-under-msys2.md](0006-windows-builds-with-msvc-under-msys2.md) has
the reasons, and says why there is no `aarch64-pc-windows-msvc` archive.

### Consequences

* Good, because each target is tested where it was built, on real hardware of its architecture.
* Good, because the build scripts have no cross-compilation mode to maintain.
* Bad, because a local build of an aarch64 target needs an aarch64 machine or emulation.
* Bad, because macOS has no container: the Xcode version is whatever the runner image has, and it
  changes when GitHub updates the image. `BUILD-INFO` records the compiler that ran.
* Bad, because GitHub will retire the Intel Mac runners at some point. The x86_64 macOS target then
  needs cross-compilation from Apple silicon, or goes away.

### Confirmation

The `build` job in `.github/workflows/build.yml` has one matrix entry per target and runs
`scripts/smoke-test.sh` after the build. The `ci` job fails when any entry fails.
