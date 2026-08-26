// SPDX-License-Identifier: MIT

//! Display-oriented dimensions derived from local media headers.
//!
//! The board needs final geometry before LazyLayoutKit solves its masonry
//! snapshot. Reading headers while the disposable index is rebuilt keeps that
//! work out of the SwiftUI rendering path and avoids decoding full media.

use std::io::{BufReader, Read, Seek, SeekFrom};

use nom_exif::{EntryValue, Exif, ExifTag, MediaParser, MediaSource, TrackInfoTag};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct MediaDimensions {
    pub width: u32,
    pub height: u32,
}

impl MediaDimensions {
    fn new(width: u32, height: u32) -> Option<Self> {
        (width > 0 && height > 0).then_some(Self { width, height })
    }

    pub(crate) fn aspect_ratio(self) -> Option<f64> {
        (self.width > 0 && self.height > 0).then(|| self.width as f64 / self.height as f64)
    }

    fn swapping_axes(self) -> Self {
        Self {
            width: self.height,
            height: self.width,
        }
    }
}

pub(crate) fn image_dimensions<R: Read + Seek>(reader: &mut R) -> Option<MediaDimensions> {
    reader.seek(SeekFrom::Start(0)).ok()?;
    let mut buffered = BufReader::new(&mut *reader);
    let image_type = imagesize::reader_type(&mut buffered).ok();
    let size = image_type.and_then(|kind| kind.reader_size(&mut buffered).ok());
    let orientation_is_applied = matches!(image_type, Some(imagesize::ImageType::Heif(_)));
    drop(buffered);
    let dimensions = match size {
        Some(size) => MediaDimensions {
            width: size.width.try_into().ok()?,
            height: size.height.try_into().ok()?,
        },
        None => {
            reader.seek(SeekFrom::Start(0)).ok()?;
            jpeg2000_dimensions(reader).or_else(|| {
                reader.seek(SeekFrom::Start(0)).ok()?;
                svg_dimensions(reader)
            })?
        }
    };

    if orientation_is_applied {
        return Some(dimensions);
    }

    reader.seek(SeekFrom::Start(0)).ok()?;
    let orientation = MediaSource::seekable(&mut *reader)
        .ok()
        .and_then(|source| {
            let mut parser = MediaParser::new();
            parser.parse_exif(source).ok().map(Exif::from)
        })
        .as_ref()
        .and_then(|exif| exif.get(ExifTag::Orientation))
        .and_then(unsigned_value);

    Some(
        if orientation.is_some_and(|value| (5..=8).contains(&value)) {
            dimensions.swapping_axes()
        } else {
            dimensions
        },
    )
}

fn jpeg2000_dimensions<R: Read + Seek>(reader: &mut R) -> Option<MediaDimensions> {
    let file_end = reader.seek(SeekFrom::End(0)).ok()?;
    let root = BoxRange {
        body_start: 0,
        end: file_end,
    };
    if let Some(header) = find_child_box(reader, root, *b"jp2h")
        .and_then(|range| find_child_box(reader, range, *b"ihdr"))
    {
        if header.body_start.checked_add(8)? > header.end {
            return None;
        }
        reader.seek(SeekFrom::Start(header.body_start)).ok()?;
        let mut values = [0_u8; 8];
        reader.read_exact(&mut values).ok()?;
        return MediaDimensions::new(
            u32::from_be_bytes(values[4..].try_into().ok()?),
            u32::from_be_bytes(values[..4].try_into().ok()?),
        );
    }

    reader.seek(SeekFrom::Start(0)).ok()?;
    let mut header = [0_u8; 32];
    reader.read_exact(&mut header).ok()?;
    if header[..2] != [0xff, 0x4f] || header[2..4] != [0xff, 0x51] {
        return None;
    }
    let width = u32::from_be_bytes(header[8..12].try_into().ok()?)
        .checked_sub(u32::from_be_bytes(header[16..20].try_into().ok()?))?;
    let height = u32::from_be_bytes(header[12..16].try_into().ok()?)
        .checked_sub(u32::from_be_bytes(header[20..24].try_into().ok()?))?;
    MediaDimensions::new(width, height)
}

pub(crate) fn video_dimensions<R: Read + Seek>(reader: &mut R) -> Option<MediaDimensions> {
    reader.seek(SeekFrom::Start(0)).ok()?;
    if let Some(dimensions) = iso_video_dimensions(reader) {
        return Some(dimensions);
    }

    reader.seek(SeekFrom::Start(0)).ok()?;
    let parsed_dimensions = MediaSource::seekable(&mut *reader)
        .ok()
        .and_then(|source| {
            let mut parser = MediaParser::new();
            parser.parse_track(source).ok()
        })
        .and_then(|info| {
            let dimensions = MediaDimensions {
                width: info.get(TrackInfoTag::Width).and_then(unsigned_value)?,
                height: info.get(TrackInfoTag::Height).and_then(unsigned_value)?,
            };
            dimensions.aspect_ratio()?;
            Some(dimensions)
        });

    if parsed_dimensions.is_some() {
        return parsed_dimensions;
    }

    reader.seek(SeekFrom::Start(0)).ok()?;
    legacy_video_dimensions(reader)
}

fn legacy_video_dimensions<R: Read>(reader: &mut R) -> Option<MediaDimensions> {
    const HEADER_LIMIT: u64 = 2 * 1024 * 1024;

    let mut bytes = Vec::new();
    reader.take(HEADER_LIMIT).read_to_end(&mut bytes).ok()?;
    avi_dimensions(&bytes)
        .or_else(|| mpeg_dimensions(&bytes))
        .or_else(|| theora_dimensions(&bytes))
}

fn avi_dimensions(bytes: &[u8]) -> Option<MediaDimensions> {
    if bytes.len() < 12 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"AVI " {
        return None;
    }
    let offset = bytes.windows(4).position(|window| window == b"avih")?;
    let body = offset.checked_add(8)?;
    if body.checked_add(40)? > bytes.len() {
        return None;
    }
    MediaDimensions::new(
        u32::from_le_bytes(bytes[body + 32..body + 36].try_into().ok()?),
        u32::from_le_bytes(bytes[body + 36..body + 40].try_into().ok()?),
    )
}

fn mpeg_dimensions(bytes: &[u8]) -> Option<MediaDimensions> {
    let offset = bytes
        .windows(4)
        .position(|window| window == [0x00, 0x00, 0x01, 0xb3])?;
    let body = offset.checked_add(4)?;
    if body.checked_add(3)? > bytes.len() {
        return None;
    }
    let width = (u32::from(bytes[body]) << 4) | (u32::from(bytes[body + 1]) >> 4);
    let height = (u32::from(bytes[body + 1] & 0x0f) << 8) | u32::from(bytes[body + 2]);
    MediaDimensions::new(width, height)
}

fn theora_dimensions(bytes: &[u8]) -> Option<MediaDimensions> {
    let offset = bytes
        .windows(7)
        .position(|window| window == b"\x80theora")?;
    let header = offset.checked_add(7)?;
    if header.checked_add(13)? > bytes.len() {
        return None;
    }
    let width = u32::from_be_bytes([0, bytes[header + 7], bytes[header + 8], bytes[header + 9]]);
    let height = u32::from_be_bytes([
        0,
        bytes[header + 10],
        bytes[header + 11],
        bytes[header + 12],
    ]);
    MediaDimensions::new(width, height)
}

fn unsigned_value(value: &EntryValue) -> Option<u32> {
    match value {
        EntryValue::U8(value) => Some(u32::from(*value)),
        EntryValue::U16(value) => Some(u32::from(*value)),
        EntryValue::U32(value) => Some(*value),
        EntryValue::U64(value) => (*value).try_into().ok(),
        _ => None,
    }
}

fn svg_dimensions<R: Read>(reader: &mut R) -> Option<MediaDimensions> {
    const MAX_SVG_HEADER_BYTES: u64 = 64 * 1024;

    let mut bytes = Vec::new();
    reader
        .take(MAX_SVG_HEADER_BYTES)
        .read_to_end(&mut bytes)
        .ok()?;
    let text = std::str::from_utf8(&bytes).ok()?;
    let root_start = text.find("<svg")?;
    let root = &text[root_start..text[root_start..].find('>')? + root_start + 1];

    if let Some(view_box) = svg_attribute(root, "viewBox") {
        let values: Vec<f64> = view_box
            .split(|character: char| character.is_ascii_whitespace() || character == ',')
            .filter(|value| !value.is_empty())
            .filter_map(|value| value.parse().ok())
            .collect();
        if values.len() == 4 {
            return scaled_dimensions(values[2], values[3]);
        }
    }

    let width = svg_length(svg_attribute(root, "width")?)?;
    let height = svg_length(svg_attribute(root, "height")?)?;
    scaled_dimensions(width, height)
}

fn svg_attribute<'a>(root: &'a str, name: &str) -> Option<&'a str> {
    let bytes = root.as_bytes();
    let mut cursor = 0;
    while let Some(relative) = root[cursor..].find(name) {
        let start = cursor + relative;
        let before_is_name = start > 0
            && (bytes[start - 1].is_ascii_alphanumeric()
                || matches!(bytes[start - 1], b'-' | b'_' | b':'));
        let end = start + name.len();
        let after_is_name = end < bytes.len()
            && (bytes[end].is_ascii_alphanumeric() || matches!(bytes[end], b'-' | b'_' | b':'));
        cursor = end;
        if before_is_name || after_is_name {
            continue;
        }

        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if bytes.get(cursor) != Some(&b'=') {
            continue;
        }
        cursor += 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        let quote = *bytes.get(cursor)?;
        if quote != b'\'' && quote != b'"' {
            continue;
        }
        cursor += 1;
        let value_start = cursor;
        while cursor < bytes.len() && bytes[cursor] != quote {
            cursor += 1;
        }
        return root.get(value_start..cursor);
    }
    None
}

fn svg_length(value: &str) -> Option<f64> {
    let value = value.trim();
    if value.ends_with('%') {
        return None;
    }
    let numeric_end = value
        .char_indices()
        .take_while(|(_, character)| {
            character.is_ascii_digit() || matches!(character, '.' | '+' | '-' | 'e' | 'E')
        })
        .last()
        .map(|(index, character)| index + character.len_utf8())?;
    value[..numeric_end].parse().ok()
}

fn scaled_dimensions(width: f64, height: f64) -> Option<MediaDimensions> {
    if !width.is_finite() || !height.is_finite() || width <= 0.0 || height <= 0.0 {
        return None;
    }
    let ratio = width / height;
    let scale = 10_000.0;
    let scaled_width = (ratio * scale).round();
    if !(1.0..=u32::MAX as f64).contains(&scaled_width) {
        return None;
    }
    Some(MediaDimensions {
        width: scaled_width as u32,
        height: scale as u32,
    })
}

#[derive(Debug, Clone, Copy)]
struct BoxRange {
    body_start: u64,
    end: u64,
}

fn iso_video_dimensions<R: Read + Seek>(reader: &mut R) -> Option<MediaDimensions> {
    let file_end = reader.seek(SeekFrom::End(0)).ok()?;
    let root = BoxRange {
        body_start: 0,
        end: file_end,
    };
    let moov = find_child_box(reader, root, *b"moov")?;

    let mut cursor = moov.body_start;
    while let Some((box_type, range)) = next_box(reader, &mut cursor, moov.end) {
        if box_type != *b"trak" || !track_is_video(reader, range) {
            continue;
        }
        let track_header = find_child_box(reader, range, *b"tkhd")?;
        return track_header_dimensions(reader, track_header);
    }
    None
}

fn track_is_video<R: Read + Seek>(reader: &mut R, track: BoxRange) -> bool {
    let Some(media) = find_child_box(reader, track, *b"mdia") else {
        return false;
    };
    let Some(handler) = find_child_box(reader, media, *b"hdlr") else {
        return false;
    };
    if handler
        .body_start
        .checked_add(12)
        .is_none_or(|end| end > handler.end)
    {
        return false;
    }
    if reader
        .seek(SeekFrom::Start(handler.body_start + 8))
        .is_err()
    {
        return false;
    }
    let mut handler_type = [0_u8; 4];
    reader.read_exact(&mut handler_type).is_ok() && handler_type == *b"vide"
}

fn track_header_dimensions<R: Read + Seek>(
    reader: &mut R,
    track_header: BoxRange,
) -> Option<MediaDimensions> {
    reader.seek(SeekFrom::Start(track_header.body_start)).ok()?;
    let mut version = [0_u8; 1];
    reader.read_exact(&mut version).ok()?;
    let matrix_offset = match version[0] {
        0 => 40,
        1 => 52,
        _ => return None,
    };
    let matrix_start = track_header.body_start.checked_add(matrix_offset)?;
    let dimensions_start = matrix_start.checked_add(36)?;
    if dimensions_start.checked_add(8)? > track_header.end {
        return None;
    }
    reader.seek(SeekFrom::Start(matrix_start)).ok()?;
    let mut values = [0_u8; 20];
    reader.read_exact(&mut values).ok()?;
    let a = signed_fixed_16_16(i32::from_be_bytes(values[0..4].try_into().ok()?));
    let b = signed_fixed_16_16(i32::from_be_bytes(values[4..8].try_into().ok()?));
    let c = signed_fixed_16_16(i32::from_be_bytes(values[12..16].try_into().ok()?));
    let d = signed_fixed_16_16(i32::from_be_bytes(values[16..20].try_into().ok()?));
    reader.seek(SeekFrom::Start(dimensions_start)).ok()?;
    let mut raw_dimensions = [0_u8; 8];
    reader.read_exact(&mut raw_dimensions).ok()?;
    let width = unsigned_fixed_16_16(u32::from_be_bytes(raw_dimensions[..4].try_into().ok()?));
    let height = unsigned_fixed_16_16(u32::from_be_bytes(raw_dimensions[4..].try_into().ok()?));

    rounded_dimensions(
        a.abs() * width + c.abs() * height,
        b.abs() * width + d.abs() * height,
    )
}

fn signed_fixed_16_16(value: i32) -> f64 {
    f64::from(value) / 65_536.0
}

fn unsigned_fixed_16_16(value: u32) -> f64 {
    f64::from(value) / 65_536.0
}

fn rounded_dimensions(width: f64, height: f64) -> Option<MediaDimensions> {
    if !width.is_finite() || !height.is_finite() || width <= 0.0 || height <= 0.0 {
        return None;
    }
    let width = width.round();
    let height = height.round();
    if width > u32::MAX as f64 || height > u32::MAX as f64 {
        return None;
    }
    MediaDimensions::new(width as u32, height as u32)
}

fn find_child_box<R: Read + Seek>(
    reader: &mut R,
    parent: BoxRange,
    wanted: [u8; 4],
) -> Option<BoxRange> {
    let mut cursor = parent.body_start;
    while let Some((box_type, range)) = next_box(reader, &mut cursor, parent.end) {
        if box_type == wanted {
            return Some(range);
        }
    }
    None
}

fn next_box<R: Read + Seek>(
    reader: &mut R,
    cursor: &mut u64,
    parent_end: u64,
) -> Option<([u8; 4], BoxRange)> {
    if cursor.checked_add(8)? > parent_end {
        return None;
    }
    reader.seek(SeekFrom::Start(*cursor)).ok()?;
    let mut header = [0_u8; 8];
    reader.read_exact(&mut header).ok()?;
    let size32 = u32::from_be_bytes(header[..4].try_into().ok()?) as u64;
    let box_type = header[4..8].try_into().ok()?;
    let (size, header_size) = match size32 {
        0 => (parent_end.checked_sub(*cursor)?, 8),
        1 => {
            let mut extended = [0_u8; 8];
            reader.read_exact(&mut extended).ok()?;
            (u64::from_be_bytes(extended), 16)
        }
        value => (value, 8),
    };
    if size < header_size {
        return None;
    }
    let end = cursor.checked_add(size)?;
    if end > parent_end {
        return None;
    }
    let body_start = cursor.checked_add(header_size)?;
    *cursor = end;
    Some((box_type, BoxRange { body_start, end }))
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use super::*;

    #[test]
    fn reads_portrait_png_dimensions() {
        let mut png = vec![
            0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, b'I', b'H', b'D', b'R',
        ];
        png.extend_from_slice(&1900_u32.to_be_bytes());
        png.extend_from_slice(&2468_u32.to_be_bytes());
        png.extend_from_slice(&[8, 6, 0, 0, 0, 0, 0, 0, 0]);

        assert_eq!(
            image_dimensions(&mut Cursor::new(png)),
            Some(MediaDimensions {
                width: 1900,
                height: 2468
            })
        );
    }

    #[test]
    fn applies_exif_orientation_to_jpeg_dimensions() {
        let mut jpeg = vec![0xff, 0xd8, 0xff, 0xe1, 0x00, 0x22];
        jpeg.extend_from_slice(b"Exif\0\0");
        jpeg.extend_from_slice(&[
            b'I', b'I', 0x2a, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0,
            0, 0,
        ]);
        jpeg.extend_from_slice(&[
            0xff, 0xc0, 0, 17, 8, 0x04, 0xb0, 0x03, 0x20, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0,
            0xff, 0xd9,
        ]);
        jpeg.resize(256, 0);

        assert_eq!(
            image_dimensions(&mut Cursor::new(jpeg)),
            Some(MediaDimensions {
                width: 1200,
                height: 800
            })
        );
    }

    #[test]
    fn reads_svg_view_box_dimensions() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1900 2468"></svg>"#;

        let dimensions = image_dimensions(&mut Cursor::new(svg)).unwrap();
        assert!((dimensions.aspect_ratio().unwrap() - 1900.0 / 2468.0).abs() < 0.0001);
    }

    #[test]
    fn reads_jpeg2000_dimensions() {
        let mut image_header = Vec::new();
        image_header.extend_from_slice(&2468_u32.to_be_bytes());
        image_header.extend_from_slice(&1900_u32.to_be_bytes());
        let jp2 = atom(*b"jp2h", atom(*b"ihdr", image_header));

        assert_eq!(
            image_dimensions(&mut Cursor::new(jp2)),
            Some(MediaDimensions {
                width: 1900,
                height: 2468
            })
        );
    }

    #[test]
    fn reads_legacy_video_container_dimensions() {
        let mut avi = b"RIFF\0\0\0\0AVI avih".to_vec();
        avi.extend_from_slice(&40_u32.to_le_bytes());
        avi.extend_from_slice(&[0_u8; 32]);
        avi.extend_from_slice(&640_u32.to_le_bytes());
        avi.extend_from_slice(&480_u32.to_le_bytes());

        let mpeg = [0x00, 0x00, 0x01, 0xb3, 0x28, 0x01, 0xe0];

        let mut theora = b"OggS\x80theora\x03\x02\x01\0\0\0\0".to_vec();
        theora.extend_from_slice(&[0x00, 0x02, 0x80, 0x00, 0x01, 0xe0]);

        for (bytes, expected) in [
            (
                avi,
                MediaDimensions {
                    width: 640,
                    height: 480,
                },
            ),
            (
                mpeg.to_vec(),
                MediaDimensions {
                    width: 640,
                    height: 480,
                },
            ),
            (
                theora,
                MediaDimensions {
                    width: 640,
                    height: 480,
                },
            ),
        ] {
            assert_eq!(video_dimensions(&mut Cursor::new(bytes)), Some(expected));
        }
    }

    #[test]
    fn reads_iso_dimensions_and_applies_track_matrices() {
        let identity = track_box([0x0001_0000, 0, 0, 0x0001_0000]);
        let quarter_turn = track_box([0, 0x0001_0000, -0x0001_0000, 0]);
        let scaled = track_box([0x0002_0000, 0, 0, 0x0002_0000]);

        assert_eq!(
            video_dimensions(&mut Cursor::new(identity)),
            Some(MediaDimensions {
                width: 640,
                height: 480
            })
        );
        assert_eq!(
            video_dimensions(&mut Cursor::new(quarter_turn)),
            Some(MediaDimensions {
                width: 480,
                height: 640
            })
        );
        assert_eq!(
            video_dimensions(&mut Cursor::new(scaled)),
            Some(MediaDimensions {
                width: 1280,
                height: 960
            })
        );
    }

    fn track_box(matrix: [i32; 4]) -> Vec<u8> {
        let mut tkhd_body = vec![0_u8; 40];
        tkhd_body.extend_from_slice(&matrix[0].to_be_bytes());
        tkhd_body.extend_from_slice(&matrix[1].to_be_bytes());
        tkhd_body.extend_from_slice(&0_i32.to_be_bytes());
        tkhd_body.extend_from_slice(&matrix[2].to_be_bytes());
        tkhd_body.extend_from_slice(&matrix[3].to_be_bytes());
        tkhd_body.extend_from_slice(&0_i32.to_be_bytes());
        tkhd_body.extend_from_slice(&0_i32.to_be_bytes());
        tkhd_body.extend_from_slice(&0_i32.to_be_bytes());
        tkhd_body.extend_from_slice(&0x4000_0000_i32.to_be_bytes());
        tkhd_body.extend_from_slice(&(640_u32 << 16).to_be_bytes());
        tkhd_body.extend_from_slice(&(480_u32 << 16).to_be_bytes());

        let mut handler_body = vec![0_u8; 8];
        handler_body.extend_from_slice(b"vide");
        let hdlr = atom(*b"hdlr", handler_body);
        let mdia = atom(*b"mdia", hdlr);
        let mut trak_body = atom(*b"tkhd", tkhd_body);
        trak_body.extend_from_slice(&mdia);
        let trak = atom(*b"trak", trak_body);
        atom(*b"moov", trak)
    }

    fn atom(box_type: [u8; 4], body: Vec<u8>) -> Vec<u8> {
        let mut result = Vec::with_capacity(body.len() + 8);
        result.extend_from_slice(&u32::try_from(body.len() + 8).unwrap().to_be_bytes());
        result.extend_from_slice(&box_type);
        result.extend_from_slice(&body);
        result
    }
}
