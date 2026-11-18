#!/usr/bin/env bash
# Tests packaging only. Synthetic archives are never published or smoke-tested.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
source_dir=${1:?pass the verified sources directory}
mkdir -p "$REPO_ROOT/build"
work=$(mktemp -d "$REPO_ROOT/build/release-test.XXXXXX")
trap 'rm -rf "${work:?}"' EXIT
mkdir "$work/release" "$work/package"
while read -r _ name _ _; do cp "$source_dir/$name" "$work/release/$name"; done < <(source_table)
cp "$source_dir/$FFMPEG_PATCH_ARCHIVE" "$work/release/"
cp -R "$REPO_ROOT/patches/ffmpeg-$FFMPEG_VERSION" "$work/package/patches"
printf 'needs: test-only\nPatch archive: %s\nSHA-256: %s\n' \
    "$FFMPEG_PATCH_ARCHIVE" "$FFMPEG_PATCH_SHA256" >"$work/package/BUILD-INFO"
for target in $ALL_TARGETS; do
    gnu_tar -C "$work/package" -cJf "$work/release/ffmpeg-decode-static-$target.tar.xz" BUILD-INFO patches
done
"$REPO_ROOT/scripts/release.sh" "v$FFMPEG_VERSION-2" "$work/release" >"$work/notes"
mv "$work/release/$FFMPEG_PATCH_ARCHIVE" "$work/saved.tar"
if "$REPO_ROOT/scripts/release.sh" "v$FFMPEG_VERSION-2" "$work/release" >"$work/notes"; then exit 1; fi
cp "$work/saved.tar" "$work/release/$FFMPEG_PATCH_ARCHIVE"
printf '\n' >>"$work/release/$FFMPEG_PATCH_ARCHIVE"
if "$REPO_ROOT/scripts/release.sh" "v$FFMPEG_VERSION-2" "$work/release" >"$work/notes"; then exit 1; fi
cp "$work/saved.tar" "$work/release/$FFMPEG_PATCH_ARCHIVE"
# A correct filename with old provenance must not pass release validation.
printf 'needs: test-only\n' >"$work/package/BUILD-INFO"
gnu_tar -C "$work/package" -cJf "$work/release/ffmpeg-decode-static-x86_64-unknown-linux-gnu.tar.xz" BUILD-INFO patches
if "$REPO_ROOT/scripts/release.sh" "v$FFMPEG_VERSION-2" "$work/release" >"$work/notes"; then exit 1; fi
printf 'needs: test-only\nPatch archive: %s\nSHA-256: %s\n' \
    "$FFMPEG_PATCH_ARCHIVE" "$FFMPEG_PATCH_SHA256" >"$work/package/BUILD-INFO"
printf '\n' >>"$work/package/patches/series"
gnu_tar -C "$work/package" -cJf "$work/release/ffmpeg-decode-static-x86_64-unknown-linux-gnu.tar.xz" BUILD-INFO patches
if "$REPO_ROOT/scripts/release.sh" "v$FFMPEG_VERSION-2" "$work/release" >"$work/notes"; then exit 1; fi
printf 'release accepts the complete source set and rejects stale or altered patch material\n'
