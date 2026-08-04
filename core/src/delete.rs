// SPDX-License-Identifier: MIT

//! Permanent deletion of a reading.
//!
//! Unlike archiving (which only flips the `archived` flag in the frontmatter),
//! deleting removes the reading's entire folder from disk — its `article.md`,
//! `assets/`, and `highlights.md` in one `remove_dir_all` — then drops its row
//! from the index. This is irreversible.

use anyhow::{bail, Result};
use rusqlite::Connection;

use crate::{reconcile::apply_diffs, scanner::ScanDiff, LibraryRoot};

/// Permanently delete the reading `id`: its whole folder and its index row.
/// Errors if the reading does not exist.
///
/// Deleting a folder is far blunter than deleting a single file, so this is
/// deliberately conservative about *what* it will remove. The guardrails ensure
/// the target is a single reading's folder and never a shared ancestor:
///
/// - the id must look like a real reading id (non-empty, ASCII-alphanumeric), so
///   a crafted value can't smuggle `/` or `..` into the path and escape the
///   reading folder;
/// - the resolved folder must still contain an `article.md` — i.e. it really is
///   a reading folder, not an empty or unrelated directory; and
/// - the folder must sit *below* a fan-out bucket, never at `articles/` or a
///   bucket itself, so one delete can never wipe many readings at once.
pub fn delete_reading(library: &LibraryRoot, conn: &Connection, id: &str) -> Result<()> {
    if !is_valid_reading_id(id) {
        bail!("refusing to delete: invalid reading id {id:?}");
    }

    let dir = library.reading_dir(id);

    if !library.article_path(id).is_file() {
        bail!("reading not found: {id}");
    }

    // Defensive: `dir` must be nested two levels under articles/ (bucket → id),
    // so it can never be the articles/ root or a bucket directory even if the
    // path helpers change. `parent()` of a real reading folder is its bucket.
    let articles = library.articles_dir();
    let is_reading_folder = dir.starts_with(&articles)
        && dir != articles
        && dir.parent().is_some_and(|bucket| bucket != articles);
    if !is_reading_folder {
        bail!(
            "refusing to delete: {} is not a reading folder",
            dir.display()
        );
    }

    std::fs::remove_dir_all(&dir)?;

    apply_diffs(conn, &[ScanDiff::Removed(id.to_string())])
}

/// A reading id must be non-empty and ASCII-alphanumeric — true for both
/// content-addressed ids (64-char lowercase hex) and ULIDs (Crockford base32).
/// Rejecting anything else keeps a bad id from resolving the reading folder to a
/// path outside a single reading (no `/`, no `.`/`..`, no empty component).
fn is_valid_reading_id(id: &str) -> bool {
    !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;
    use crate::{index::open, new_id, reconcile::rebuild, write_reading, LibraryRoot, Metadata};

    fn make_library(dir: &TempDir) -> LibraryRoot {
        fs::create_dir_all(dir.path().join("articles")).unwrap();
        LibraryRoot::new(dir.path()).unwrap()
    }

    fn meta(id: &str) -> Metadata {
        Metadata {
            format_version: 1,
            id: id.to_string(),
            url: "https://example.com".to_string(),
            canonical_url: "https://example.com".to_string(),
            title: "Test".to_string(),
            author: None,
            site: None,
            saved_at: "2026-06-13T15:00:00Z".to_string(),
            read_at: None,
            archived: false,
            favorite: false,
            rating: 0,
            tags: vec![],
            excerpt: None,
            word_count: None,
            lang: None,
            source_hash: String::new(),
        }
    }

    fn row_count(conn: &Connection, id: &str) -> i64 {
        conn.query_row(
            "SELECT COUNT(*) FROM readings WHERE id = ?1",
            rusqlite::params![id],
            |r| r.get(0),
        )
        .unwrap()
    }

    #[test]
    fn delete_removes_file_assets_and_row() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        // Simulate a stored asset for this reading.
        let assets = lib.assets_dir(&id);
        fs::create_dir_all(&assets).unwrap();
        fs::write(assets.join("image.png"), b"x").unwrap();
        // ...and a saved highlight, which lives outside the index.
        crate::highlights::add_highlight(&lib, &id, "a passage").unwrap();
        rebuild(&conn, &lib).unwrap();
        assert_eq!(row_count(&conn, &id), 1);

        delete_reading(&lib, &conn, &id).unwrap();

        assert!(!lib.article_path(&id).exists());
        assert!(!assets.exists());
        assert!(!lib.highlights_path(&id).exists());
        assert_eq!(row_count(&conn, &id), 0);
    }

    #[test]
    fn delete_succeeds_without_assets() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        delete_reading(&lib, &conn, &id).unwrap();
        assert!(!lib.article_path(&id).exists());
        assert_eq!(row_count(&conn, &id), 0);
    }

    #[test]
    fn delete_removes_the_whole_reading_folder() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        crate::highlights::add_highlight(&lib, &id, "a passage").unwrap();
        rebuild(&conn, &lib).unwrap();
        assert!(lib.reading_dir(&id).is_dir());

        delete_reading(&lib, &conn, &id).unwrap();

        // The entire folder is gone — article, assets, and highlights with it.
        assert!(!lib.reading_dir(&id).exists());
        assert_eq!(row_count(&conn, &id), 0);
    }

    #[test]
    fn delete_unknown_id_errors() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        // A well-formed id that simply isn't present hits the not-found guard.
        assert!(delete_reading(&lib, &conn, &new_id()).is_err());
    }

    #[test]
    fn delete_rejects_malformed_ids_without_touching_disk() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        // Seed one real reading so there is something a traversal could target.
        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Ids that could escape a single reading folder are refused outright.
        for bad in ["", "..", "../../..", "a/b", "8f/8f.md", "."] {
            assert!(
                delete_reading(&lib, &conn, bad).is_err(),
                "malformed id {bad:?} must be refused"
            );
        }

        // The real reading is untouched.
        assert!(lib.article_path(&id).is_file());
        assert_eq!(row_count(&conn, &id), 1);
    }
}
