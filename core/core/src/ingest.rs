// SPDX-License-Identifier: MIT

//! Shared save and import orchestration.
//!
//! Browser captures and native-app imports both enter the library through this
//! module so identity, deduplication, asset writing, and placeholder upgrades
//! stay identical across clients.

use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};
use url::Url;

use crate::{
    find_by_media, find_by_url, first_local_image_asset, media_id, quote_id, read_metadata,
    sha256_hex, url_id, ImageBytes, LibraryRoot, Metadata, ReadingKind,
};
use crate::{
    images::write_images_under_lock,
    locking::{lock_reading, ReadingLock},
    writer::write_reading_under_lock,
};

const LOCAL_ORIGIN_SCHEME: &str = "cuttings://local";
const LOCAL_ASSET_SCHEME: &str = "cuttings-asset:";
// This single directory intentionally persists after its temporary files are
// removed. Deleting a shared staging directory creates a cross-process race:
// one importer can remove it between another importer's create_dir_all and
// create_new calls. Empty operational directories are ignored by the scanner.
const IMPORT_STAGING_DIRECTORY: &str = ".cuttings-imports";
const VIDEO_COPY_BUFFER_SIZE: usize = 1024 * 1024;
const QUOTE_EXCERPT_CHARACTERS: usize = 600;

/// Everything required to persist one browser capture or native import.
pub struct SaveInput {
    /// Optional canonical quote text used only for identity. Source-less text
    /// supplies its whitespace-normalized content here while retaining the
    /// original line structure in `markdown`; browser captures leave it unset.
    pub quote_identity_markdown: Option<String>,
    pub kind: ReadingKind,
    pub lightweight: bool,
    pub url: String,
    pub media_url: Option<String>,
    pub canonical_url: String,
    pub title: String,
    pub author: Option<String>,
    pub site: Option<String>,
    pub saved_at: String,
    pub markdown: String,
    pub images: Vec<ImageBytes>,
    pub excerpt: Option<String>,
    pub word_count: Option<u32>,
    pub lang: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveDisposition {
    Saved,
    Upgraded,
    Duplicate,
}

/// Structured, friendly result returned for both writes and duplicates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SaveOutcome {
    pub disposition: SaveDisposition,
    pub id: String,
    /// Path to `article.md`, relative to the library root.
    pub path: String,
}

/// Invalid capture data is kept distinct from storage failures so the native
/// messaging adapter can preserve its protocol-v2 error classification.
#[derive(Debug, thiserror::Error)]
pub enum SaveError {
    #[error("{0}")]
    InvalidRequest(String),
    #[error(transparent)]
    Storage(#[from] anyhow::Error),
}

impl From<std::io::Error> for SaveError {
    fn from(error: std::io::Error) -> Self {
        Self::Storage(error.into())
    }
}

/// Save one capture, returning a duplicate as data rather than an error.
///
/// A full article capture is allowed to overwrite an earlier lightweight link
/// placeholder at the same URL-derived id. That upgrade preserves every field
/// controlled by the user after import; captured page metadata and content are
/// replaced by the richer browser result.
pub fn save_capture(library: &LibraryRoot, input: SaveInput) -> Result<SaveOutcome, SaveError> {
    let id = capture_id(&input)?;
    // Identity is known before touching disk. Hold its cross-process lock from
    // the duplicate/placeholder read through asset writes and atomic rename.
    let lock = lock_reading(library, &id)?;
    save_capture_under_lock(library, input, id, &lock)
}

fn save_capture_under_lock(
    library: &LibraryRoot,
    input: SaveInput,
    id: String,
    lock: &ReadingLock,
) -> Result<SaveOutcome, SaveError> {
    lock.ensure_protects(library, &id)?;
    let existing_id = find_existing(library, &input, &id)?;

    let previous = existing_id
        .as_deref()
        .and_then(|existing| read_metadata(&library.article_path(existing)).ok());
    let upgrading = previous.as_ref().is_some_and(|metadata| {
        input.kind == ReadingKind::Article
            && !input.lightweight
            && metadata.kind == ReadingKind::Article
            && metadata.lightweight
            && metadata.id == id
    });

    if let Some(existing_id) = existing_id {
        if !upgrading {
            return Ok(outcome(library, SaveDisposition::Duplicate, existing_id));
        }
    }

    let markdown = write_images_under_lock(library, &id, &input.markdown, &input.images, lock)?;
    let preview_asset = first_local_image_asset(&markdown);

    let mut metadata = Metadata {
        format_version: 1,
        id: id.clone(),
        kind: input.kind,
        lightweight: input.lightweight,
        url: input.url,
        media_url: input.media_url,
        preview_asset,
        canonical_url: input.canonical_url,
        title: input.title,
        author: input.author,
        site: input.site,
        saved_at: input.saved_at,
        read_at: None,
        archived: false,
        favorite: false,
        rating: 0,
        tags: vec![],
        excerpt: input.excerpt,
        word_count: input.word_count,
        lang: input.lang,
        source_hash: String::new(),
    };

    if let Some(previous) = previous.filter(|_| upgrading) {
        metadata.saved_at = previous.saved_at;
        metadata.read_at = previous.read_at;
        metadata.archived = previous.archived;
        metadata.favorite = previous.favorite;
        metadata.rating = previous.rating;
        metadata.tags = previous.tags;
    }

    write_reading_under_lock(library, metadata, markdown, lock)?;
    Ok(outcome(
        library,
        if upgrading {
            SaveDisposition::Upgraded
        } else {
            SaveDisposition::Saved
        },
        id,
    ))
}

/// Import an HTTP(S) URL without fetching it. The placeholder deliberately uses
/// the normal article id so a later browser capture upgrades this same reading.
pub fn import_link(library: &LibraryRoot, url: &str) -> Result<SaveOutcome, SaveError> {
    let normalized = normalize_http_url(url)?;
    let parsed = Url::parse(&normalized).map_err(invalid)?;
    let site = parsed.host_str().map(str::to_string);

    save_capture(
        library,
        SaveInput {
            quote_identity_markdown: None,
            kind: ReadingKind::Article,
            lightweight: true,
            url: normalized.clone(),
            media_url: None,
            canonical_url: normalized.clone(),
            title: normalized.clone(),
            author: None,
            site,
            saved_at: crate::time::now_utc_iso(),
            markdown: format!("[Open link](<{normalized}>)"),
            images: vec![],
            excerpt: None,
            word_count: None,
            lang: None,
        },
    )
}

/// Import source-less plain text as a quote. Identity ignores whitespace-only
/// differences while the stored body retains the user's line structure.
pub fn import_text(
    library: &LibraryRoot,
    text: &str,
    title: Option<&str>,
) -> Result<SaveOutcome, SaveError> {
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    let trimmed = text.trim();
    let identity_text = normalized_text(trimmed);
    if identity_text.is_empty() {
        return Err(SaveError::InvalidRequest(
            "text import requires non-empty text".to_string(),
        ));
    }

    let content_hash = sha256_hex(format!("quote\0{identity_text}").as_bytes());
    let origin = format!("{LOCAL_ORIGIN_SCHEME}/quote/{content_hash}");
    let title = title
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .unwrap_or("Saved quote");
    let markdown = trimmed
        .split('\n')
        .map(|line| {
            if line.is_empty() {
                ">".to_string()
            } else {
                format!("> {line}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n");

    save_capture(
        library,
        SaveInput {
            quote_identity_markdown: Some(identity_text.clone()),
            kind: ReadingKind::Quote,
            lightweight: false,
            url: origin.clone(),
            media_url: None,
            canonical_url: origin,
            title: title.to_string(),
            author: None,
            site: None,
            saved_at: crate::time::now_utc_iso(),
            markdown,
            images: vec![],
            excerpt: Some(truncate_chars(&identity_text, QUOTE_EXCERPT_CHARACTERS)),
            word_count: Some(identity_text.split_whitespace().count() as u32),
            lang: None,
        },
    )
}

/// Import source-less image bytes. The byte hash drives both the synthetic
/// origin and the content-addressed media id, so filenames and pasteboard
/// representations of the same bytes deduplicate.
pub fn import_image(
    library: &LibraryRoot,
    bytes: Vec<u8>,
    content_type: &str,
    title: &str,
) -> Result<SaveOutcome, SaveError> {
    if bytes.is_empty() {
        return Err(SaveError::InvalidRequest(
            "image import requires non-empty bytes".to_string(),
        ));
    }

    let content_hash = sha256_hex(&bytes);
    let origin = format!("{LOCAL_ORIGIN_SCHEME}/image/{content_hash}");
    let title = match title.trim() {
        "" => "Imported image",
        title => title,
    };

    save_capture(
        library,
        SaveInput {
            quote_identity_markdown: None,
            kind: ReadingKind::Image,
            lightweight: false,
            url: origin.clone(),
            media_url: Some(origin.clone()),
            canonical_url: origin.clone(),
            title: title.to_string(),
            author: None,
            site: None,
            saved_at: crate::time::now_utc_iso(),
            markdown: format!("![Imported image]({origin})"),
            images: vec![ImageBytes {
                url: origin,
                content_type: content_type.trim().to_string(),
                bytes,
            }],
            excerpt: None,
            word_count: None,
            lang: None,
        },
    )
}

/// Import a source-less local video without materializing it in memory.
///
/// The source is streamed once into a temporary file inside the library while
/// its bytes are hashed. The content hash determines the reading id and final
/// asset filename, so filenames and MIME aliases never affect deduplication.
/// The caller's path is used only for this copy and is never persisted.
pub fn import_video_file(
    library: &LibraryRoot,
    file_path: &Path,
    content_type: &str,
    title: &str,
) -> Result<SaveOutcome, SaveError> {
    let extension = video_extension(content_type)?;
    let mut staged = stage_video(library, file_path)?;
    let content_hash = staged.content_hash.clone();
    let origin = format!("{LOCAL_ORIGIN_SCHEME}/video/{content_hash}");
    let id = local_video_id(&content_hash);
    let filename = format!("{content_hash}.{extension}");
    let relative_asset = format!("assets/{filename}");
    let media_reference = format!("{LOCAL_ASSET_SCHEME}{relative_asset}");

    // Hashing must finish before the content-addressed lock is known. Hold it
    // from the duplicate check through the asset move and article rename so two
    // processes importing the same bytes cannot race each other.
    let lock = lock_reading(library, &id)?;
    if library.article_path(&id).is_file() {
        return Ok(outcome(library, SaveDisposition::Duplicate, id));
    }

    let assets_dir = library.assets_dir(&id);
    fs::create_dir_all(&assets_dir)?;
    let asset_path = assets_dir.join(&filename);
    staged.persist(&asset_path)?;

    let metadata = Metadata {
        format_version: 1,
        id: id.clone(),
        kind: ReadingKind::Video,
        lightweight: false,
        url: origin.clone(),
        media_url: Some(media_reference),
        preview_asset: None,
        canonical_url: origin,
        title: match title.trim() {
            "" => "Imported video".to_string(),
            title => title.to_string(),
        },
        author: None,
        site: None,
        saved_at: crate::time::now_utc_iso(),
        read_at: None,
        archived: false,
        favorite: false,
        rating: 0,
        tags: vec![],
        excerpt: None,
        word_count: None,
        lang: None,
        source_hash: String::new(),
    };
    let body = format!("[Play video]({relative_asset})");

    if let Err(error) = write_reading_under_lock(library, metadata, body, &lock) {
        // The article is the reading's commit marker. Do not leave a newly moved
        // asset behind when that atomic article write reports an ordinary error.
        let _ = fs::remove_file(&asset_path);
        return Err(error.into());
    }

    Ok(outcome(library, SaveDisposition::Saved, id))
}

/// A source-less video's id depends only on its kind and raw content hash. The
/// normalized extension is intentionally absent so the same bytes deduplicate
/// even if a caller supplied another filename or equivalent content type.
fn local_video_id(content_hash: &str) -> String {
    sha256_hex(format!("video\0{content_hash}").as_bytes())
}

fn video_extension(content_type: &str) -> Result<&'static str, SaveError> {
    let normalized = content_type
        .split(';')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    match normalized.as_str() {
        "video/mp4" => Ok("mp4"),
        "video/quicktime" => Ok("mov"),
        "video/m4v" | "video/x-m4v" => Ok("m4v"),
        "video/webm" => Ok("webm"),
        "video/mpeg" => Ok("mpeg"),
        "video/avi" | "video/x-msvideo" => Ok("avi"),
        "video/ogg" => Ok("ogv"),
        "video/x-matroska" => Ok("mkv"),
        "video/3gpp" => Ok("3gp"),
        "video/3gpp2" => Ok("3g2"),
        _ => Err(SaveError::InvalidRequest(format!(
            "unsupported video content type: {}",
            content_type.trim()
        ))),
    }
}

struct StagedVideo {
    path: Option<PathBuf>,
    content_hash: String,
}

impl StagedVideo {
    fn persist(&mut self, destination: &Path) -> Result<(), SaveError> {
        let source = self.path.as_ref().expect("staged video not yet persisted");
        fs::rename(source, destination)?;
        self.path = None;
        Ok(())
    }
}

impl Drop for StagedVideo {
    fn drop(&mut self) {
        if let Some(path) = self.path.as_ref() {
            let _ = fs::remove_file(path);
        }
    }
}

fn stage_video(library: &LibraryRoot, file_path: &Path) -> Result<StagedVideo, SaveError> {
    let metadata = fs::metadata(file_path).map_err(|error| {
        SaveError::InvalidRequest(format!("could not read video file: {error}"))
    })?;
    if !metadata.is_file() {
        return Err(SaveError::InvalidRequest(
            "video import source must be a regular file".to_string(),
        ));
    }

    let mut source = fs::File::open(file_path)?;
    let staging_dir = library.path().join(IMPORT_STAGING_DIRECTORY);
    fs::create_dir_all(&staging_dir)?;
    let staging_path = staging_dir.join(format!("video-{}.tmp", crate::new_id()));
    let mut destination = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&staging_path)?;

    let copy_result = stream_and_hash(&mut source, &mut destination);
    let sync_result = copy_result.as_ref().ok().map(|_| destination.sync_all());
    drop(destination);

    let (content_hash, byte_count) = match copy_result {
        Ok(result) => result,
        Err(error) => {
            let _ = fs::remove_file(&staging_path);
            return Err(error.into());
        }
    };
    if let Some(Err(error)) = sync_result {
        let _ = fs::remove_file(&staging_path);
        return Err(error.into());
    }
    if byte_count == 0 {
        let _ = fs::remove_file(&staging_path);
        return Err(SaveError::InvalidRequest(
            "video import requires a non-empty file".to_string(),
        ));
    }

    Ok(StagedVideo {
        path: Some(staging_path),
        content_hash,
    })
}

fn stream_and_hash(
    source: &mut fs::File,
    destination: &mut fs::File,
) -> std::io::Result<(String, u64)> {
    let mut hasher = Sha256::new();
    let mut byte_count = 0_u64;
    let mut buffer = vec![0_u8; VIDEO_COPY_BUFFER_SIZE];

    loop {
        let read = source.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        destination.write_all(&buffer[..read])?;
        hasher.update(&buffer[..read]);
        byte_count += read as u64;
    }

    Ok((hex::encode(hasher.finalize()), byte_count))
}

fn capture_id(input: &SaveInput) -> Result<String, SaveError> {
    let result = match input.kind {
        ReadingKind::Article => url_id(&input.url),
        ReadingKind::Image | ReadingKind::Video => match input.media_url.as_deref() {
            Some(media_url) => media_id(input.kind, &input.url, media_url),
            None => {
                return Err(SaveError::InvalidRequest(
                    "image and video saves require metadata.media_url".to_string(),
                ))
            }
        },
        ReadingKind::Quote => quote_id(
            &input.url,
            input
                .quote_identity_markdown
                .as_deref()
                .unwrap_or(&input.markdown),
        ),
    };
    result
        .map_err(|error| SaveError::InvalidRequest(format!("could not derive reading id: {error}")))
}

fn find_existing(
    library: &LibraryRoot,
    input: &SaveInput,
    id: &str,
) -> Result<Option<String>, SaveError> {
    match input.kind {
        ReadingKind::Article => find_by_url(library, &input.url).map_err(Into::into),
        ReadingKind::Image | ReadingKind::Video => find_by_media(
            library,
            input.kind,
            &input.url,
            input.media_url.as_deref().expect("validated by capture_id"),
        )
        .map_err(Into::into),
        ReadingKind::Quote => Ok(library.article_path(id).is_file().then(|| id.to_string())),
    }
}

fn outcome(library: &LibraryRoot, disposition: SaveDisposition, id: String) -> SaveOutcome {
    let article_path = library.article_path(&id);
    let path = article_path
        .strip_prefix(library.path())
        .unwrap_or(&article_path)
        .to_string_lossy()
        .into_owned();
    SaveOutcome {
        disposition,
        id,
        path,
    }
}

fn normalize_http_url(raw: &str) -> Result<String, SaveError> {
    let parsed = Url::parse(raw.trim()).map_err(invalid)?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(SaveError::InvalidRequest(
            "link import requires an http(s) URL".to_string(),
        ));
    }
    crate::normalize_url(parsed.as_str()).map_err(SaveError::Storage)
}

fn invalid(error: impl std::fmt::Display) -> SaveError {
    SaveError::InvalidRequest(error.to_string())
}

fn normalized_text(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn truncate_chars(text: &str, max: usize) -> String {
    let mut chars = text.chars();
    let truncated: String = chars.by_ref().take(max).collect();
    if chars.next().is_some() {
        format!("{truncated}…")
    } else {
        truncated
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        parse_reading, set_favorite, set_rating, set_read, writer::write_reading_under_lock,
    };
    use std::{fs, sync::mpsc};

    fn library() -> (tempfile::TempDir, LibraryRoot) {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        (dir, library)
    }

    fn full_capture(url: &str) -> SaveInput {
        SaveInput {
            quote_identity_markdown: None,
            kind: ReadingKind::Article,
            lightweight: false,
            url: url.to_string(),
            media_url: None,
            canonical_url: url.to_string(),
            title: "Captured title".to_string(),
            author: Some("Author".to_string()),
            site: Some("example.com".to_string()),
            saved_at: "2026-08-24T12:00:00.000Z".to_string(),
            markdown: "# Captured title\n\nFull body.".to_string(),
            images: vec![],
            excerpt: Some("Full body.".to_string()),
            word_count: Some(2),
            lang: Some("en".to_string()),
        }
    }

    fn assert_staging_empty(library: &LibraryRoot) {
        let staging = library.path().join(IMPORT_STAGING_DIRECTORY);
        if staging.is_dir() {
            assert_eq!(
                fs::read_dir(staging).unwrap().count(),
                0,
                "temporary video imports must be cleaned up"
            );
        }
    }

    #[test]
    fn link_uses_article_identity_and_is_persistently_lightweight() {
        let (_dir, library) = library();
        let url = "https://www.example.com/post/?utm_source=paste";

        let result = import_link(&library, url).unwrap();
        let reading =
            parse_reading(&std::fs::read_to_string(library.article_path(&result.id)).unwrap())
                .unwrap();

        assert_eq!(result.disposition, SaveDisposition::Saved);
        assert_eq!(result.id, url_id(url).unwrap());
        assert!(reading.metadata.lightweight);
        assert_eq!(reading.metadata.url, "https://example.com/post");
    }

    #[test]
    fn full_capture_upgrades_link_and_preserves_user_state() {
        let (_dir, library) = library();
        let url = "https://example.com/post";
        let imported = import_link(&library, url).unwrap();
        let original = read_metadata(&library.article_path(&imported.id)).unwrap();

        let index_dir = tempfile::TempDir::new().unwrap();
        let conn = crate::open_index(&index_dir.path().join("index.db")).unwrap();
        crate::rebuild(&conn, &library).unwrap();
        set_read(&library, &conn, &imported.id, true).unwrap();
        set_rating(&library, &conn, &imported.id, 4).unwrap();
        crate::add_tag(&library, &conn, &imported.id, "later").unwrap();

        let result = save_capture(&library, full_capture(url)).unwrap();
        let reading =
            parse_reading(&std::fs::read_to_string(library.article_path(&result.id)).unwrap())
                .unwrap();

        assert_eq!(result.disposition, SaveDisposition::Upgraded);
        assert!(!reading.metadata.lightweight);
        assert_eq!(reading.metadata.saved_at, original.saved_at);
        assert!(reading.metadata.read_at.is_some());
        assert_eq!(reading.metadata.rating, 4);
        assert_eq!(reading.metadata.tags, vec!["later"]);
        assert_eq!(reading.metadata.title, "Captured title");
        assert_eq!(reading.body, "# Captured title\n\nFull body.\n");
    }

    #[test]
    fn normal_article_duplicate_stays_structured() {
        let (_dir, library) = library();
        let url = "https://example.com/post";
        save_capture(&library, full_capture(url)).unwrap();

        let duplicate = save_capture(&library, full_capture(url)).unwrap();
        assert_eq!(duplicate.disposition, SaveDisposition::Duplicate);
        assert_eq!(duplicate.id, url_id(url).unwrap());
    }

    #[test]
    fn text_import_has_content_identity_and_synthetic_origin() {
        let (_dir, library) = library();
        let first = import_text(&library, " A selected\npassage. ", Some("Notes.txt")).unwrap();
        let duplicate = import_text(&library, "A  selected passage.", None).unwrap();
        let reading = read_metadata(&library.article_path(&first.id)).unwrap();

        assert_eq!(duplicate.disposition, SaveDisposition::Duplicate);
        assert_eq!(first.id, duplicate.id);
        assert!(reading.url.starts_with("cuttings://local/quote/"));
        assert_eq!(reading.kind, ReadingKind::Quote);
        assert_eq!(reading.title, "Notes.txt");
    }

    #[test]
    fn image_import_writes_bytes_and_deduplicates_by_content() {
        let (_dir, library) = library();
        let bytes = b"normalized image bytes".to_vec();
        let first = import_image(&library, bytes.clone(), "image/png", "Pasted image").unwrap();
        let duplicate = import_image(&library, bytes.clone(), "image/png", "Other title").unwrap();
        let reading = read_metadata(&library.article_path(&first.id)).unwrap();

        assert_eq!(duplicate.disposition, SaveDisposition::Duplicate);
        assert_eq!(first.id, duplicate.id);
        assert!(reading.url.starts_with("cuttings://local/image/"));
        assert_eq!(reading.kind, ReadingKind::Image);
        let asset = reading.preview_asset.unwrap();
        assert_eq!(
            std::fs::read(library.reading_dir(&first.id).join(asset)).unwrap(),
            bytes
        );
    }

    #[test]
    fn video_import_streams_to_a_content_addressed_local_asset() {
        let (_dir, library) = library();
        let source_dir = tempfile::TempDir::new().unwrap();
        let source = source_dir.path().join("private-original-name.mp4");
        let mut bytes = vec![0x5a; VIDEO_COPY_BUFFER_SIZE * 2 + 137];
        bytes[0..8].copy_from_slice(b"ftypmp42");
        fs::write(&source, &bytes).unwrap();

        let imported = import_video_file(
            &library,
            &source,
            " Video/MP4; codecs=avc1 ",
            " Local clip ",
        )
        .unwrap();
        let article = fs::read_to_string(library.article_path(&imported.id)).unwrap();
        let reading = parse_reading(&article).unwrap();
        let content_hash = sha256_hex(&bytes);
        let relative_asset = format!("assets/{content_hash}.mp4");

        assert_eq!(imported.disposition, SaveDisposition::Saved);
        assert_eq!(imported.id, local_video_id(&content_hash));
        assert_eq!(reading.metadata.kind, ReadingKind::Video);
        assert_eq!(
            reading.metadata.url,
            format!("cuttings://local/video/{content_hash}")
        );
        assert_eq!(reading.metadata.canonical_url, reading.metadata.url);
        assert_eq!(reading.metadata.title, "Local clip");
        assert_eq!(
            reading.metadata.media_url.as_deref(),
            Some(format!("cuttings-asset:{relative_asset}").as_str())
        );
        assert_eq!(reading.metadata.preview_asset, None);
        assert_eq!(reading.body, format!("[Play video]({relative_asset})\n"));
        assert_eq!(
            fs::read(library.reading_dir(&imported.id).join(&relative_asset)).unwrap(),
            bytes
        );
        assert!(
            !article.contains(source.to_string_lossy().as_ref()),
            "the caller's source path must never be persisted"
        );
        assert_staging_empty(&library);
    }

    #[test]
    fn video_import_deduplicates_identical_bytes_across_names_and_types() {
        let (_dir, library) = library();
        let source_dir = tempfile::TempDir::new().unwrap();
        let first_path = source_dir.path().join("first.mp4");
        let second_path = source_dir.path().join("renamed.mov");
        let bytes = b"the exact same local video bytes";
        fs::write(&first_path, bytes).unwrap();
        fs::write(&second_path, bytes).unwrap();

        let first = import_video_file(&library, &first_path, "video/mp4", "First title").unwrap();
        let duplicate =
            import_video_file(&library, &second_path, "video/quicktime", "Different title")
                .unwrap();

        assert_eq!(duplicate.disposition, SaveDisposition::Duplicate);
        assert_eq!(duplicate.id, first.id);
        let reading = read_metadata(&library.article_path(&first.id)).unwrap();
        assert_eq!(reading.title, "First title");
        assert!(reading.media_url.unwrap().ends_with(".mp4"));
        assert_eq!(
            fs::read_dir(library.assets_dir(&first.id)).unwrap().count(),
            1
        );
        assert_staging_empty(&library);
    }

    #[test]
    fn imported_video_remains_after_the_source_is_deleted() {
        let (_dir, library) = library();
        let source_dir = tempfile::TempDir::new().unwrap();
        let source = source_dir.path().join("delete-me.webm");
        let bytes = b"portable copied video";
        fs::write(&source, bytes).unwrap();

        let imported = import_video_file(&library, &source, "video/webm", "Portable clip").unwrap();
        fs::remove_file(&source).unwrap();

        let metadata = read_metadata(&library.article_path(&imported.id)).unwrap();
        let reference = metadata.media_url.unwrap();
        let relative_asset = reference.strip_prefix(LOCAL_ASSET_SCHEME).unwrap();
        assert_eq!(
            fs::read(library.reading_dir(&imported.id).join(relative_asset)).unwrap(),
            bytes
        );
    }

    #[test]
    fn video_import_rejects_missing_directory_empty_and_unsupported_inputs() {
        let (_dir, library) = library();
        let source_dir = tempfile::TempDir::new().unwrap();
        let empty = source_dir.path().join("empty.mp4");
        let nonempty = source_dir.path().join("clip.mp4");
        fs::write(&empty, []).unwrap();
        fs::write(&nonempty, b"bytes").unwrap();

        for result in [
            import_video_file(
                &library,
                &source_dir.path().join("missing.mp4"),
                "video/mp4",
                "Missing",
            ),
            import_video_file(&library, source_dir.path(), "video/mp4", "Directory"),
            import_video_file(&library, &empty, "video/mp4", "Empty"),
            import_video_file(&library, &nonempty, "application/octet-stream", "Unknown"),
        ] {
            assert!(matches!(result, Err(SaveError::InvalidRequest(_))));
        }
        assert_staging_empty(&library);
    }

    #[test]
    fn video_staging_file_is_cleaned_when_the_save_fails() {
        let (_dir, library) = library();
        let source_dir = tempfile::TempDir::new().unwrap();
        let source = source_dir.path().join("clip.mp4");
        fs::write(&source, b"staged before lock failure").unwrap();
        // Blocking the lock directory makes the post-hash save fail after the
        // staging file exists, exercising the guard's downstream-error cleanup.
        fs::write(library.path().join(".cuttings-locks"), b"not a directory").unwrap();

        assert!(matches!(
            import_video_file(&library, &source, "video/mp4", "Clip"),
            Err(SaveError::Storage(_))
        ));
        assert_staging_empty(&library);
    }

    #[test]
    fn video_content_types_map_to_safe_canonical_extensions() {
        assert_eq!(video_extension("video/mp4").unwrap(), "mp4");
        assert_eq!(
            video_extension("VIDEO/QUICKTIME; charset=binary").unwrap(),
            "mov"
        );
        assert_eq!(video_extension("video/x-m4v").unwrap(), "m4v");
        assert_eq!(video_extension("video/webm").unwrap(), "webm");
        assert!(video_extension("../video/mp4").is_err());
        assert!(video_extension("application/octet-stream").is_err());
    }

    #[test]
    fn imports_reject_empty_or_non_http_content() {
        let (_dir, library) = library();
        assert!(matches!(
            import_link(&library, "file:///tmp/a"),
            Err(SaveError::InvalidRequest(_))
        ));
        assert!(matches!(
            import_text(&library, " \n\t", None),
            Err(SaveError::InvalidRequest(_))
        ));
        assert!(matches!(
            import_image(&library, vec![], "image/png", ""),
            Err(SaveError::InvalidRequest(_))
        ));
    }

    #[test]
    fn concurrent_state_write_before_upgrade_preserves_state_and_full_body() {
        let (_dir, library) = library();
        let url = "https://example.com/concurrent-before";
        let imported = import_link(&library, url).unwrap();

        // Hold the exact sidecar the public upgrade path must acquire. Start the
        // upgrade before committing a state edit made from the lightweight
        // snapshot; it cannot read that snapshot until this atomic write ends.
        let lock = lock_reading(&library, &imported.id).unwrap();
        let library_path = library.path().to_path_buf();
        let (started_tx, started_rx) = mpsc::channel();
        let upgrade = std::thread::spawn(move || {
            let library = LibraryRoot::new(library_path).unwrap();
            started_tx.send(()).unwrap();
            save_capture(&library, full_capture(url)).unwrap()
        });
        started_rx.recv().unwrap();

        let content = std::fs::read_to_string(library.article_path(&imported.id)).unwrap();
        let mut reading = parse_reading(&content).unwrap();
        reading.metadata.tags.push("raced-tag".to_string());
        reading.metadata.favorite = true;
        reading.metadata.rating = 5;
        write_reading_under_lock(&library, reading.metadata, reading.body, &lock).unwrap();
        drop(lock);

        let outcome = upgrade.join().unwrap();
        assert_eq!(outcome.disposition, SaveDisposition::Upgraded);
        let reading =
            parse_reading(&std::fs::read_to_string(library.article_path(&imported.id)).unwrap())
                .unwrap();
        assert_eq!(reading.body, "# Captured title\n\nFull body.\n");
        assert_eq!(reading.metadata.tags, vec!["raced-tag"]);
        assert!(reading.metadata.favorite);
        assert_eq!(reading.metadata.rating, 5);
    }

    #[test]
    fn concurrent_app_mutations_after_upgrade_preserve_full_body() {
        let (_dir, library) = library();
        let url = "https://example.com/concurrent-after";
        let imported = import_link(&library, url).unwrap();
        let index_dir = tempfile::TempDir::new().unwrap();
        let index_path = index_dir.path().join("index.db");
        let conn = crate::open_index(&index_path).unwrap();
        crate::rebuild(&conn, &library).unwrap();
        drop(conn);

        // Keep the upgrade lock while the app-side tag/status/rating worker is
        // launched. Its real public RMW methods can proceed only after the full
        // body is atomically installed, so each reads and retains that body.
        let lock = lock_reading(&library, &imported.id).unwrap();
        let library_path = library.path().to_path_buf();
        let id = imported.id.clone();
        let (started_tx, started_rx) = mpsc::channel();
        let mutations = std::thread::spawn(move || {
            let library = LibraryRoot::new(library_path).unwrap();
            let conn = crate::open_index(&index_path).unwrap();
            started_tx.send(()).unwrap();
            crate::add_tag(&library, &conn, &id, "after-upgrade").unwrap();
            set_read(&library, &conn, &id, true).unwrap();
            set_favorite(&library, &conn, &id, true).unwrap();
            set_rating(&library, &conn, &id, 4).unwrap();
        });
        started_rx.recv().unwrap();

        let outcome =
            save_capture_under_lock(&library, full_capture(url), imported.id.clone(), &lock)
                .unwrap();
        drop(lock);
        mutations.join().unwrap();

        assert_eq!(outcome.disposition, SaveDisposition::Upgraded);
        let reading =
            parse_reading(&std::fs::read_to_string(library.article_path(&imported.id)).unwrap())
                .unwrap();
        assert_eq!(reading.body, "# Captured title\n\nFull body.\n");
        assert_eq!(reading.metadata.tags, vec!["after-upgrade"]);
        assert!(reading.metadata.read_at.is_some());
        assert!(reading.metadata.favorite);
        assert_eq!(reading.metadata.rating, 4);
    }
}
