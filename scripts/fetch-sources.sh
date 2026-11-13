#!/usr/bin/env bash
# Downloads the FFmpeg, dav1d and zlib source archives pinned in versions.env
# and verifies their SHA-256 checksums.
#
# Usage: scripts/fetch-sources.sh [directory]     (default: sources/)
#        scripts/fetch-sources.sh --print-checksums
#
# --print-checksums downloads the pinned versions to a temporary directory in
# build/ and prints the *_SHA256 lines for versions.env without verifying
# anything. Use it after a version bump, and compare the output with the
# checksum or signature the upstream project publishes before committing it.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

download() {
    local url=$1 out=$2
    curl --fail --silent --show-error --location --retry 3 --output "$out.part" "$url"
    mv "$out.part" "$out"
}

if [ "${1:-}" = "--print-checksums" ]; then
    mkdir -p "$REPO_ROOT/build"
    tmp=$(mktemp -d "$REPO_ROOT/build/checksums.XXXXXX")
    trap 'rm -rf "${tmp:?}"' EXIT
    while read -r prefix name url _; do
        download "$url" "$tmp/$name"
        printf '%s_SHA256=%s\n' "$prefix" "$(sha256_of "$tmp/$name")"
    done < <(source_table)
    exit 0
fi

dest=${1:-"$REPO_ROOT/sources"}
mkdir -p "$dest"

while read -r _ name url sha; do
    if [ -f "$dest/$name" ] && [ "$(sha256_of "$dest/$name")" = "$sha" ]; then
        log "$name is already present"
        continue
    fi
    log "downloading $url"
    download "$url" "$dest/$name"
    verify_sha256 "$dest/$name" "$sha"
done < <(source_table)

log "sources verified in $dest"
