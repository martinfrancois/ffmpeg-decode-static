# Shared helpers. Source this file, do not run it.
# shellcheck shell=bash

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../versions.env
. "$REPO_ROOT/versions.env"

FFMPEG_ARCHIVE="ffmpeg-$FFMPEG_VERSION.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/$FFMPEG_ARCHIVE"
DAV1D_ARCHIVE="dav1d-$DAV1D_VERSION.tar.xz"
DAV1D_URL="https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/$DAV1D_ARCHIVE"
ZLIB_ARCHIVE="zlib-$ZLIB_VERSION.tar.xz"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/$ZLIB_ARCHIVE"

# Every target this repository builds, as Rust target triples.
ALL_TARGETS="
x86_64-unknown-linux-gnu
aarch64-unknown-linux-gnu
x86_64-unknown-linux-musl
aarch64-unknown-linux-musl
"

log() {
    printf '==> %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# Prints "<versions.env prefix> <archive> <url> <sha256>" for each source archive.
source_table() {
    printf '%s %s %s %s\n' \
        FFMPEG "$FFMPEG_ARCHIVE" "$FFMPEG_URL" "$FFMPEG_SHA256" \
        DAV1D "$DAV1D_ARCHIVE" "$DAV1D_URL" "$DAV1D_SHA256" \
        ZLIB "$ZLIB_ARCHIVE" "$ZLIB_URL" "$ZLIB_SHA256"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Fails unless the file has the expected SHA-256.
verify_sha256() {
    local file=$1 expected=$2 actual
    actual=$(sha256_of "$file")
    if [ "$actual" != "$expected" ]; then
        die "checksum mismatch for $(basename "$file"): expected $expected, got $actual"
    fi
}

# Fails unless every source archive is in the directory with the pinned checksum.
verify_sources() {
    local dir=$1 name sha
    while read -r _ name _ sha; do
        [ -f "$dir/$name" ] || die "$dir/$name is missing, run scripts/fetch-sources.sh"
        verify_sha256 "$dir/$name" "$sha"
    done < <(source_table)
}

# podman if it is installed, docker otherwise, unless the caller chose.
container_engine() {
    if [ -n "${CONTAINER_ENGINE:-}" ]; then
        printf '%s\n' "$CONTAINER_ENGINE"
    elif command -v podman >/dev/null 2>&1; then
        echo podman
    else
        echo docker
    fi
}

# The timestamp of the archive entries and the revision in BUILD-INFO come
# from the checkout unless the caller sets them.
default_build_identity() {
    if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
        SOURCE_DATE_EPOCH=$(git -C "$REPO_ROOT" log -1 --format=%ct) ||
            die "set SOURCE_DATE_EPOCH when building outside a git checkout"
    fi
    if [ -z "${BUILD_REVISION:-}" ]; then
        BUILD_REVISION=$(git -C "$REPO_ROOT" rev-parse HEAD) ||
            die "set BUILD_REVISION when building outside a git checkout"
    fi
    export SOURCE_DATE_EPOCH BUILD_REVISION
}

is_known_target() {
    local target
    for target in $ALL_TARGETS; do
        [ "$target" = "$1" ] && return 0
    done
    return 1
}

# GNU tar is required for reproducible archives. macOS ships it as gtar.
gnu_tar() {
    if command -v gtar >/dev/null 2>&1; then
        gtar "$@"
    elif tar --version 2>/dev/null | grep -q 'GNU tar'; then
        tar "$@"
    else
        die "GNU tar not found (on macOS: brew install gnu-tar)"
    fi
}
