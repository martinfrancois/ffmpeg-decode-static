---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# x86_64 Linux objects carry no relaxable GOT relocations

## Context and Problem Statement

The first musl build, made in Alpine 3.24 with GCC 15.2 and binutils 2.45.1, linked into the
smoke test without an error and then crashed in `avformat_open_input`. The same libraries worked
in a C program linked inside Alpine.

GCC 15 compiles "push the address of a function" into `push foo@GOTPCREL(%rip)`. The assembler in
binutils 2.45 marks that instruction with the relocation `R_X86_64_GOTPCRELX`, which tells the
linker it may rewrite the instruction. GNU ld 2.40, the linker on the machine that linked the
smoke test, only knows that marking on `call`, `jmp` and `mov`. It rewrote the `push` into a
`call`, so the program called the function instead of passing its address.

A static library is linked by whatever linker its user has. How do the libraries stay correct with
linkers older than the toolchain that built them?

## Decision Drivers

* The failure is silent at link time and a crash, or worse, at run time.
* Common distributions ship linkers older than binutils 2.45. Debian 12 has 2.40 and Ubuntu 24.04
  has 2.42.
* The protection should not depend on which compiler version a container image happens to have.

## Considered Options

* Assemble with `-Wa,-mrelax-relocations=no` and fail the build if a relaxable relocation remains
* Build in an older Alpine whose toolchain does not emit the instruction
* Tell users to link with a recent linker

## Decision Outcome

Chosen option: "Assemble with `-Wa,-mrelax-relocations=no` and fail the build if a relaxable
relocation remains", because it removes the whole class of rewrites for every toolchain version,
and a check can prove it.

`scripts/build.sh` passes the flag to the C compiler for zlib, dav1d and FFmpeg on x86_64 Linux,
for both glibc and musl. The assembler then emits the plain `R_X86_64_GOTPCREL`, which every
linker leaves alone. After the build, `readelf` lists the relocations of the four libraries and
the script stops if any `GOTPCRELX` is among them.

### Consequences

* Good, because the libraries link correctly with old and new linkers.
* Bad, because the linker can no longer turn a load from the global offset table into a direct
  address. Some accesses to global symbols cost one extra memory read. The hot loops of FFmpeg and
  dav1d are hand-written assembly built by nasm, which this does not touch.
* Neutral: aarch64 has no such assembler marking, so the flag is not passed there.

### Confirmation

The `readelf` check in `scripts/build.sh`. The smoke test for `x86_64-unknown-linux-musl` crashed
before this change and passes with it.

## Pros and Cons of the Options

### Build in an older Alpine whose toolchain does not emit the instruction

* Good, because it needs no flag.
* Bad, because the next image update brings the problem back, and CI only notices while its own
  linker is older than the image's assembler.

### Tell users to link with a recent linker

* Bad, because a user who misses the note gets a program that crashes, with no hint why.
