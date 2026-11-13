#!/usr/bin/env bash
# Builds zlib, dav1d and FFmpeg for one target and packs the release archive.
# It builds for the machine it runs on, so run it on the target's own
# architecture and C library, and for a glibc target on the glibc version in
# versions.env. scripts/build-linux.sh does that for the Linux targets by
# running this script in the pinned container. The macOS targets run it
# directly, with Xcode's command line tools, GNU tar, xz, pkg-config and, on
# x86_64, nasm installed.
#
# Usage: scripts/build.sh <target>
#
# Environment:
#   SOURCES_DIR        verified source archives (default: sources/)
#   WORK_DIR           scratch directory (default: build/<target>)
#   OUT_DIR            where the archive goes (default: dist/)
#   JOBS               parallel compile jobs (default: all cores)
#   SOURCE_DATE_EPOCH  timestamp for archive entries (default: HEAD commit time)
#   BUILD_REVISION     revision recorded in BUILD-INFO (default: HEAD commit)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target=${1:-}
is_known_target "$target" ||
    die "usage: scripts/build.sh <target>, one of:$(printf '%s' "$ALL_TARGETS" | tr '\n' ' ')"

case "$target" in
    x86_64-*) arch=x86_64 ;;
    aarch64-*) arch=aarch64 ;;
esac
case "$target" in
    *-linux-gnu) os=linux libc=glibc ;;
    *-linux-musl) os=linux libc=musl ;;
    *-apple-darwin) os=macos ;;
esac

sources=${SOURCES_DIR:-"$REPO_ROOT/sources"}
work=${WORK_DIR:-"$REPO_ROOT/build/$target"}
out=${OUT_DIR:-"$REPO_ROOT/dist"}
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}

default_build_identity

# --- toolchain ---------------------------------------------------------------

host_arch=$(uname -m)
[ "$host_arch" = arm64 ] && host_arch=aarch64
[ "$host_arch" = "$arch" ] || die "$target needs a $arch machine, this one is $host_arch"

# Flags for every C file of the three libraries.
extra_cflags=""
tools="make pkg-config python3 xz"
case "$os" in
    linux)
        export CC=gcc AR=ar
        tools="$tools readelf"
        # zlib's default "ar rc" stamps every member with the current time.
        # The D modifier writes zeros, as FFmpeg and dav1d already do.
        zlib_arflags=rcD
        if [ "$libc" = glibc ]; then
            glibc=$(getconf GNU_LIBC_VERSION | cut -d' ' -f2)
            # The libraries can need any symbol of the glibc they were compiled against.
            [ "$glibc" = "$GLIBC_VERSION" ] ||
                die "this machine has glibc $glibc, but $target is built against $GLIBC_VERSION (use scripts/build-linux.sh)"
            baseline="glibc $glibc"
        else
            # musl's ldd prints its version and exits non-zero when run without a file.
            baseline="musl $({ ldd 2>&1 || true; } | sed -n 's/^Version //p')"
        fi
        if [ "$arch" = x86_64 ]; then
            # Keeps the assembler from marking GOT accesses as relaxable.
            # Linkers older than the assembler can rewrite a marked instruction
            # they do not know into wrong code
            # (docs/adr/0005-no-relaxable-relocations.md).
            extra_cflags="-Wa,-mrelax-relocations=no"
        fi
        ;;
    macos)
        export CC=clang AR=ar
        tools="$tools libtool otool"
        # The compiler and the linker read the oldest supported macOS from here.
        export MACOSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET
        # Makes Apple's ar and libtool write zeros instead of the current time.
        # zlib archives with libtool here, which takes no ar flags.
        export ZERO_AR_DATE=1
        zlib_arflags=""
        baseline="macOS $MACOS_DEPLOYMENT_TARGET"
        ;;
esac
# Only the x86_64 builds have assembly that needs nasm. On aarch64 the C
# compiler assembles the hand-written code.
[ "$arch" = x86_64 ] && tools="$tools nasm"

for tool in "$CC" "$AR" $tools; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found on PATH"
done

verify_sources "$sources"

mkdir -p "$work" "$out"

if [ "$arch" = x86_64 ]; then
    assembler=$(nasm --version)
else
    assembler="the C compiler"
fi
if [ "$os" = macos ] && [ "$arch" = x86_64 ]; then
    # nasm writes the oldest macOS into an object only when the source asks
    # for it, and the linker warns about every object without one. This puts
    # a wrapper first on PATH that adds the request to each Mach-O object the
    # builds assemble. Other formats, which configure probes, reject it.
    nasm_request="build_version macos, ${MACOS_DEPLOYMENT_TARGET%%.*}, ${MACOS_DEPLOYMENT_TARGET#*.}"
    mkdir -p "$work/tools"
    cat >"$work/tools/nasm" <<EOF
#!/bin/sh
case " \$* " in
    *" macho64 "*) exec "$(command -v nasm)" --before "$nasm_request" "\$@" ;;
    *) exec "$(command -v nasm)" "\$@" ;;
esac
EOF
    chmod +x "$work/tools/nasm"
    PATH="$work/tools:$PATH"
    assembler="$assembler, run with --before \"$nasm_request\" for Mach-O output"
fi
src=$work/src
deps=$work/deps
stage=$work/stage
pkg=$work/package
rm -rf "${work:?}/src" "${work:?}/deps" "${work:?}/stage" "${work:?}/package"
mkdir -p "$src" "$deps" "$stage" "$pkg"

# meson and ninja come from PyPI at pinned versions on every platform.
venv=$work/venv
if [ ! -x "$venv/bin/meson" ]; then
    python3 -m venv "$venv"
    "$venv/bin/python" -m pip install --quiet --disable-pip-version-check \
        --requirement "$REPO_ROOT/scripts/requirements.txt"
fi
PATH="$venv/bin:$PATH"

# Each build step appends the exact command it ran. BUILD-INFO prints them.
commands=$work/commands.txt
: >"$commands"

# Prints its arguments as one shell command line, quoting only where needed.
shell_words() {
    local word line=""
    for word in "$@"; do
        case "$word" in
            *[!A-Za-z0-9_./=,:@+-]*) word="'$word'" ;;
        esac
        line="$line${line:+ }$word"
    done
    printf '%s' "$line"
}

# Runs a configure-type command and records it, with the scratch directory
# replaced by a placeholder so the record is the same on every machine.
recorded() {
    local label=$1
    shift
    {
        printf '[%s]\n' "$label"
        printf '%s' "${RECORD_ENV:+$RECORD_ENV }"
        printf '%s\n\n' "$(shell_words "$@")" | sed "s|$work|\$WORK|g"
    } >>"$commands"
    "$@"
}

extract() {
    log "extracting $1"
    gnu_tar -xf "$sources/$1" -C "$src"
}

# --- zlib --------------------------------------------------------------------

extract "$ZLIB_ARCHIVE"
(
    cd "$src/zlib-$ZLIB_VERSION"
    export CFLAGS="-O3 -fPIC${extra_cflags:+ $extra_cflags}"
    RECORD_ENV="CFLAGS='$CFLAGS'" recorded zlib ./configure --static --prefix="$deps"
    make -j"$jobs" libz.a ${zlib_arflags:+"ARFLAGS=$zlib_arflags"}
    make install ${zlib_arflags:+"ARFLAGS=$zlib_arflags"}
)

# --- dav1d -------------------------------------------------------------------

extract "$DAV1D_ARCHIVE"
(
    cd "$src/dav1d-$DAV1D_VERSION"
    recorded dav1d meson setup build \
        --prefix "$deps" --libdir lib \
        --buildtype release --default-library static \
        -Db_staticpic=true \
        ${extra_cflags:+"-Dc_args=$extra_cflags"} \
        -Denable_tools=false -Denable_tests=false -Denable_examples=false
    ninja -C build -j"$jobs" install
)

# --- FFmpeg ------------------------------------------------------------------

# What the libraries contain. docs/adr/0001-decode-only-lgpl-configuration.md
# gives the reason for each group.
# The buffer source and sink are part of libavfilter itself and need no flag.
ffmpeg_filters="bwdif format yadif"
ffmpeg_protocols="file pipe"

ffmpeg_flags=(
    "--cc=$CC"
    --disable-autodetect
    --disable-iconv
    --disable-programs
    --disable-doc
    --disable-debug
    --enable-static
    --disable-shared
    --enable-pic
    --disable-avdevice
    --disable-swresample
    --disable-swscale
    --disable-network
    --disable-devices
    --disable-encoders
    --disable-muxers
    --disable-hwaccels
    --disable-protocols
    "--enable-protocol=${ffmpeg_protocols// /,}"
    --disable-filters
    "--enable-filter=${ffmpeg_filters// /,}"
    --enable-zlib
    --enable-libdav1d
    --pkg-config-flags=--static
    --enable-pthreads
)
if [ -n "$extra_cflags" ]; then
    ffmpeg_flags+=("--extra-cflags=$extra_cflags")
fi

extract "$FFMPEG_ARCHIVE"
ffmpeg_src=$src/ffmpeg-$FFMPEG_VERSION
(
    cd "$ffmpeg_src"
    # The dependencies are found through pkg-config, and the install prefix
    # stays at its default, so the configuration string that FFmpeg compiles
    # into the libraries holds no path of the build machine.
    export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig"
    # shellcheck disable=SC2016 # $WORK is the placeholder that BUILD-INFO prints
    RECORD_ENV='PKG_CONFIG_LIBDIR=$WORK/deps/lib/pkgconfig' recorded ffmpeg ./configure "${ffmpeg_flags[@]}"
    make -j"$jobs"
    make install DESTDIR="$stage"
)

# --- checks on what was configured -------------------------------------------

config_h=$ffmpeg_src/config.h
components_h=$ffmpeg_src/config_components.h

license=$(sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"$/\1/p' "$config_h")
[ "$license" = "LGPL version 2.1 or later" ] ||
    die "FFmpeg reports the licence '$license', expected 'LGPL version 2.1 or later'"

# Names of the enabled components of one kind, lower case, sorted, on one line.
enabled_components() {
    sed -n "s/^#define CONFIG_\(.*\)_$1 1\$/\1/p" "$components_h" |
        tr '[:upper:]' '[:lower:]' | sort | tr '\n' ' ' | sed 's/ $//'
}

expect_components() {
    local kind=$1 expected=$2 actual
    actual=$(enabled_components "$kind")
    [ "$actual" = "$expected" ] ||
        die "enabled $kind components are '$actual', expected '$expected'"
}

expect_components ENCODER ""
expect_components MUXER ""
expect_components HWACCEL ""
expect_components INDEV ""
expect_components OUTDEV ""
expect_components PROTOCOL "$ffmpeg_protocols"
expect_components FILTER "$ffmpeg_filters"

# The formats this repository promises. A version bump that drops or renames
# one of them has to fail here, not in a consumer.
required_decoders="apng dnxhd ffv1 gif h264 hevc libdav1d mjpeg mpeg2video mpeg4 png prores vp8 vp9 webp webp_anim"
required_demuxers="apng avi gif matroska mov mpegts mxf webp_anim"

require_components() {
    local kind=$1 name
    shift
    for name in "$@"; do
        case " $(enabled_components "$kind") " in
            *" $name "*) ;;
            *) die "the $name $kind is not enabled" ;;
        esac
    done
}

# shellcheck disable=SC2086
require_components DECODER $required_decoders
# shellcheck disable=SC2086
require_components DEMUXER $required_demuxers

# --- package -----------------------------------------------------------------

log "packaging"
mkdir -p "$pkg/lib/pkgconfig" "$pkg/licenses"
cp -R "$stage/usr/local/include" "$pkg/include"

ffmpeg_libs="avcodec avfilter avformat avutil"
for lib in $ffmpeg_libs; do
    cp "$stage/usr/local/lib/lib$lib.a" "$pkg/lib/"
done
installed=""
for file in "$stage"/usr/local/lib/lib*.a; do
    name=$(basename "$file" .a)
    installed="$installed${installed:+ }${name#lib}"
done
[ "$installed" = "$ffmpeg_libs" ] || die "FFmpeg installed the libraries '$installed', expected '$ffmpeg_libs'"

# dav1d and zlib go inside libavcodec.a, so a consumer links four FFmpeg
# libraries and nothing else (docs/adr/0004-dav1d-and-zlib-inside-libavcodec.md).
case "$os" in
    linux)
        "$AR" -M <<EOF
open $pkg/lib/libavcodec.a
addlib $deps/lib/libdav1d.a
addlib $deps/lib/libz.a
save
end
EOF
        # The script mode of ar stamps the symbol table with the current time.
        # Rewriting it with the D modifier puts zeros there.
        "$AR" sD "$pkg/lib/libavcodec.a"
        ;;
    macos)
        libtool -static -o "$pkg/lib/libavcodec.merged.a" \
            "$pkg/lib/libavcodec.a" "$deps/lib/libdav1d.a" "$deps/lib/libz.a"
        mv "$pkg/lib/libavcodec.merged.a" "$pkg/lib/libavcodec.a"
        # Every object has to record the oldest macOS it runs on, and all the
        # same one. otool prints one "name(member):" line per object.
        otool -l "$pkg"/lib/*.a >"$work/load-commands.txt"
        # "|| true": grep fails when it counts none, and the check below reports it.
        objects=$(grep -c '^.*(.*):$' "$work/load-commands.txt" || true)
        minos=$(awk '$1 == "minos" { count[$2]++ } END { for (version in count) print count[version], version }' "$work/load-commands.txt")
        [ "$minos" = "$objects $MACOS_DEPLOYMENT_TARGET" ] ||
            die "expected $objects objects for macOS $MACOS_DEPLOYMENT_TARGET, found (count, version): $minos"
        ;;
esac

if [ "$os" = linux ] && [ "$arch" = x86_64 ]; then
    # Through a file: in a pipeline, grep would stop reading at the first
    # matches and the status of the pipeline would be readelf's broken pipe.
    readelf --relocs --wide "$pkg"/lib/*.a >"$work/relocations.txt"
    if grep -m 5 GOTPCRELX "$work/relocations.txt"; then
        die "the libraries hold relaxable GOT relocations, see docs/adr/0005-no-relaxable-relocations.md"
    fi
fi

# The pkg-config files point at the directory they are in, and no longer name
# the merged libraries.
for lib in $ffmpeg_libs; do
    # shellcheck disable=SC2016 # ${...} below are pkg-config variables
    sed -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
        -e 's|^libdir=.*|libdir=${prefix}/lib|' \
        -e 's|^includedir=.*|includedir=${prefix}/include|' \
        -e "/^Libs/ s| -L$deps/lib||g" \
        -e '/^Libs/ s| -ldav1d||g' \
        -e '/^Libs/ s| -lz||g' \
        "$stage/usr/local/lib/pkgconfig/lib$lib.pc" >"$pkg/lib/pkgconfig/lib$lib.pc"
done
if grep -n -e "$work" -e dav1d -e ' -lz' "$pkg"/lib/pkgconfig/*.pc; then
    die "a pkg-config file still names a build path or a merged library"
fi

cp "$ffmpeg_src/COPYING.LGPLv2.1" "$pkg/licenses/FFmpeg-COPYING.LGPLv2.1"
cp "$ffmpeg_src/LICENSE.md" "$pkg/licenses/FFmpeg-LICENSE.md"
cp "$src/dav1d-$DAV1D_VERSION/COPYING" "$pkg/licenses/dav1d-COPYING"
cp "$src/zlib-$ZLIB_VERSION/LICENSE" "$pkg/licenses/zlib-LICENSE"

{
    cat <<EOF
Decode-only static FFmpeg libraries
https://github.com/martinfrancois/ffmpeg-decode-static

target:           $target
build revision:   $BUILD_REVISION
runs on:          $baseline or newer
FFmpeg licence:   $license
C compiler:       $("$CC" --version | head -n 1)
assembler:        $assembler
meson:            $(meson --version)

Sources (name, URL, SHA-256):
EOF
    while read -r _ name url sha; do
        printf '  %s\n    %s\n    %s\n' "$name" "$url" "$sha"
    done < <(source_table)
    cat <<EOF

libavcodec.a also holds the objects of dav1d and zlib. The licence of each
library is in licenses/.

Build commands, run in each unpacked source directory (\$WORK is the scratch
directory of the build):

EOF
    cat "$commands"
} >"$pkg/BUILD-INFO"

archive=$out/ffmpeg-decode-static-$target.tar.xz
(
    cd "$pkg"
    gnu_tar --sort=name --format=ustar \
        --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
        --mode='u=rwX,go=rX' \
        -cf - BUILD-INFO include lib licenses
) | xz -9 --threads=1 >"$archive"

log "wrote $archive ($(wc -c <"$archive") bytes, sha256 $(sha256_of "$archive"))"
