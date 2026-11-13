#!/usr/bin/env bash
# Builds one Linux target inside its pinned container (versions.env), with
# podman or docker. The container matches the machine's architecture, so run
# this on x86_64 for the x86_64 targets and on aarch64 for the aarch64 ones.
#
# Usage: scripts/build-linux.sh <target>
#
# Environment:
#   CONTAINER_ENGINE   podman or docker (default: podman if installed)
#   SOURCES_DIR        verified source archives (default: sources/)
#   OUT_DIR            where the archive goes (default: dist/)
#   JOBS               parallel compile jobs (default: all cores)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target=${1:-}
case "$target" in
    *-unknown-linux-gnu) image="docker.io/library/almalinux:$GLIBC_IMAGE_TAG@$GLIBC_IMAGE_DIGEST" ;;
    *-unknown-linux-musl) image="docker.io/library/alpine:$MUSL_IMAGE_TAG@$MUSL_IMAGE_DIGEST" ;;
    *) die "usage: scripts/build-linux.sh <linux target>" ;;
esac

engine=$(container_engine)

sources=${SOURCES_DIR:-"$REPO_ROOT/sources"}
out=${OUT_DIR:-"$REPO_ROOT/dist"}
verify_sources "$sources"
# Created here so the directory belongs to the calling user even when the
# container runs as root.
mkdir -p "$out"

# The container has no git, so the values that scripts/build.sh would read
# from the checkout are passed in.
default_build_identity

# The repository and the sources are mounted read-only. The build happens in
# the container's own /work, and only the archive is written to the host.
# shellcheck disable=SC2016 # $1 is for the shell inside the container
"$engine" run --rm \
    --volume "$REPO_ROOT:/repo:ro,z" \
    --volume "$sources:/sources:ro,z" \
    --volume "$out:/out:z" \
    --env SOURCES_DIR=/sources \
    --env OUT_DIR=/out \
    --env WORK_DIR=/work \
    --env SOURCE_DATE_EPOCH \
    --env BUILD_REVISION \
    ${JOBS:+--env "JOBS=$JOBS"} \
    "$image" \
    sh -euc '. /repo/scripts/linux-setup.sh; exec bash /repo/scripts/build.sh "$1"' sh "$target"
