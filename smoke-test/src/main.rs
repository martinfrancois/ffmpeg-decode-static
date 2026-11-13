//! Links the static FFmpeg libraries built by this repository, decodes every
//! file in `samples/` and compares the result with the values below.
//!
//! The expected timestamps, colour tags and frame hashes were read from the
//! samples with a full FFmpeg build that is independent of these libraries
//! (`ffprobe -show_frames`, and
//! `ffmpeg -idct simple -i FILE -map 0:v:0 -fps_mode passthrough -f hash -hash sha256 -`).
//! `anim.webp` is the exception, see its entry.

use std::ffi::CStr;
use std::path::Path;
use std::process::ExitCode;

use ffmpeg_next as ffmpeg;

use ffmpeg::color::{Primaries, Range, Space, TransferCharacteristic};
use ffmpeg::format::Pixel;
use ffmpeg::util::frame::video::Video;
use ffmpeg::{Dictionary, Rational, codec, decoder, ffi, filter, format, media};
use sha2::{Digest, Sha256};

const EXPECTED_LICENSE: &str = "LGPL version 2.1 or later";
const EXPECTED_PROTOCOLS: [&str; 2] = ["file", "pipe"];

#[derive(Clone, Copy, Debug, PartialEq)]
struct Colour {
    range: Range,
    matrix: Space,
    primaries: Primaries,
    transfer: TransferCharacteristic,
}

const BT709: Colour = Colour {
    range: Range::MPEG,
    matrix: Space::BT709,
    primaries: Primaries::BT709,
    transfer: TransferCharacteristic::BT709,
};

const BT2020_PQ: Colour = Colour {
    range: Range::MPEG,
    matrix: Space::BT2020NCL,
    primaries: Primaries::BT2020,
    transfer: TransferCharacteristic::SMPTE2084,
};

const UNTAGGED: Colour = Colour {
    range: Range::Unspecified,
    matrix: Space::Unspecified,
    primaries: Primaries::Unspecified,
    transfer: TransferCharacteristic::Unspecified,
};

/// What the VP8 decoder reports: VP8 is BT.601 limited range by definition.
const VP8_DEFAULT: Colour = Colour {
    range: Range::MPEG,
    matrix: Space::BT470BG,
    ..UNTAGGED
};

/// What the MJPEG decoder reports for a JFIF stream: BT.601 full range.
const JFIF: Colour = Colour {
    range: Range::JPEG,
    matrix: Space::BT470BG,
    ..UNTAGGED
};

/// What the PNG decoder reports for RGB without a colour chunk.
const FULL_RANGE_RGB: Colour = Colour {
    range: Range::JPEG,
    matrix: Space::RGB,
    ..UNTAGGED
};

struct Sample {
    file: &'static str,
    decoder: &'static str,
    width: u32,
    height: u32,
    pixel: Pixel,
    /// The stream time base, which is the unit of `timestamps`.
    time_base: (i32, i32),
    /// Presentation timestamp of every frame, in output order.
    timestamps: &'static [i64],
    colour: Colour,
    /// Interlaced samples are top field first.
    interlaced: bool,
    /// SHA-256 over the pixels of all frames, laid out as FFmpeg's rawvideo.
    sha256: &'static str,
}

impl Sample {
    const fn progressive(
        file: &'static str,
        decoder: &'static str,
        pixel: Pixel,
        time_base: (i32, i32),
        timestamps: &'static [i64],
        colour: Colour,
        sha256: &'static str,
    ) -> Self {
        Self {
            file,
            decoder,
            width: 64,
            height: 64,
            pixel,
            time_base,
            timestamps,
            colour,
            interlaced: false,
            sha256,
        }
    }
}

const MILLISECONDS: (i32, i32) = (1, 1000);
const MP4_25FPS: (i32, i32) = (1, 12800);
const EVERY_40_MS: &[i64] = &[0, 40, 80, 120, 160];
const EVERY_512_TICKS: &[i64] = &[0, 512, 1024, 1536, 2048];
const EVERY_FRAME: &[i64] = &[0, 1, 2, 3, 4];

const SAMPLES: &[Sample] = &[
    Sample::progressive(
        "h264-8bit.mp4",
        "h264",
        Pixel::YUV420P,
        MP4_25FPS,
        EVERY_512_TICKS,
        BT709,
        "6099f2e5f12b9e560a78048cf4cb5c2cc472712c11b0f6dc898f91745a6d45ad",
    ),
    Sample::progressive(
        "hevc-10bit.mkv",
        "hevc",
        Pixel::YUV420P10LE,
        MILLISECONDS,
        EVERY_40_MS,
        BT2020_PQ,
        "c4dbb4a699b8c9d3903c05498ee530282b36fe84d21079f6d8f8821aad835395",
    ),
    Sample::progressive(
        "av1.mp4",
        "libdav1d",
        Pixel::YUV420P,
        MP4_25FPS,
        EVERY_512_TICKS,
        BT709,
        "7486bc4a6feedaf0d4ae229840cc1d82c176d273db1f7c81ced7065b2e54c1e2",
    ),
    Sample::progressive(
        "vp9.webm",
        "vp9",
        Pixel::YUV420P,
        MILLISECONDS,
        EVERY_40_MS,
        BT709,
        "6bc79a456c8df42ca7aa6944737559fbf682d5100972d9e9e313d9275d243f5c",
    ),
    Sample::progressive(
        "vp8.webm",
        "vp8",
        Pixel::YUV420P,
        MILLISECONDS,
        EVERY_40_MS,
        VP8_DEFAULT,
        "d27eddcf0c7436908d180c949c8bea79b731088ea704678a220d751c250351c5",
    ),
    Sample::progressive(
        "prores.mov",
        "prores",
        Pixel::YUV422P10LE,
        MP4_25FPS,
        EVERY_512_TICKS,
        BT709,
        "33ac84a10b36d7a7ab4e68ad35bc8f3b3c81e09cfadc4d1866426c564fb4d258",
    ),
    Sample::progressive(
        "ffv1-12bit.mkv",
        "ffv1",
        Pixel::YUV420P12LE,
        MILLISECONDS,
        EVERY_40_MS,
        BT709,
        "c62a2f38c06b2b501899f3b4741f90df846f997914e228262c1502bb68099f71",
    ),
    Sample {
        file: "mpeg2-interlaced.ts",
        decoder: "mpeg2video",
        width: 64,
        height: 64,
        pixel: Pixel::YUV420P,
        time_base: (1, 90000),
        // The transport stream muxer starts 1.44 seconds in.
        timestamps: &[129600, 133200, 136800, 140400, 144000],
        colour: BT709,
        interlaced: true,
        sha256: "5b047949f53f8d7f12344fb8d2a2b956042c7772c8827807f53df3eaa6696d10",
    },
    Sample::progressive(
        "vfr.mkv",
        "h264",
        Pixel::YUV420P,
        MILLISECONDS,
        // Variable frame rate: the gaps are 40, 80, 40 and 240 milliseconds.
        &[0, 40, 120, 160, 400],
        BT709,
        "5bcdf8024f71ee859c47cd667e1d7677d85e8239ba2311e1f4e6035ed8be7929",
    ),
    Sample::progressive(
        "mjpeg.avi",
        "mjpeg",
        Pixel::YUVJ420P,
        (1, 25),
        EVERY_FRAME,
        JFIF,
        "595931f3b455bce53e1b8cd7d6a44377be1df661c4ced7b079bec2f601179ac8",
    ),
    Sample::progressive(
        "mpeg4.avi",
        "mpeg4",
        Pixel::YUV420P,
        (1, 25),
        EVERY_FRAME,
        UNTAGGED,
        "a1153359e9cce2685c0023cd7158ed83901e347219071a1be679daa4d3bb701c",
    ),
    Sample {
        file: "dnxhr.mxf",
        decoder: "dnxhd",
        width: 256,
        height: 128,
        pixel: Pixel::YUV422P,
        time_base: (1, 25),
        timestamps: &[0, 1],
        colour: BT709,
        interlaced: false,
        sha256: "c44087a798e30266b7f2e6507895da8c6ad2824ef8b5bbae328f944d078e605a",
    },
    Sample::progressive(
        "anim.gif",
        "gif",
        Pixel::BGRA,
        (1, 100),
        &[0, 10, 20, 30, 40],
        UNTAGGED,
        "7b025a4395e08a8e060a5b550501953a1a3b01c8a16cfed6ff52412ce15827f5",
    ),
    Sample::progressive(
        "anim.apng",
        "apng",
        Pixel::RGB24,
        (1, 100_000),
        &[0, 10_000, 20_000, 30_000, 40_000],
        FULL_RANGE_RGB,
        "abbfdb3214cc8155da3a9b9b1a9d71e716d42278bf6ec92d43218abf90112219",
    ),
    // FFmpeg decodes animated WebP since 9.0, so the full FFmpeg that made
    // the other reference values could not read this file. The hash is the
    // one libwebp 1.6.0 gives for the five frames (through Pillow, converted
    // from RGBA to ARGB byte order).
    Sample::progressive(
        "anim.webp",
        "webp_anim",
        Pixel::ARGB,
        MILLISECONDS,
        &[0, 100, 200, 300, 400],
        UNTAGGED,
        "a42f8d40ad6d427847a17266766409003617315c8ca8968671b2e4bf804fe118",
    ),
];

type Check = Result<(), String>;

fn expect_eq<T: PartialEq + std::fmt::Debug>(what: &str, actual: T, expected: T) -> Check {
    if actual == expected {
        Ok(())
    } else {
        Err(format!("{what} is {actual:?}, expected {expected:?}"))
    }
}

fn ffmpeg_error(what: &str) -> impl Fn(ffmpeg::Error) -> String + '_ {
    move |error| format!("{what}: {error}")
}

/// The frames of one sample, as far as the checks need them.
struct Decoded {
    decoder: String,
    time_base: Rational,
    timestamps: Vec<i64>,
    frames: Vec<Video>,
    sha256: String,
}

/// Feeds the visible pixels of a frame to the hasher in the order of FFmpeg's
/// rawvideo: plane after plane, row after row, without the row padding.
fn hash_frame(hasher: &mut Sha256, frame: &Video) -> Check {
    for plane in 0..frame.planes() {
        let row_bytes = unsafe {
            ffi::av_image_get_linesize(frame.format().into(), frame.width() as i32, plane as i32)
        };
        let row_bytes = usize::try_from(row_bytes)
            .map_err(|_| format!("no row size for plane {plane} of {:?}", frame.format()))?;
        let stride = frame.stride(plane);
        let data = frame.data(plane);
        for row in 0..frame.plane_height(plane) as usize {
            hasher.update(&data[row * stride..row * stride + row_bytes]);
        }
    }
    Ok(())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn decode(path: &Path) -> Result<Decoded, String> {
    let mut input = format::input(path).map_err(ffmpeg_error("open"))?;
    let stream = input
        .streams()
        .best(media::Type::Video)
        .ok_or("no video stream")?;
    let stream_index = stream.index();
    let time_base = stream.time_base();

    let context = codec::context::Context::from_parameters(stream.parameters())
        .map_err(ffmpeg_error("read stream parameters"))?;
    let codec = decoder::find(context.id()).ok_or("no decoder for this codec")?;
    let mut decoder = context.decoder();
    decoder.set_packet_time_base(time_base);
    // The C reference transform gives the same pixels on every CPU. Without
    // it, MPEG-2, MPEG-4 and MJPEG may use an inverse DCT with other rounding.
    let mut options = Dictionary::new();
    options.set("idct", "simple");
    let mut decoder = decoder
        .open_as_with(codec, options)
        .and_then(|opened| opened.video())
        .map_err(ffmpeg_error("open decoder"))?;

    let mut decoded = Decoded {
        decoder: codec.name().to_owned(),
        time_base,
        timestamps: Vec::new(),
        frames: Vec::new(),
        sha256: String::new(),
    };
    let mut hasher = Sha256::new();
    let mut drain = |decoder: &mut decoder::Video, decoded: &mut Decoded| -> Check {
        let mut frame = Video::empty();
        while decoder.receive_frame(&mut frame).is_ok() {
            let index = decoded.frames.len();
            let timestamp = frame
                .pts()
                .ok_or_else(|| format!("frame {index} has no timestamp"))?;
            decoded.timestamps.push(timestamp);
            hash_frame(&mut hasher, &frame)?;
            decoded.frames.push(frame.clone());
        }
        Ok(())
    };

    for (stream, packet) in input.packets() {
        if stream.index() == stream_index {
            decoder
                .send_packet(&packet)
                .map_err(ffmpeg_error("send packet"))?;
            drain(&mut decoder, &mut decoded)?;
        }
    }
    decoder
        .send_eof()
        .map_err(ffmpeg_error("send end of file"))?;
    drain(&mut decoder, &mut decoded)?;

    decoded.sha256 = hex(&hasher.finalize());
    Ok(decoded)
}

/// Runs the frames through one deinterlacer in field mode and counts the output.
fn deinterlaced_frame_count(decoded: &Decoded, deinterlacer: &str) -> Result<usize, String> {
    let first = decoded.frames.first().ok_or("no frames to deinterlace")?;
    let buffer = filter::find("buffer").ok_or("the buffer filter is missing")?;
    let sink = filter::find("buffersink").ok_or("the buffersink filter is missing")?;
    let source_args = format!(
        "video_size={}x{}:pix_fmt={}:time_base={}/{}:pixel_aspect=1/1:colorspace={}:range={}",
        first.width(),
        first.height(),
        first
            .format()
            .descriptor()
            .ok_or("unknown pixel format")?
            .name(),
        decoded.time_base.numerator(),
        decoded.time_base.denominator(),
        first.color_space().name().unwrap_or("unknown"),
        first.color_range().name().unwrap_or("unknown"),
    );

    let mut graph = filter::Graph::new();
    graph
        .add(&buffer, "in", &source_args)
        .map_err(ffmpeg_error("add buffer source"))?;
    graph
        .add(&sink, "out", "")
        .map_err(ffmpeg_error("add buffer sink"))?;
    graph
        .output("in", 0)
        .and_then(|parser| parser.input("out", 0))
        .and_then(|parser| parser.parse(&format!("{deinterlacer}=mode=send_field")))
        .map_err(ffmpeg_error("parse filter graph"))?;
    graph
        .validate()
        .map_err(ffmpeg_error("configure filter graph"))?;

    let mut count = 0;
    let mut drain = |graph: &mut filter::Graph| {
        let mut filtered = Video::empty();
        let mut sink = graph.get("out").expect("the sink was added above");
        while sink.sink().frame(&mut filtered).is_ok() {
            count += 1;
        }
    };
    for frame in &decoded.frames {
        graph
            .get("in")
            .expect("the source was added above")
            .source()
            .add(frame)
            .map_err(ffmpeg_error("send frame to filter"))?;
        drain(&mut graph);
    }
    graph
        .get("in")
        .expect("the source was added above")
        .source()
        .flush()
        .map_err(ffmpeg_error("flush filter"))?;
    drain(&mut graph);
    Ok(count)
}

fn check_sample(directory: &Path, sample: &Sample) -> Check {
    let decoded = decode(&directory.join(sample.file))?;

    expect_eq("decoder", decoded.decoder.as_str(), sample.decoder)?;
    expect_eq(
        "time base",
        (
            decoded.time_base.numerator(),
            decoded.time_base.denominator(),
        ),
        sample.time_base,
    )?;
    expect_eq("frame count", decoded.frames.len(), sample.timestamps.len())?;
    expect_eq(
        "timestamps",
        decoded.timestamps.as_slice(),
        sample.timestamps,
    )?;

    for (index, frame) in decoded.frames.iter().enumerate() {
        let what = |property: &str| format!("{property} of frame {index}");
        expect_eq(
            &what("size"),
            (frame.width(), frame.height()),
            (sample.width, sample.height),
        )?;
        expect_eq(&what("pixel format"), frame.format(), sample.pixel)?;
        expect_eq(
            &what("colour"),
            Colour {
                range: frame.color_range(),
                matrix: frame.color_space(),
                primaries: frame.color_primaries(),
                transfer: frame.color_transfer_characteristic(),
            },
            sample.colour,
        )?;
        expect_eq(
            &what("interlaced flag"),
            frame.is_interlaced(),
            sample.interlaced,
        )?;
        expect_eq(
            &what("top field first flag"),
            frame.is_top_first(),
            sample.interlaced,
        )?;
    }

    expect_eq(
        "SHA-256 of the frames",
        decoded.sha256.as_str(),
        sample.sha256,
    )?;

    if sample.interlaced {
        for deinterlacer in ["bwdif", "yadif"] {
            // Field mode turns every interlaced frame into two progressive ones.
            expect_eq(
                &format!("frame count after {deinterlacer}"),
                deinterlaced_frame_count(&decoded, deinterlacer)?,
                2 * decoded.frames.len(),
            )?;
        }
    }
    Ok(())
}

/// Counts what one of FFmpeg's `av_*_iterate` functions yields.
fn count_registered<T>(
    iterate: unsafe extern "C" fn(*mut *mut std::ffi::c_void) -> *const T,
    mut keep: impl FnMut(*const T) -> bool,
) -> usize {
    let mut state = std::ptr::null_mut();
    let mut count = 0;
    loop {
        let item = unsafe { iterate(&mut state) };
        if item.is_null() {
            return count;
        }
        if keep(item) {
            count += 1;
        }
    }
}

fn registered_protocols() -> Vec<String> {
    let mut protocols = Vec::new();
    for output in [0, 1] {
        let mut state = std::ptr::null_mut();
        loop {
            let name = unsafe { ffi::avio_enum_protocols(&mut state, output) };
            if name.is_null() {
                break;
            }
            let name = unsafe { CStr::from_ptr(name) }
                .to_string_lossy()
                .into_owned();
            if !protocols.contains(&name) {
                protocols.push(name);
            }
        }
    }
    protocols.sort();
    protocols
}

/// Checks that the linked libraries are the decode-only LGPL build.
fn check_libraries() -> Check {
    for (library, license) in [
        ("libavcodec", codec::license()),
        ("libavformat", format::license()),
        ("libavfilter", filter::license()),
        ("libavutil", ffmpeg::util::license()),
    ] {
        expect_eq(&format!("licence of {library}"), license, EXPECTED_LICENSE)?;
    }

    let configuration = codec::configuration();
    for flag in ["--enable-gpl", "--enable-nonfree", "--enable-version3"] {
        if configuration.contains(flag) {
            return Err(format!("the configuration contains {flag}"));
        }
    }

    let encoders = count_registered(ffi::av_codec_iterate, |codec| unsafe {
        ffi::av_codec_is_encoder(codec) != 0
    });
    expect_eq("number of encoders", encoders, 0)?;
    let muxers = count_registered(ffi::av_muxer_iterate, |_| true);
    expect_eq("number of muxers", muxers, 0)?;
    expect_eq(
        "protocols",
        registered_protocols(),
        EXPECTED_PROTOCOLS.map(String::from).to_vec(),
    )
}

fn main() -> ExitCode {
    let Some(directory) = std::env::args_os().nth(1) else {
        eprintln!("usage: smoke-test <samples directory>");
        return ExitCode::from(2);
    };
    let directory = Path::new(&directory);

    if let Err(error) = ffmpeg::init() {
        eprintln!("FFmpeg failed to initialise: {error}");
        return ExitCode::FAILURE;
    }
    println!("libavcodec configuration: {}", codec::configuration());

    let mut failures = 0;
    let mut report = |name: &str, result: Check| match result {
        Ok(()) => println!("ok    {name}"),
        Err(error) => {
            println!("FAIL  {name}: {error}");
            failures += 1;
        }
    };

    report("libraries", check_libraries());
    for sample in SAMPLES {
        report(sample.file, check_sample(directory, sample));
    }

    if failures == 0 {
        println!("all {} checks passed", SAMPLES.len() + 1);
        ExitCode::SUCCESS
    } else {
        println!("{failures} checks failed");
        ExitCode::FAILURE
    }
}
