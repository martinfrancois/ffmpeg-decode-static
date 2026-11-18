#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=$(cd "${1:?pass an existing configured and built patched FFmpeg source directory}" && pwd)
# This test uses ELF section garbage collection and the build's static libraries.
# Keep all outputs separate from the supplied source/build tree.
mkdir -p "$repo/build"
work=$(mktemp -d "$repo/build/mpeg-motion-branches.XXXXXX")
trap 'rm -rf "${work:?}"' EXIT
. "$repo/versions.env"
cd "$source_dir"
while read -r _before after path; do
    printf '%s  %s\n' "$after" "$path"
done < "$repo/patches/ffmpeg-$FFMPEG_VERSION/files" > "$work/source.sha256"
sha256sum -c "$work/source.sha256"
# Match FFmpeg configure's exclusions for warnings in the included decoder.
"${CC:-clang}" -O1 -Wno-parentheses -Wno-pointer-sign \
    -ffunction-sections -fdata-sections -I. -Ilibavcodec \
    "$repo/tests/mpeg-motion-branches.c" -Llibavformat -Llibavcodec -Llibavutil \
    -Wl,--gc-sections -lavformat -lavcodec -lavutil -lm -pthread \
    -o "$work/mpeg-motion-branches"
"$work/mpeg-motion-branches"
