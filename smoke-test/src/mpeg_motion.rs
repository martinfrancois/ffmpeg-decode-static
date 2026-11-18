//! Regression inputs and independent unmodified-decoder hashes are documented in
//! samples/mpeg-motion/README.md. Only packet/frame decoding errors count as refusal.

use std::path::Path;

use ffmpeg::{Dictionary, codec, decoder, format, media};
use ffmpeg_next as ffmpeg;

type DecodeResult = Result<(usize, u64), (&'static str, ffmpeg::Error)>;

fn decode(path: &Path) -> DecodeResult {
    let mut input = format::input(path).map_err(|error| ("open input", error))?;
    let stream = input
        .streams()
        .best(media::Type::Video)
        .ok_or(("find video", ffmpeg::Error::StreamNotFound))?;
    let index = stream.index();
    let context = codec::context::Context::from_parameters(stream.parameters())
        .map_err(|error| ("read parameters", error))?;
    let codec =
        decoder::find(context.id()).ok_or(("find decoder", ffmpeg::Error::DecoderNotFound))?;
    let mut options = Dictionary::new();
    options.set("idct", "simple");
    options.set("flags", "+bitexact");
    options.set("threads", "1");
    options.set("err_detect", "+crccheck+buffer+compliant+explode");
    let mut decoder = context
        .decoder()
        .open_as_with(codec, options)
        .and_then(|opened| opened.video())
        .map_err(|error| ("open decoder", error))?;
    let mut count = 0;
    let mut hash = 14_695_981_039_346_656_037_u64;
    let mut drain = |decoder: &mut decoder::Video| -> Result<(), (&'static str, ffmpeg::Error)> {
        let mut frame = ffmpeg::util::frame::video::Video::empty();
        loop {
            match decoder.receive_frame(&mut frame) {
                Ok(()) => {
                    for row in 0..frame.height() as usize {
                        let start = row * frame.stride(0);
                        for &byte in &frame.data(0)[start..start + frame.width() as usize] {
                            hash = (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211);
                        }
                    }
                    count += 1;
                }
                Err(ffmpeg::Error::Eof) => return Ok(()),
                Err(ffmpeg::Error::Other { errno }) if errno == ffmpeg::error::EAGAIN => {
                    return Ok(());
                }
                Err(error) => return Err(("receive frame", error)),
            }
        }
    };
    for (stream, packet) in input.packets() {
        if stream.index() == index {
            decoder
                .send_packet(&packet)
                .map_err(|error| ("send packet", error))?;
            drain(&mut decoder)?;
        }
    }
    decoder.send_eof().map_err(|error| ("send EOF", error))?;
    drain(&mut decoder)?;
    Ok((count, hash))
}

pub fn check(directory: &Path) -> Result<(), String> {
    // The normal twins must decode completely with unchanged visible luma.
    for (file, expected) in [
        ("mpeg1-valid.m1v", 0x2965_2733_3e1e_d1b7),
        ("mpeg2-valid.m2v", 0xf9c7_804f_d81d_24fc),
    ] {
        match decode(&directory.join("mpeg-motion").join(file)) {
            Ok((30, hash)) if hash == expected => {}
            result => {
                return Err(format!(
                    "cannot validate MPEG control \"{file}\": expected 30 frames and luma hash {expected:016x}, got {result:?}"
                ));
            }
        }
    }
    for file in ["mpeg1-invalid.m1v", "mpeg2-invalid.m2v"] {
        match decode(&directory.join("mpeg-motion").join(file)) {
            Err(("send packet" | "receive frame", ffmpeg::Error::InvalidData)) => {}
            result => {
                return Err(format!(
                    "cannot validate MPEG refusal \"{file}\": expected a packet or frame InvalidData error, got {result:?}"
                ));
            }
        }
    }
    Ok(())
}
