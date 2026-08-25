// SPDX-License-Identifier: MIT

use std::sync::{Mutex, OnceLock};

use anyhow::bail;
use ulid::{Generator, Ulid};

use crate::ReadingKind;

/// Generate a new ULID string (26-char Crockford Base32).
///
/// IDs are **monotonically increasing**: a process-wide generator increments
/// the random component for IDs created within the same millisecond, so IDs
/// produced in sequence always sort in creation order. (Plain `Ulid::new()`
/// only sorts across milliseconds — within one, its random suffix is
/// unordered, which would let two saves in the same millisecond sort out of
/// insertion order.)
pub fn new_id() -> String {
    static GENERATOR: OnceLock<Mutex<Generator>> = OnceLock::new();
    let generator = GENERATOR.get_or_init(|| Mutex::new(Generator::new()));
    let mut guard = generator.lock().unwrap_or_else(|e| e.into_inner());
    // `generate` only errors on monotonic overflow within a single millisecond
    // (practically impossible) or if the system clock moves backwards; fall
    // back to a fresh random ULID so we always return a valid 26-char id.
    guard.generate().unwrap_or_else(|_| Ulid::new()).to_string()
}

/// Content-addressed id for a page: the SHA-256 (hex) of its normalized URL.
///
/// Deterministic — the same page always yields the same id, so it doubles as the
/// dedup key and the article's filename stem. Errors only if the URL can't be
/// parsed (e.g. a non-http scheme), in which case the caller decides what to do.
pub fn url_id(url: &str) -> anyhow::Result<String> {
    Ok(crate::writer::sha256_hex(
        crate::normalize_url(url)?.as_bytes(),
    ))
}

/// Content-addressed id for one image or video saved from a page.
///
/// The identity includes the kind, normalized source-page URL, and a direct
/// media identity. HTTP(S) media URLs are normalized; opaque schemes such as
/// `blob:` retain their trimmed raw value. NUL separators make the three
/// components unambiguous.
/// Articles deliberately continue to use [`url_id`] so their existing ids do
/// not change.
pub fn media_id(
    kind: ReadingKind,
    source_page_url: &str,
    media_url: &str,
) -> anyhow::Result<String> {
    if !kind.is_media() {
        bail!("media_id requires image or video kind");
    }

    let source_page_url = crate::normalize_url(source_page_url)?;
    let media_url = normalized_media_identity(media_url)?;
    let identity = format!("{}\0{}\0{}", kind.as_str(), source_page_url, media_url);
    Ok(crate::writer::sha256_hex(identity.as_bytes()))
}

/// HTTP(S) assets receive the same URL normalization as source pages. Browser
/// media can also be addressed by `blob:` or another page-local scheme; those
/// values are stable only as opaque strings, so preserve their trimmed form.
fn normalized_media_identity(media_url: &str) -> anyhow::Result<String> {
    let media_url = media_url.trim();
    if media_url.is_empty() {
        bail!("media_id requires a non-empty media URL");
    }

    if let Some(content_hash) = local_asset_content_hash(media_url) {
        return Ok(format!("cuttings-asset:sha256:{content_hash}"));
    }

    let is_http = url::Url::parse(media_url)
        .map(|url| matches!(url.scheme(), "http" | "https"))
        .unwrap_or(false);
    if is_http {
        crate::normalize_url(media_url)
    } else {
        Ok(media_url.to_string())
    }
}

/// Extract the content address from the constrained local-media reference.
///
/// The extension describes the stored representation but is not part of its
/// identity. This lets the same bytes from one origin deduplicate when two
/// import sources report equivalent or conflicting MIME aliases.
fn local_asset_content_hash(media_url: &str) -> Option<String> {
    let filename = media_url.strip_prefix("cuttings-asset:assets/")?;
    let (hash, extension) = filename.split_once('.')?;
    if hash.len() != 64
        || !hash.chars().all(|character| character.is_ascii_hexdigit())
        || extension.is_empty()
        || !extension
            .chars()
            .all(|character| character.is_ascii_alphanumeric())
    {
        return None;
    }
    Some(hash.to_ascii_lowercase())
}

/// Content-addressed id for a selected quote saved from a page.
///
/// Quote identity is the normalized source-page URL plus normalized selected
/// Markdown. Selection normalization trims its edges and collapses every run of
/// Unicode whitespace to one ASCII space; case and punctuation remain intact.
/// The original Markdown is still stored unchanged as the reading body.
pub fn quote_id(source_page_url: &str, markdown: &str) -> anyhow::Result<String> {
    let source_page_url = crate::normalize_url(source_page_url)?;
    let selected_text = markdown.split_whitespace().collect::<Vec<_>>().join(" ");
    if selected_text.is_empty() {
        bail!("quote_id requires non-empty selected markdown");
    }
    let identity = format!("quote\0{source_page_url}\0{selected_text}");
    Ok(crate::writer::sha256_hex(identity.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_is_26_chars() {
        let id = new_id();
        assert_eq!(id.len(), 26);
    }

    #[test]
    fn ids_are_sorted_by_creation_order() {
        // The monotonic generator must keep ids strictly increasing even when
        // many are produced within the same millisecond — a tight loop is the
        // worst case for the old random-suffix behaviour.
        let mut prev = new_id();
        for _ in 0..1000 {
            let next = new_id();
            assert!(prev < next, "{prev} should sort before {next}");
            prev = next;
        }
    }

    #[test]
    fn ids_are_unique() {
        let a = new_id();
        let b = new_id();
        assert_ne!(a, b);
    }

    #[test]
    fn url_id_is_deterministic() {
        let u = "https://example.com/post";
        assert_eq!(url_id(u).unwrap(), url_id(u).unwrap());
    }

    #[test]
    fn url_id_is_64_char_lowercase_hex() {
        let id = url_id("https://example.com/post").unwrap();
        assert_eq!(id.len(), 64);
        assert!(id
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn url_id_ignores_tracking_params() {
        assert_eq!(
            url_id("https://example.com/post").unwrap(),
            url_id("https://example.com/post?utm_source=x").unwrap(),
        );
    }

    #[test]
    fn url_id_differs_for_distinct_pages() {
        assert_ne!(
            url_id("https://example.com/a").unwrap(),
            url_id("https://example.com/b").unwrap(),
        );
    }

    #[test]
    fn url_id_errors_on_unparseable_url() {
        assert!(url_id("not a url").is_err());
    }

    #[test]
    fn media_id_is_deterministic() {
        let source = "https://example.com/gallery";
        let media = "https://cdn.example.com/photo.jpg";
        assert_eq!(
            media_id(ReadingKind::Image, source, media).unwrap(),
            media_id(ReadingKind::Image, source, media).unwrap()
        );
    }

    #[test]
    fn media_id_distinguishes_media_on_the_same_page() {
        let source = "https://example.com/gallery";
        assert_ne!(
            media_id(ReadingKind::Image, source, "https://cdn.example.com/a.jpg").unwrap(),
            media_id(ReadingKind::Image, source, "https://cdn.example.com/b.jpg").unwrap()
        );
    }

    #[test]
    fn media_id_distinguishes_image_from_video() {
        let source = "https://example.com/post";
        let media = "https://cdn.example.com/media";
        assert_ne!(
            media_id(ReadingKind::Image, source, media).unwrap(),
            media_id(ReadingKind::Video, source, media).unwrap()
        );
    }

    #[test]
    fn media_id_normalizes_both_urls() {
        assert_eq!(
            media_id(
                ReadingKind::Image,
                "https://example.com/gallery?utm_source=feed",
                "https://cdn.example.com/photo.jpg?utm_campaign=social"
            )
            .unwrap(),
            media_id(
                ReadingKind::Image,
                "https://example.com/gallery",
                "https://cdn.example.com/photo.jpg"
            )
            .unwrap()
        );
    }

    #[test]
    fn media_id_uses_local_asset_content_hash_not_extension() {
        let source = "https://example.com/watch";
        let hash = "ab".repeat(32);

        assert_eq!(
            media_id(
                ReadingKind::Video,
                source,
                &format!("cuttings-asset:assets/{hash}.mp4")
            )
            .unwrap(),
            media_id(
                ReadingKind::Video,
                source,
                &format!("cuttings-asset:assets/{hash}.mov")
            )
            .unwrap()
        );
    }

    #[test]
    fn local_asset_content_hash_shape_is_strict() {
        let hash = "ab".repeat(32);
        assert_eq!(
            local_asset_content_hash(&format!("cuttings-asset:assets/{hash}.webm")),
            Some(hash)
        );
        assert!(local_asset_content_hash("cuttings-asset:assets/short.mp4").is_none());
        assert!(local_asset_content_hash(&format!(
            "cuttings-asset:assets/{}.tar.gz",
            "ab".repeat(32)
        ))
        .is_none());
    }

    #[test]
    fn media_id_accepts_trimmed_blob_urls() {
        let source = "https://example.com/watch";
        let blob = "blob:https://example.com/7e64a8cf";
        assert_eq!(
            media_id(ReadingKind::Video, source, &format!("  {blob}\n")).unwrap(),
            media_id(ReadingKind::Video, source, blob).unwrap()
        );
        assert_ne!(
            media_id(ReadingKind::Video, source, blob).unwrap(),
            media_id(
                ReadingKind::Video,
                source,
                "blob:https://example.com/another"
            )
            .unwrap()
        );
    }

    #[test]
    fn media_id_rejects_empty_media_url() {
        assert!(media_id(ReadingKind::Image, "https://example.com/gallery", "  \n ").is_err());
    }

    #[test]
    fn media_id_rejects_article_kind() {
        assert!(media_id(
            ReadingKind::Article,
            "https://example.com/post",
            "https://cdn.example.com/photo.jpg"
        )
        .is_err());
    }

    #[test]
    fn quote_id_normalizes_source_and_selected_whitespace() {
        assert_eq!(
            quote_id(
                "https://example.com/post?utm_source=feed",
                "  A quoted\n\tpassage.  "
            )
            .unwrap(),
            quote_id("https://example.com/post", "A quoted passage.").unwrap()
        );
    }

    #[test]
    fn quote_id_distinguishes_selections_on_one_page() {
        let source = "https://example.com/post";
        assert_ne!(
            quote_id(source, "First passage").unwrap(),
            quote_id(source, "Second passage").unwrap()
        );
    }

    #[test]
    fn quote_id_rejects_empty_selection() {
        assert!(quote_id("https://example.com/post", " \n\t ").is_err());
    }
}
