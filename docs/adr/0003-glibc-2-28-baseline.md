---
status: accepted
date: 2026-11-13
decision-makers: [martinfrancois]
consulted: [implementing coding agent]
informed: [Future maintainers and agents working on this repository]
---

# The glibc targets are built on AlmaLinux 8, against glibc 2.28

## Context and Problem Statement

A static library compiled against a new glibc can refer to functions that an older glibc does not
have. A program that links such a library then fails to link, or to start, on an older
distribution. The `*-linux-gnu` libraries need a stated oldest glibc.

Which glibc are they built against, and in which container?

## Decision Drivers

* The owner asked for binaries that run on older distributions, and named manylinux_2_28 as an
  example.
* Renovate has to be able to propose a newer image, and the owner's Renovate setup waits seven
  days after a release, which needs a release date for every image.
* One image for both architectures means one pin.

## Considered Options

* The official `almalinux:8` image, with GCC 14 from its `gcc-toolset-14` packages
* The `quay.io/pypa/manylinux_2_28_*` images
* An image of a current distribution

## Decision Outcome

Chosen option: "The official `almalinux:8` image, with GCC 14 from its `gcc-toolset-14`
packages", because it gives the same glibc 2.28 and the same compiler series as manylinux_2_28
from one image that Renovate can date.

glibc 2.28 came out in August 2018. Debian 10, Ubuntu 18.10, RHEL 8 and everything newer have it.

`versions.env` pins the image by a dated tag and its digest. An image update must stay on major
version 8, because AlmaLinux 9 has glibc 2.34.

### Consequences

* Good, because the libraries link on any distribution with glibc 2.28 or newer.
* Good, because the tag on Docker Hub is one multi-architecture image with a push date, so one pin
  covers x86_64 and aarch64 and Renovate's waiting period works.
* Bad, because the build installs the compiler with `dnf` on every run, which takes about a
  minute, and the package versions are whatever AlmaLinux 8 serves that day. `BUILD-INFO` records
  the compiler and assembler versions that ran.
* Neutral: the baseline is what the libraries need. The glibc a finished program needs is set
  where that program is linked.

### Confirmation

`scripts/build.sh` stops when the glibc of the machine it runs on differs from `GLIBC_VERSION` in
`versions.env`, and writes that version into `BUILD-INFO` ("runs on: glibc 2.28 or newer").

## Pros and Cons of the Options

### The `quay.io/pypa/manylinux_2_28_*` images

* Good, because the compiler is already installed.
* Bad, because there is one image per architecture, so two pins.
* Bad, because quay.io gives Renovate no release date, so updates would wait forever or need a
  custom datasource.

### An image of a current distribution

* Bad, because the libraries could then need a glibc that older distributions lack.
