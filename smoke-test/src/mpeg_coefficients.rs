//! The coefficient fixtures exercise the public packet/frame decoder API.
//! Their construction and the unmodified control hash are recorded with the files.

use std::path::Path;

use crate::mpeg_motion::decode_with_threads;

fn check_streams(directory: &Path, threads: usize) -> Result<(), String> {
    let directory = directory.join("mpeg-coefficients");
    for (file, frames, hash) in [
        ("plain.m2v", 50, 0x96c9_af6f_ed4e_5045),
        ("zero-ac.m2v", 50, 0x2c91_d105_0d22_f325),
        ("positive-2047.m2v", 50, 0x90ab_866a_b88f_fde5),
        ("negative-2048.m2v", 50, 0x9100_0916_0f9b_d0a5),
        ("single-2046.m2v", 50, 0xf646_d3bd_feda_f275),
        ("row-safe.m2v", 50, 0x0324_3c7f_51ce_3725),
        ("mpeg1-intra-valid.m1v", 3, 0xa259_4778_46ce_4a25),
        ("mpeg1-inter-valid.m1v", 3, 0x49a4_fd06_8305_ef05),
        ("mpeg2-intra-valid.m2v", 3, 0x1d0b_79a2_92aa_4bd5),
        ("mpeg2-inter-valid.m2v", 3, 0xa55f_b7cf_6667_338b),
        ("mpeg1-slices-valid.m1v", 3, 0xf49a_544b_d722_7125),
        ("mpeg2-slices-valid.m2v", 3, 0x6ca0_4f6f_198b_0b85),
    ] {
        if threads > 1 && !file.contains("-slices-") && !file.contains("-fields-") {
            continue;
        }
        match decode_with_threads(&directory.join(file), threads) {
            Ok(result) if result == (frames, hash) => {}
            result => {
                return Err(format!(
                    "cannot validate MPEG coefficient control \"{file}\": expected {frames} frames and luma hash {hash:016x}, got {result:?}"
                ));
            }
        }
    }
    for (expected, files) in [
        (
            ffmpeg_next::Error::PatchWelcome,
            &[
                "edge-up.m2v",
                "two-in-range.m2v",
                "three-in-range.m2v",
                "rounding-overflow.m2v",
                "column-overflow.m2v",
                "mpeg1-intra-large.m1v",
                "mpeg1-inter-large.m1v",
                "mpeg2-intra-large.m2v",
                "mpeg2-inter-large.m2v",
                "mpeg1-slices-large.m1v",
                "mpeg2-slices-large.m2v",
                "mpeg2-fields-large.m2v",
            ][..],
        ),
        (
            ffmpeg_next::Error::InvalidData,
            &[
                "zero.m2v",
                "lowest.m2v",
                "mpeg1-intra-zero.m1v",
                "mpeg1-inter-zero.m1v",
                "mpeg2-intra-zero.m2v",
                "mpeg2-inter-zero.m2v",
                "mpeg1-slices-zero.m1v",
                "mpeg2-slices-zero.m2v",
                "mpeg2-fields-zero.m2v",
            ][..],
        ),
    ] {
        for file in files {
            if threads > 1 && !file.contains("-slices-") && !file.contains("-fields-") {
                continue;
            }
            match decode_with_threads(&directory.join(file), threads) {
                Err(("send packet" | "receive frame", error)) if error == expected => {}
                result => {
                    return Err(format!(
                        "cannot validate MPEG coefficient refusal \"{file}\": expected a packet or frame {expected:?} error, got {result:?}"
                    ));
                }
            }
        }
    }
    Ok(())
}

// The smoke program runs these checks sequentially. Restore detected CPU flags
// before other codecs run, including when a coefficient check fails.
pub fn check(directory: &Path) -> Result<(), String> {
    unsafe {
        let detected = ffmpeg_next::ffi::av_get_cpu_flags();
        let mut modes = vec![detected, 0];
        if cfg!(target_arch = "x86_64") && detected & ffmpeg_next::ffi::AV_CPU_FLAG_SSE2 != 0 {
            let sse2 = ffmpeg_next::ffi::AV_CPU_FLAG_MMX
                | ffmpeg_next::ffi::AV_CPU_FLAG_MMXEXT
                | ffmpeg_next::ffi::AV_CPU_FLAG_SSE
                | ffmpeg_next::ffi::AV_CPU_FLAG_SSE2;
            modes.push(detected & sse2);
        }
        let result = modes.into_iter().try_for_each(|flags| {
            ffmpeg_next::ffi::av_force_cpu_flags(flags);
            let x86_simd =
                cfg!(target_arch = "x86_64") && flags & ffmpeg_next::ffi::AV_CPU_FLAG_SSE2 != 0;
            check_vcr2(directory, x86_simd)?;
            [1, 2].into_iter().try_for_each(|threads| {
                check_streams(directory, threads)
                    .map_err(|error| format!("{error}; CPU flags {flags:#x}, threads {threads}"))
            })
        });
        ffmpeg_next::ffi::av_force_cpu_flags(detected);
        result
    }
}

// No sequence header is supplied. Dimensions and the VCR2 tag must select
// vcr2_init_sequence, which assigns MPEG2VIDEO despite the proprietary tag.
fn check_vcr2(directory: &Path, x86_simd: bool) -> Result<(), String> {
    use ffmpeg_next::{Dictionary, Packet, codec, decoder, util::frame::video::Video};

    let directory = directory.join("mpeg-coefficients");
    for (file, expected) in [
        ("vcr2-valid.packet", 0xa110_59ef_d172_cb25),
        ("vcr2-zero.packet", 0xa110_59ef_d172_cb25),
        ("vcr2-idct-overflow.packet", 0x058e_ef4e_b2a3_4a0c),
        (
            "vcr2-large.packet",
            if x86_simd {
                0x7c95_06c3_dd06_1b25
            } else {
                0x5aa5_8ab3_fed0_db85
            },
        ),
    ] {
        let codec = decoder::find(codec::Id::MPEG2VIDEO)
            .ok_or_else(|| "cannot test VCR2: MPEG-2 decoder unavailable".to_owned())?;
        let mut context = codec::context::Context::new_with_codec(codec);
        unsafe {
            let context = &mut *context.as_mut_ptr();
            context.codec_tag = u32::from_le_bytes(*b"VCR2");
            context.width = 32;
            context.coded_width = 32;
            context.height = 16;
            context.coded_height = 16;
        }
        let mut options = Dictionary::new();
        options.set("idct", "simple");
        options.set("flags", "+bitexact");
        options.set("threads", "1");
        options.set("err_detect", "+crccheck+buffer+compliant+explode");
        let mut decoder = context
            .decoder()
            .open_as_with(codec, options)
            .and_then(|opened| opened.video())
            .map_err(|error| format!("cannot open VCR2 decoder: {error}"))?;
        let bytes = std::fs::read(directory.join(file))
            .map_err(|error| format!("cannot read VCR2 fixture {file}: {error}"))?;
        decoder
            .send_packet(&Packet::copy(&bytes))
            .map_err(|error| format!("cannot decode VCR2 packet {file}: {error}"))?;
        let mut frame = Video::empty();
        decoder
            .receive_frame(&mut frame)
            .map_err(|error| format!("cannot receive VCR2 frame {file}: {error}"))?;
        if (frame.width(), frame.height()) != (32, 16) {
            return Err(format!("unexpected VCR2 dimensions for {file}"));
        }
        let mut hash = 14_695_981_039_346_656_037_u64;
        for row in 0..16 {
            let start = row * frame.stride(0);
            for &byte in &frame.data(0)[start..start + 32] {
                hash = (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211);
            }
        }
        if hash != expected {
            return Err(format!(
                "VCR2 pixels changed for {file}: expected {expected:016x}, got {hash:016x}"
            ));
        }
        decoder
            .send_eof()
            .map_err(|error| format!("cannot flush VCR2 {file}: {error}"))?;
        if decoder.receive_frame(&mut frame) != Err(ffmpeg_next::Error::Eof) {
            return Err(format!("VCR2 {file} did not finish after one frame"));
        }
    }
    Ok(())
}
