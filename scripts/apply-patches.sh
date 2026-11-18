#!/usr/bin/env bash
# Verifies the exact patch series and source files before applying any change.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source_dir=${1:?pass the extracted FFmpeg directory}
patch_dir=${2:?pass the extracted patch directory}
patch_dir=$(cd "$patch_dir" && pwd)
verify_patch_directory "$patch_dir"
[ "$(cat "$source_dir/RELEASE")" = "$FFMPEG_VERSION" ] ||
    die "cannot patch version \"$source_dir\": expected FFmpeg $FFMPEG_VERSION"
while read -r before _ path; do
    verify_sha256 "$source_dir/$path" "$before"
done <"$patch_dir/files"
while read -r sha name; do
    verify_sha256 "$patch_dir/$name" "$sha"
    gnu_patch --batch --forward --fuzz=0 --no-backup-if-mismatch \
        -d "$source_dir" -p1 -i "$patch_dir/$name"
done <"$patch_dir/series"
while read -r _ after path; do
    verify_sha256 "$source_dir/$path" "$after"
done <"$patch_dir/files"
