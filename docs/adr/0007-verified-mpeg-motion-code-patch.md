---
status: accepted
date: 2026-11-18
decision-makers: [martinfrancois]
consulted: []
informed: [Future maintainers and agents working on this repository]
---

# A verified MPEG motion-code patch

## Context and Problem Statement

FFmpeg 9.0.2 returns 65535 for an invalid MPEG motion VLC. Ten callers use that
value without checking it. Damaged frame-coded MPEG-1 and MPEG-2 B pictures
therefore decode without an error even with `err_detect=explode`. A small
correction is available at the decoder boundary, without another parser.

## Considered Options

* Keep the upstream decoder unchanged
* Apply a verified source patch and distribute it with the original sources
* Parse macroblocks again in every consumer

## Decision Outcome

Prepare the verified source patch for review. The helper returns motion decoding
status separately from the signed vector and checks all ten callers before use.
The original source archive stays unchanged and retains its upstream checksum.
The patch includes a dated modification notice in the changed source file.

The patch archive has a separate pin in versions.env. Its manifest records patch
hashes and before/after hashes for changed files. Archive creation normalizes
metadata with Python's standard USTAR writer. GNU tar versions differed in unused
header fields during GNU/musl preparation, so the patch archive does not use the
platform's tar writer. The patch bundle is small and stays uncompressed. Every target verifies and applies the same archive before configure;
a missing patch, wrong version, rejected hunk or digest mismatch stops the build.
GNU patch is an explicit prerequisite on every platform.

Releases carry the original source archives plus the patch archive. Library
archives embed the same patch material. BUILD-INFO records the archive digest,
application command and patch manifest. A future FFmpeg version requires a
reviewed rebase of this series; a version bump must not silently remove it.

The regression suite links the actual built libraries. Invalid streams must
return InvalidData from the packet/frame API under explode. Valid twins must
retain their 30 frames and independently measured luma hashes. Existing smoke
checks remain in place. The source correction does not address coefficient
saturation or expand the supported syntax.

## Consequences

Consumers with explode receive an error for the reproduced invalid motion codes.
Without explode, FFmpeg's existing concealment/error-resilience policy still
applies. This is a maintained downstream change until an upstream version
provides equivalent behavior. Platform builds and native review remain necessary
before publication. The record is proposed until that review is accepted.
