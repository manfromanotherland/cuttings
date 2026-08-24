// SPDX-License-Identifier: MIT

//! Shared save and import orchestration.
//!
//! Browser captures and native-app imports both enter the library through this
//! module so identity, deduplication, asset writing, and placeholder upgrades
//! stay identical across clients.

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
    use std::sync::mpsc;

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
