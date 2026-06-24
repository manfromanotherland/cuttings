// SPDX-License-Identifier: MIT

use std::fs;
use std::io::Write as _;

use anyhow::Result;
use sha2::{Digest, Sha256};

use crate::frontmatter::{parse_reading, render_reading};
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
pub fn find_duplicate(library: &LibraryRoot, canonical_url: &str) -> Result<Option<String>> {
    let articles_dir = library.articles_dir();
    if !articles_dir.is_dir() {
        return Ok(None);
    }
    for entry in fs::read_dir(&articles_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|e| e.to_str()) == Some("md") {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(reading) = parse_reading(&content) {
                    if reading.metadata.canonical_url == canonical_url {
                        return Ok(Some(reading.metadata.id));
                    }
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
}
