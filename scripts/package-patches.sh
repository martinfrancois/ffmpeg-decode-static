#!/usr/bin/env bash
# Creates the deterministic patch source archive alongside the upstream archives.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
dest=${1:-"$REPO_ROOT/sources"}
mkdir -p "$dest"
pack_patches "$REPO_ROOT/patches/ffmpeg-$FFMPEG_VERSION" >"$dest/$FFMPEG_PATCH_ARCHIVE.part"
verify_sha256 "$dest/$FFMPEG_PATCH_ARCHIVE.part" "$FFMPEG_PATCH_SHA256"
mv "$dest/$FFMPEG_PATCH_ARCHIVE.part" "$dest/$FFMPEG_PATCH_ARCHIVE"
