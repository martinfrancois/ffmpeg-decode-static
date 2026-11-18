//! Packet/frame checks for the three macroblock quantiser update branches.

use std::path::Path;

use crate::mpeg_motion::decode_with_policy;

pub fn check(directory: &Path) -> Result<(), String> {
    let directory = directory.join("mpeg-quantiser");
    let mut failures = Vec::new();
    for (branch, control_hash, lenient_hash, max_threads) in [
        ("intra", 0x110e_4099_3b7f_4a80, 0x32d5_0a37_ebd4_1b25, 1),
        ("zero-mv", 0x0be6_a8b3_7954_4760, 0x110e_4099_3b7f_4a80, 1),
        ("motion", 0x0be6_a8b3_7954_4760, 0x110e_4099_3b7f_4a80, 1),
        (
            "intra-slices",
            0xf788_ccfa_cda2_7865,
            0xc017_a073_9ee3_d280,
            2,
        ),
        (
            "zero-mv-slices",
            0x2c50_1af9_38f1_9b65,
            0x6745_7cb5_00d6_6005,
            2,
        ),
        (
            "motion-slices",
            0x2c50_1af9_38f1_9b65,
            0x6745_7cb5_00d6_6005,
            2,
        ),
    ] {
        for threads in 1..=max_threads {
            for (qscale, strict, expected) in [
                (2, true, Ok((3, control_hash))),
                (2, false, Ok((3, control_hash))),
                (0, false, Ok((3, lenient_hash))),
                (0, true, Err(ffmpeg_next::Error::InvalidData)),
            ] {
                let file = format!("{branch}-q{qscale}.m2v");
                let actual = decode_with_policy(&directory.join(&file), threads, strict);
                let matches = match (&actual, &expected) {
                    (Ok(actual), Ok(expected)) => actual == expected,
                    (Err(("send packet" | "receive frame", actual)), Err(expected)) => {
                        actual == expected
                    }
                    _ => false,
                };
                if !matches {
                    failures.push(format!(
                        "cannot validate MPEG quantiser \"{file}\": expected {expected:?}, got {actual:?}; strict={strict}; threads={threads}"
                    ));
                }
            }
        }
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(failures.join("\n"))
    }
}
