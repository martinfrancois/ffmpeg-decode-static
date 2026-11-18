#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$repo/scripts/lib.sh"
source_archive=${1:?pass the pinned FFmpeg source archive}
mkdir -p "$repo/build"
work=$(mktemp -d "$repo/build/patch-test.XXXXXX")
trap 'rm -rf "${work:?}"' EXIT
"$repo/scripts/package-patches.sh" "$work/one"
"$repo/scripts/package-patches.sh" "$work/two"
cmp "$work/one/$FFMPEG_PATCH_ARCHIVE" "$work/two/$FFMPEG_PATCH_ARCHIVE"
mkdir "$work/patches"
tar -xf "$work/one/$FFMPEG_PATCH_ARCHIVE" -C "$work/patches"
tar -xf "$source_archive" -C "$work"
"$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"
if "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
tar -xf "$source_archive" -C "$work"
printf '\n' >>"$work/patches/0001-reject-invalid-mpeg-motion-codes.patch"
if "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
tar -xf "$work/one/$FFMPEG_PATCH_ARCHIVE" -C "$work/patches"
printf 'wrong-version\n' >"$work/ffmpeg-$FFMPEG_VERSION/RELEASE"
if "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
tar -xf "$source_archive" -C "$work"
printf '\n' >>"$work/ffmpeg-$FFMPEG_VERSION/libavcodec/mpeg12dec.c"
if "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
rm "$work/patches/series"
if "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
tar -xf "$work/one/$FFMPEG_PATCH_ARCHIVE" -C "$work/patches"
tar -xf "$source_archive" -C "$work"
# Even a patch tool that exits successfully without changing the source is refused.
mkdir "$work/fake-bin"
printf '#!/bin/sh\nexit 0\n' >"$work/fake-bin/gpatch"
chmod +x "$work/fake-bin/gpatch"
if PATH="$work/fake-bin:$PATH" "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
printf '#!/bin/sh\nexit 1\n' >"$work/fake-bin/gpatch"
if PATH="$work/fake-bin:$PATH" "$repo/scripts/apply-patches.sh" "$work/ffmpeg-$FFMPEG_VERSION" "$work/patches"; then exit 1; fi
# File timestamps and permissions do not change the patch source archive.
touch "$work/patches/series"
chmod 600 "$work/patches/series"
pack_patches "$work/patches" >"$work/retimed.tar"
cmp "$work/one/$FFMPEG_PATCH_ARCHIVE" "$work/retimed.tar"
printf 'patch packaging, application, repeated application and tamper checks passed\n'
