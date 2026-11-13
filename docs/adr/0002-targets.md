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
  for fully static binaries.
* A cross-compiled FFmpeg cannot be tested on the machine that built it. A broken build should
  fail in the job that made it.
* GitHub's hosted runners are free for public repositories and exist for x86_64 and aarch64
  Linux.

## Considered Options

* Build every target on a runner of its own architecture, inside a container that fixes the C
  library
* Cross-compile every target from one x86_64 Linux runner

## Decision Outcome

Chosen option: "Build every target on a runner of its own architecture, inside a container that
fixes the C library", because the job that builds a target can link the smoke test against the
result and run it.

| Target | Runner | Build environment |
| --- | --- | --- |
| `x86_64-unknown-linux-gnu` | `ubuntu-24.04` | AlmaLinux 8 container |
| `aarch64-unknown-linux-gnu` | `ubuntu-24.04-arm` | AlmaLinux 8 container |
| `x86_64-unknown-linux-musl` | `ubuntu-24.04` | Alpine container |
| `aarch64-unknown-linux-musl` | `ubuntu-24.04-arm` | Alpine container |

`scripts/build.sh` refuses to run when the machine's architecture differs from the target's.

The musl libraries are built in Alpine because its compiler targets musl natively. The smoke test
for them runs on the runner itself, with Rust's own `*-unknown-linux-musl` target, because that is
how a Rust program links them. Rust brings its own copy of musl, which can be older than Alpine's.
The smoke test is the check that the two fit together.

### Consequences

* Good, because each target is tested where it was built, on real hardware of its architecture.
* Good, because the build scripts have no cross-compilation mode to maintain.
* Bad, because a local build of an aarch64 target needs an aarch64 machine or emulation.

### Confirmation

The `build` job in `.github/workflows/build.yml` has one matrix entry per target and runs
`scripts/smoke-test.sh` after the build. The `ci` job fails when any entry fails.
