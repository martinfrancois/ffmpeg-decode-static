# Installs the build tools inside a Linux build container and puts them on
# PATH. scripts/build-linux.sh sources this file as root in the container,
# from the container's own sh, because Alpine has no bash until this ran.
# shellcheck shell=sh

if [ -f /etc/alpine-release ]; then
    apk add --no-cache bash binutils gcc make musl-dev nasm pkgconf python3 tar xz >&2
elif [ -f /etc/almalinux-release ]; then
    # GCC 14 is the newest compiler series that both AlmaLinux 8 and the
    # manylinux_2_28 images carry. nasm is in the powertools repository.
    dnf --quiet --assumeyes --enablerepo=powertools install \
        diffutils findutils gcc-toolset-14-binutils gcc-toolset-14-gcc make nasm \
        pkgconf-pkg-config python3.12 tar xz >&2
    # The enable script reads variables that may be unset.
    set +u
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
    set -u
    # The virtual environment in scripts/build.sh needs a Python new enough
    # for meson, and "python3" is not provided by the python3.12 package.
    mkdir -p /usr/local/bin
    ln -sf /usr/bin/python3.12 /usr/local/bin/python3
else
    echo "error: unknown build container, expected Alpine or AlmaLinux" >&2
    return 1
fi
