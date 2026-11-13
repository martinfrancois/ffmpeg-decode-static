#!/usr/bin/env bash
# Checks the files of a release, writes their checksums and prints the release
# notes. The release job of .github/workflows/build.yml runs it for a tag.
#
# Usage: scripts/release.sh <tag> [directory] >dist/release-notes.md
#
# <tag> is v<FFmpeg version>-<build number>, for example v9.0.2-1.
# [directory] (default: dist/release) must hold the archive of every target
# and the three source archives, and nothing else. The script writes
# checksums.txt into it.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag=${1:-}
dir=${2:-"$REPO_ROOT/dist/release"}
repository=${GITHUB_REPOSITORY:-martinfrancois/ffmpeg-decode-static}
if [ -z "$tag" ] || [ ! -d "$dir" ]; then
    die "usage: scripts/release.sh <tag> [directory]"
fi

build_number=${tag#"v$FFMPEG_VERSION-"}
case "$build_number" in
    "$tag" | "" | 0* | *[!0-9]*)
        die "the tag $tag does not fit FFmpeg $FFMPEG_VERSION in versions.env, expected v$FFMPEG_VERSION-<build number>"
        ;;
esac

rm -f "$dir/checksums.txt"
expected=$(
    {
        for target in $ALL_TARGETS; do
            printf 'ffmpeg-decode-static-%s.tar.xz\n' "$target"
        done
        source_table | cut -d' ' -f2
    } | LC_ALL=C sort
)
actual=$(find "$dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)
if [ "$actual" != "$expected" ]; then
    printf 'expected:\n%s\nfound:\n%s\n' "$expected" "$actual" >&2
    die "$dir does not hold exactly the files of a release"
fi
verify_sources "$dir"

# The format that "cksum --tag" writes, so "cksum --check" reads both digests.
# Each digest goes through a variable, so a failing tool stops the script.
while read -r name; do
    sha256=$(sha256_of "$dir/$name")
    sha3_256=$(sha3_256_of "$dir/$name")
    printf 'SHA256 (%s) = %s\nSHA3-256 (%s) = %s\n' "$name" "$sha256" "$name" "$sha3_256"
done <<<"$expected" >"$dir/checksums.txt"
log "wrote $dir/checksums.txt"

cat <<EOF_NOTES
Decode-only, LGPL, static FFmpeg $FFMPEG_VERSION libraries for linking into Rust programs. This is build $build_number of this FFmpeg version.

## Archives

| Archive | Needs |
| --- | --- |
EOF_NOTES
for target in $ALL_TARGETS; do
    archive=ffmpeg-decode-static-$target.tar.xz
    needs=$(gnu_tar -xOf "$dir/$archive" BUILD-INFO | sed -n 's/^needs: *//p')
    [ -n "$needs" ] || die "$archive has no \"needs:\" line in BUILD-INFO"
    # shellcheck disable=SC2016 # the backticks are Markdown
    printf '| `%s` | %s |\n' "$archive" "$needs"
done
cat <<EOF_NOTES

[README.md](https://github.com/$repository/blob/$tag/README.md) says how a Rust program links an archive. \`BUILD-INFO\` in each archive has the exact build commands.

## Sources

The libraries are under the LGPL, version 2.1 or later, with dav1d (BSD 2-Clause) and zlib (zlib licence) inside \`libavcodec\`. The source archives they were built from are attached to this release, unchanged from upstream:

| Source | Upstream URL | SHA-256 |
| --- | --- | --- |
EOF_NOTES
while read -r _ name url sha; do
    # shellcheck disable=SC2016 # the backticks are Markdown
    printf '| `%s` | %s | `%s` |\n' "$name" "$url" "$sha"
done < <(source_table)
cat <<EOF_NOTES

## Checksums

\`checksums.txt\` has a SHA-256 and a SHA3-256 digest of every other file of this release. [README.md](https://github.com/$repository/blob/$tag/README.md#download) shows how to check a download with it.
EOF_NOTES
