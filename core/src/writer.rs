// SPDX-License-Identifier: MIT

use std::fs;
use std::io::Write as _;

use anyhow::Result;
use sha2::{Digest, Sha256};

use crate::frontmatter::{read_metadata, render_reading};
use crate::types::{LibraryRoot, Metadata, Reading};

/// Write a reading to the library atomically (temp-file + rename).
///
/// Computes and sets `source_hash` from the body before writing.
/// Creates `articles/` and `assets/<id>/` if they don't exist.
pub fn write_reading(
    library: &LibraryRoot,
    mut metadata: Metadata,
    body: String,
) -> Result<Reading> {
    metadata.source_hash = format!("sha256:{}", sha256_hex(body.as_bytes()));

    let reading = Reading { metadata, body };
    let content = render_reading(&reading)?;

    fs::create_dir_all(library.articles_dir())?;
    fs::create_dir_all(library.assets_dir(&reading.metadata.id))?;

    let article_path = library.article_path(&reading.metadata.id);
    let tmp_path = article_path.with_extension("md.tmp");

    {
        let mut f = fs::File::create(&tmp_path)?;
        f.write_all(content.as_bytes())?;
        f.sync_all()?;
    }
    fs::rename(&tmp_path, &article_path)?;

    Ok(reading)
}

/// Scan the library's articles directory for an article with the given canonical URL.
/// Returns the existing article's id if found.
///
/// URLs are compared after normalization (tracking params, fragment, trailing
/// slash, host case), so a page and its `?utm_source=…`-tagged variant dedupe
/// to the same reading.
pub fn find_duplicate(library: &LibraryRoot, canonical_url: &str) -> Result<Option<String>> {
    let target = norm_key(canonical_url);
    scan_articles(library, |m| norm_key(&m.canonical_url) == target)
}

/// Scan for an article that was saved from `url`, matching either the visible
/// `url` it was saved from or its `canonical_url`.
///
/// This is what the "is this page already saved?" check needs: the toolbar only
/// knows the visible tab URL — it can't run extraction to discover the page's
/// `<link rel=canonical>`. Matching the stored `url` lets a revisit of the same
/// address register as saved even when the canonical differs (query params
/// stripped, trailing slash enforced, etc.), which `find_duplicate`'s
/// canonical-only match would miss.
///
/// Both sides are normalized before comparison, so tracking params (`utm_*`,
/// `fbclid`, …) on the visited URL don't defeat the match.
pub fn find_saved(library: &LibraryRoot, url: &str) -> Result<Option<String>> {
    let target = norm_key(url);
    scan_articles(library, |m| {
        norm_key(&m.url) == target || norm_key(&m.canonical_url) == target
    })
}

/// Normalize a URL for matching, falling back to the raw string when it can't be
/// parsed (e.g. a non-http scheme) so exact-equality matching still works.
fn norm_key(url: &str) -> String {
    crate::normalize_url(url).unwrap_or_else(|_| url.to_string())
}

/// Scan `articles/*.md`, returning the id of the first article whose metadata
/// satisfies `matches`.
fn scan_articles(
    library: &LibraryRoot,
    matches: impl Fn(&Metadata) -> bool,
) -> Result<Option<String>> {
    let articles_dir = library.articles_dir();
    if !articles_dir.is_dir() {
        return Ok(None);
    }
    for entry in fs::read_dir(&articles_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|e| e.to_str()) == Some("md") {
            // Read only the frontmatter — the check compares URL fields and never
            // needs the article body, which is the bulk of each file.
            if let Ok(metadata) = read_metadata(&path) {
                if matches(&metadata) {
                    return Ok(Some(metadata.id));
                }
            }
        }
    }
    Ok(None)
}

pub fn sha256_hex(data: &[u8]) -> String {
    hex::encode(Sha256::digest(data))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Metadata;
    use tempfile::TempDir;

    fn tmp_library() -> (TempDir, LibraryRoot) {
        let dir = TempDir::new().unwrap();
        let lib = LibraryRoot::new(dir.path()).unwrap();
        (dir, lib)
    }

    fn sample_metadata() -> Metadata {
        Metadata {
            format_version: 1,
            id: crate::new_id(),
            url: "https://example.com/post".to_string(),
            canonical_url: "https://example.com/post".to_string(),
            title: "Test".to_string(),
            author: None,
            site: Some("example.com".to_string()),
            saved_at: "2026-06-13T15:00:00Z".to_string(),
            read_at: None,
            archived: false,
            favorite: false,
            rating: 0,
            tags: vec![],
            excerpt: None,
            word_count: None,
            lang: None,
            source_hash: String::new(), // set by write_reading
        }
    }

    #[test]
    fn writes_article_file() {
        let (_dir, lib) = tmp_library();
        let meta = sample_metadata();
        let id = meta.id.clone();

        write_reading(&lib, meta, "# Test\n\nContent.\n".to_string()).unwrap();

        assert!(lib.article_path(&id).exists());
        assert!(lib.assets_dir(&id).is_dir());
    }

    #[test]
    fn source_hash_is_set() {
        let (_dir, lib) = tmp_library();
        let meta = sample_metadata();
        let body = "# Test\n\nContent.\n".to_string();

        let reading = write_reading(&lib, meta, body.clone()).unwrap();

        let expected = format!("sha256:{}", sha256_hex(body.as_bytes()));
        assert_eq!(reading.metadata.source_hash, expected);
    }

    #[test]
    fn find_duplicate_detects_existing_canonical_url() {
        let (_dir, lib) = tmp_library();
        let meta = sample_metadata();
        let canonical = meta.canonical_url.clone();

        write_reading(&lib, meta, "# Test\n".to_string()).unwrap();

        let dup = find_duplicate(&lib, &canonical).unwrap();
        assert!(dup.is_some());
    }

    #[test]
    fn find_duplicate_returns_none_for_new_url() {
        let (_dir, lib) = tmp_library();
        let dup = find_duplicate(&lib, "https://example.com/new").unwrap();
        assert!(dup.is_none());
    }

    #[test]
    fn find_saved_matches_visible_url_when_canonical_differs() {
        // The page was saved from a feed URL but declared a different canonical.
        // The toolbar only knows the visible URL, so matching the stored `url` is
        // what makes the "already saved?" check work.
        let (_dir, lib) = tmp_library();
        let mut meta = sample_metadata();
        meta.url = "https://example.com/from-feed".to_string();
        meta.canonical_url = "https://example.com/post".to_string();
        write_reading(&lib, meta, "# Test\n".to_string()).unwrap();

        assert!(
            find_saved(&lib, "https://example.com/from-feed")
                .unwrap()
                .is_some(),
            "matches the visible url it was saved from"
        );
        assert!(
            find_saved(&lib, "https://example.com/post")
                .unwrap()
                .is_some(),
            "also matches the canonical url"
        );
        // find_duplicate stays canonical-only: a URL that matches only the
        // stored `url` (not the canonical) must not count as a duplicate.
        assert!(find_duplicate(&lib, "https://example.com/from-feed")
            .unwrap()
            .is_none());
    }

    #[test]
    fn find_saved_ignores_tracking_params() {
        // Regression: visiting a saved page with a utm tag must still show saved.
        let (_dir, lib) = tmp_library();
        let mut meta = sample_metadata();
        meta.url = "https://paulgraham.com/taste.html".to_string();
        meta.canonical_url = "https://paulgraham.com/taste.html".to_string();
        write_reading(&lib, meta, "# Taste\n".to_string()).unwrap();

        assert!(
            find_saved(
                &lib,
                "https://paulgraham.com/taste.html?utm_source=readcontrol.app"
            )
            .unwrap()
            .is_some(),
            "utm-tagged visit still matches the saved page"
        );
        assert!(
            find_saved(&lib, "https://paulgraham.com/articles.html?id=2")
                .unwrap()
                .is_none(),
            "a genuinely different page (meaningful query) must not match"
        );
    }

    #[test]
    fn find_duplicate_ignores_tracking_params() {
        // Saving the utm-tagged variant of an already-saved page is a duplicate.
        let (_dir, lib) = tmp_library();
        let mut meta = sample_metadata();
        meta.canonical_url = "https://example.com/post".to_string();
        write_reading(&lib, meta, "# Test\n".to_string()).unwrap();

        assert!(
            find_duplicate(&lib, "https://example.com/post?utm_source=x")
                .unwrap()
                .is_some()
        );
    }
}
