# Working on this repository

Scripts and CI that build decode-only, LGPL, static FFmpeg libraries for Rust programs.
[README.md](README.md) says what the archives hold and how a program uses them. The reasons behind
the non-obvious choices are in [docs/adr/](docs/adr), one MADR 4 record each. Read the record
before changing what it decided, and add one when you make a choice the code cannot explain.

## Layout

- `versions.env` is the only place a version, checksum or container image is pinned.
- `scripts/build.sh` builds one target on the machine it runs on. `scripts/build-linux.sh` runs it
  in the pinned container. `scripts/lib.sh` holds what the scripts share, including the list of
  targets. A new target needs an entry there and one in the workflow's build matrix.
- `smoke-test/` is a Rust program that links the built libraries and decodes `samples/`.
- `.github/workflows/build.yml` builds and tests every target. Its `ci` job is the required check.
  For a tag, its `release` job publishes what the run built, with `scripts/release.sh`.

## Commands

Linux targets need podman or docker and a machine of the target's architecture.

```sh
scripts/fetch-sources.sh                          # download and verify sources into sources/
scripts/build-linux.sh x86_64-unknown-linux-gnu   # build into dist/
scripts/smoke-test.sh x86_64-unknown-linux-gnu    # link, decode samples/, check dependencies
```

macOS targets build on a Mac of the target's architecture, without a container:

```sh
scripts/build.sh aarch64-apple-darwin
scripts/smoke-test.sh aarch64-apple-darwin
```

Windows targets build on Windows. `scripts\msvc-env.cmd` sets up MSVC and runs a script in MSYS2
bash ([docs/adr/0006-windows-builds-with-msvc-under-msys2.md](docs/adr/0006-windows-builds-with-msvc-under-msys2.md)):

```bat
scripts\msvc-env.cmd build.sh x86_64-pc-windows-msvc
scripts\msvc-env.cmd smoke-test.sh x86_64-pc-windows-msvc
```

The smoke test needs cargo, a C compiler and libclang. The musl targets also need the musl
headers (`musl-tools` on Debian and Ubuntu) and run on a glibc machine, as they do in CI.

Before you push a change to a script, run `bash -n` and
[ShellCheck](https://www.shellcheck.net/) on it, then build and smoke-test what your machine can:
on Linux at least one glibc and one musl target. CI covers the rest.

## Updating a pinned version

A new source version fails the build until its checksum is in `versions.env`:

1. Run `scripts/fetch-sources.sh --print-checksums` and copy the changed `*_SHA256` line into
   `versions.env`.
2. Compare that value with what upstream publishes before you commit it. FFmpeg signs its
   archives (`gpg --verify` against the `.asc` file next to the archive, key
   `FCF986EA15E6E293A5644F10B4322F04D67658D8`). dav1d publishes a `.sha256` file next to the
   archive. zlib's GitHub release shows a SHA-256 digest for each asset.
3. An FFmpeg update is only possible within what the `ffmpeg-next` version in
   `smoke-test/Cargo.toml` supports. Check the crate's release notes, and update the crate in the
   same pull request if FFmpeg moves to a new minor version.

`scripts/build.sh` fails when a required decoder or demuxer disappears, or when an encoder, a
muxer, a device, a hardware accelerator, or a protocol or filter outside its lists gets enabled.
Decide then whether the lists in the script or the configure flags have to change, and update
[docs/adr/0001-decode-only-lgpl-configuration.md](docs/adr/0001-decode-only-lgpl-configuration.md)
if the answer changes what the libraries contain.

## Releases

A release is a tag `v<FFmpeg version>-<build number>` on `main`, for example `v9.0.2-1`. The first
build of an FFmpeg version is 1. A later change to anything else that ends up in the archives
(dav1d, zlib, a build flag, a container image) raises the number.

```sh
git switch main && git pull --ff-only
git tag v9.0.2-2 && git push origin v9.0.2-2
```

The tag starts the workflow. It builds and smoke-tests every target again, and the `release` job
then attaches the archives, the source archives and `checksums.txt` to a new GitHub release. The
job fails if the tag is not on `main`, does not fit `FFMPEG_VERSION`, or the files are not exactly
the expected ones. When it fails, no release is published. Rerun the job if the cause was outside
the repository or the tagged commit has reached `main` since, and delete the draft release first
if the job left one. A tag is not moved or reused: if the cause is in the repository or a
published release is wrong, fix `main` and tag the next build number.

## Samples

`samples/` holds one tiny file per format, made by `scripts/generate-samples.sh --container`. The
expected values in `smoke-test/src/main.rs` come from an independent decoder, and the comment at
the top of that file gives the commands. After regenerating a sample, read the values again with
those commands. The smoke test's own output is not a source for them: it would only prove that the
libraries agree with themselves.

## Warnings in the CI logs

Read the log of a green run too. These warnings are known and stay:

- FFmpeg's own sources give about 230 compiler warnings per Linux target (`-Wstringop-overflow`,
  `-Wstack-usage`, `-Wimplicit-fallthrough`, `-Wunused-function`, `-Warray-bounds`). The build
  compiles the upstream archive unchanged, so they are upstream's to fix.
- `actions/download-artifact` prints Node's `DEP0005` deprecation warning. It comes from the
  action's own code.
- On macOS, `libtool` warns about duplicate member names when it puts dav1d and zlib into
  `libavcodec.a`. Objects from different directories share a file name, and the linker reads them
  all.
- The aarch64 macOS smoke test links with one linker warning about QTKit, a framework that
  `ffmpeg-sys-next` asks for. README.md tells users about it.
- MSVC gives about 100 warnings for FFmpeg's own sources per Windows target (C4334, C4113 and a
  few others), and meson warns that MSVC has no `-fvisibility=hidden` when it configures dav1d.
  Neither matters for a static library.

Any other warning is new: fix it, or add it here with the reason it stays.

## Conventions

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/). One commit
  per logical change. Changes reach `main` through a pull request, merged by rebase or squash.
- Shell scripts start with `set -euo pipefail`, take paths from arguments or environment variables
  with defaults under the repository, and never write outside `build/`, `dist/` and `sources/`.
  The one exception is `scripts/generate-samples.sh`, which writes `samples/`. The scripts also
  run on macOS, so they have to work in its bash 3.2: no associative arrays, and no expansion of
  an empty array.
- A build must not depend on what the machine has installed beyond the tools `scripts/build.sh`
  checks for. If FFmpeg's configure finds a library on its own, turn it off by name.
- Archives must come out the same when the same commit is built twice. Keep timestamps, user names
  and absolute paths out of them. The Windows archives do not meet this yet: MSVC writes the build
  time and source paths into its objects
  ([issue 4](https://github.com/martinfrancois/ffmpeg-decode-static/issues/4)).
