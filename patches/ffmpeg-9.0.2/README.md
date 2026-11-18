# FFmpeg 9.0.2 modifications

The upstream source archive remains unchanged. This series modifies
`libavcodec/mpeg12dec.c` to return an error for invalid MPEG-1/2 motion codes.
All ten callers check the status before using the vector. Legal signed motion
vectors keep their existing decoding. The modified file records the date.
The patch is under the same LGPL-2.1-or-later terms as the FFmpeg file it changes;
the complete licence is in the original archive's COPYING.LGPLv2.1.

`series` lists patch SHA-256 digests in application order. `files` lists the
before and after SHA-256 digests of every modified file. Both are checked by
`scripts/apply-patches.sh` in the helper repository. BUILD-INFO identifies that
repository revision and records the patch archive digest and build commands.

To reconstruct the modified source, extract the original ffmpeg-9.0.2.tar.xz,
extract this patch archive into a separate directory, and run the helper's
`scripts/apply-patches.sh SOURCE_DIRECTORY PATCH_DIRECTORY`. It needs GNU patch,
GNU tar, xz and a SHA-256 tool. The helper build applies the same series before
configuration on every target. No encoder, muxer or hardware interface is added.
