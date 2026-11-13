#!/usr/bin/env bash
# Regenerates the test files in samples/ with a full FFmpeg (one that has
# encoders, unlike the libraries this repository builds).
#
# Usage: scripts/generate-samples.sh               uses "ffmpeg" from PATH
#        scripts/generate-samples.sh --container   runs in the pinned Alpine
#                                                  image with its ffmpeg package
#
# The committed files came from the --container form. Another FFmpeg version
# gives other bytes, and may give other timestamps. When Alpine no longer has
# the version below, change it here, and check the expectations in
# smoke-test/src/main.rs after regenerating.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

alpine_ffmpeg_version=8.1.3

if [ "${1:-}" = "--container" ]; then
    # shellcheck disable=SC2016 # $1 is for the shell inside the container
    exec "$(container_engine)" run --rm --volume "$REPO_ROOT:/repo:z" \
        "docker.io/library/alpine:$MUSL_IMAGE_TAG@$MUSL_IMAGE_DIGEST" \
        sh -euc 'apk add --no-cache bash "ffmpeg~$1" >&2; exec bash /repo/scripts/generate-samples.sh' \
        sh "$alpine_ffmpeg_version"
fi

out=$REPO_ROOT/samples
mkdir -p "$out"

# 64x64 pixels and five frames keep every file at a few kilobytes.
size=64x64
frames=5

# Encodes the test pattern. Arguments: output file, then encoder options.
encode() {
    local file=$1
    shift
    log "$file"
    ffmpeg -hide_banner -loglevel error -nostdin -y \
        -f lavfi -i "testsrc=size=${SIZE:-$size}:rate=${RATE:-25}" \
        -frames:v "${FRAMES:-$frames}" -an -threads 1 \
        -map_metadata -1 -fflags +bitexact -flags:v +bitexact \
        "$@" "$out/$file"
}

# Colour tags are set on the frames with the setparams filter. The ffmpeg
# program takes them from there and ignores -color_primaries and -color_trc
# given as encoder options.
bt709="setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
bt2020_pq="setparams=range=tv:color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc"

# H.264, 8 bit, with B-frames so decode order differs from display order.
encode h264-8bit.mp4 -vf "format=yuv420p,$bt709" -c:v libx264 -preset medium -bf 2

# HEVC, 10 bit, tagged as BT.2020 with the PQ transfer function.
encode hevc-10bit.mkv -vf "format=yuv420p10le,$bt2020_pq" \
    -c:v libx265 -preset medium -x265-params log-level=error

encode av1.mp4 -vf "format=yuv420p,$bt709" -c:v libaom-av1 -cpu-used 8 -crf 40
encode vp9.webm -vf "format=yuv420p,$bt709" -c:v libvpx-vp9 -crf 40 -b:v 0
encode vp8.webm -vf format=yuv420p -c:v libvpx -crf 30 -b:v 200k

# ProRes 422 Proxy, 10 bit.
encode prores.mov -vf "format=yuv422p10le,$bt709" -c:v prores_ks -profile:v proxy

# FFV1, 12 bit.
encode ffv1-12bit.mkv -vf "format=yuv420p12le,$bt709" -c:v ffv1 -level 3

# MPEG-2, interlaced, top field first, in a transport stream. The filter
# weaves 50 progressive pictures per second into 25 interlaced frames.
RATE=50 encode mpeg2-interlaced.ts -vf "interlace=scan=tff,format=yuv420p,$bt709" \
    -c:v mpeg2video -flags:v +ilme+ildct+bitexact -b:v 600k

# Variable frame rate: frames at 0, 40, 120, 160 and 400 milliseconds.
encode vfr.mkv \
    -vf "settb=1/1000,setpts='if(eq(N,0),0,if(eq(N,1),40,if(eq(N,2),120,if(eq(N,3),160,400))))',format=yuv420p,$bt709" \
    -fps_mode vfr -c:v libx264 -preset medium -bf 0

# Motion JPEG uses full-range YUV. Neither AVI file carries colour tags.
encode mjpeg.avi -vf format=yuvj420p -c:v mjpeg -q:v 8
encode mpeg4.avi -vf format=yuv420p -c:v mpeg4 -q:v 8

# DNxHR LB in MXF. The encoder takes nothing smaller than 256x120.
SIZE=256x128 FRAMES=2 encode dnxhr.mxf -vf "format=yuv422p,$bt709" -c:v dnxhd -profile:v dnxhr_lb

# Animated images, ten frames per second.
RATE=10 encode anim.gif -c:v gif
RATE=10 encode anim.apng -vf format=rgb24 -f apng -plays 0
RATE=10 encode anim.webp -c:v libwebp_anim -lossless 1 -loop 0

ls -l "$out"
