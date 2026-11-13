#!/usr/bin/env bash
# Unpacks the archive of one target into an empty directory, builds the Rust
# program in smoke-test/ against it, runs it on samples/ and checks that the
# binary loads no FFmpeg, dav1d or zlib shared library.
#
# Needs cargo with the target's Rust toolchain, a C compiler and libclang
# (ffmpeg-sys-next generates its bindings with bindgen at build time).
#
# Usage: scripts/smoke-test.sh <target> [archive]
#        (default archive: dist/ffmpeg-decode-static-<target>.tar.xz)
#
# Environment:
#   WORK_DIR   scratch directory (default: build/smoke-<target>)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target=${1:-}
is_known_target "$target" || die "usage: scripts/smoke-test.sh <target> [archive]"
archive=${2:-"$REPO_ROOT/dist/ffmpeg-decode-static-$target.tar.xz"}
[ -f "$archive" ] || die "$archive not found"

work=${WORK_DIR:-"$REPO_ROOT/build/smoke-$target"}
mkdir -p "$work"
# The Rust build is thrown away too: cargo does not notice that a static
# library under FFMPEG_DIR changed, and would test the previous one.
rm -rf "${work:?}/ffmpeg" "${work:?}/target"
mkdir "$work/ffmpeg"
gnu_tar -xf "$archive" -C "$work/ffmpeg"

for entry in BUILD-INFO include lib/pkgconfig licenses/FFmpeg-COPYING.LGPLv2.1 licenses/dav1d-COPYING licenses/zlib-LICENSE; do
    [ -e "$work/ffmpeg/$entry" ] || die "the archive has no $entry"
done

log "building the smoke test for $target"
# cargo runs in smoke-test/ so that rustup picks up its rust-toolchain.toml.
cd "$REPO_ROOT/smoke-test"
if command -v rustup >/dev/null 2>&1; then
    # Installs the toolchain that rust-toolchain.toml names.
    rustup toolchain install
    rustup target add "$target"
fi
export FFMPEG_DIR="$work/ffmpeg" CARGO_TARGET_DIR="$work/target"
cargo clippy --release --locked --target "$target" -- --deny warnings
cargo build --release --locked --target "$target"

binary=$work/target/$target/release/smoke-test
"$binary" "$REPO_ROOT/samples"

log "checking shared library dependencies"
case "$target" in
    *-linux-musl)
        # A static executable has no dynamic section at all.
        dynamic=$(readelf --dynamic "$binary")
        if grep -q NEEDED <<<"$dynamic"; then
            printf '%s\n' "$dynamic" >&2
            die "the musl binary is not fully static"
        fi
        ;;
    *-linux-gnu)
        dependencies=$(ldd "$binary")
        printf '%s\n' "$dependencies"
        if printf '%s\n' "$dependencies" | grep -E -i 'libav|libsw|dav1d|libz\.'; then
            die "the binary loads a shared library that should be linked statically"
        fi
        ;;
esac

log "smoke test passed for $target"
