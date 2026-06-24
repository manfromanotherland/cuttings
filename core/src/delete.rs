// SPDX-License-Identifier: MIT

//! Permanent deletion of a reading.
//!
//! Unlike archiving (which only flips the `archived` flag in the frontmatter),
//! deleting removes the Markdown file and the reading's asset directory from
//! disk, then drops its row from the index. This is irreversible.

use anyhow::{bail, Result};
use rusqlite::Connection;

use crate::{reconcile::apply_diffs, scanner::ScanDiff, LibraryRoot};

/// Permanently delete the reading `id`: its `.md` file, its assets, and its
/// index row. Errors if the reading does not exist.
pub fn delete_reading(library: &LibraryRoot, conn: &Connection, id: &str) -> Result<()> {
    let path = library.article_path(id);
    if !path.is_file() {
        bail!("reading not found: {id}");
    }

    std::fs::remove_file(&path)?;

    // Remove downloaded images/assets, if any were stored for this reading.
    let assets = library.assets_dir(id);
    if assets.is_dir() {
        std::fs::remove_dir_all(&assets)?;
    }

    // Remove any highlights saved against this reading; they live outside the
    // index (in `highlights/`) so nothing else would clean them up.
    crate::highlights::delete_all_highlights(library, id)?;

    apply_diffs(conn, &[ScanDiff::Removed(id.to_string())])
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
    fn delete_unknown_id_errors() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        assert!(delete_reading(&lib, &conn, "no-such-id").is_err());
    }
}
