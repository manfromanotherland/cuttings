// SPDX-License-Identifier: MIT

use anyhow::Result;
use rusqlite::{params, Connection};

use crate::{
    scanner::{scan_library, ScanDiff, ScannedReading},
    LibraryRoot,
};

/// Apply a set of scanner diffs to the index in a single transaction.
pub fn apply_diffs(conn: &Connection, diffs: &[ScanDiff]) -> Result<()> {
    if diffs.is_empty() {
        return Ok(());
    }

    let tx = conn.unchecked_transaction()?;

    for diff in diffs {
        match diff {
            ScanDiff::Added(r) => insert(conn, r)?,
            ScanDiff::Changed(r) => update(conn, r)?,
            ScanDiff::Removed(id) => delete(conn, id)?,
        }
    }

    tx.commit()?;
    Ok(())
}

/// Rebuild the index from scratch: clear all rows then re-insert every article.
///
/// The FTS triggers keep `readings_fts` in sync automatically.
pub fn rebuild(conn: &Connection, library: &LibraryRoot) -> Result<()> {
    let readings = scan_library(library)?;

    let tx = conn.unchecked_transaction()?;

    conn.execute("DELETE FROM readings", [])?;

    for r in &readings {
        insert(conn, r)?;
    }

    tx.commit()?;
    Ok(())
}

fn insert(conn: &Connection, r: &ScannedReading) -> Result<()> {
    let tags = serde_json::to_string(&r.metadata.tags)?;
    conn.execute(
        "INSERT OR REPLACE INTO readings
         (id, url, canonical_url, title, author, site, saved_at,
          read, archived, favorite, source_hash, excerpt, word_count,
          lang, tags_json, body_text)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
        params![
            r.metadata.id,
            r.metadata.url,
            r.metadata.canonical_url,
            r.metadata.title,
            r.metadata.author,
            r.metadata.site,
            r.metadata.saved_at,
            r.metadata.read as i32,
            r.metadata.archived as i32,
            r.metadata.favorite as i32,
            r.metadata.source_hash,
            r.metadata.excerpt,
            r.metadata.word_count,
            r.metadata.lang,
            tags,
            r.body,
        ],
    )?;
    Ok(())
}

fn update(conn: &Connection, r: &ScannedReading) -> Result<()> {
    let tags = serde_json::to_string(&r.metadata.tags)?;
    conn.execute(
        "UPDATE readings SET
         url=?2, canonical_url=?3, title=?4, author=?5, site=?6,
         saved_at=?7, read=?8, archived=?9, favorite=?10,
         source_hash=?11, excerpt=?12, word_count=?13, lang=?14,
         tags_json=?15, body_text=?16
         WHERE id=?1",
        params![
            r.metadata.id,
            r.metadata.url,
            r.metadata.canonical_url,
            r.metadata.title,
            r.metadata.author,
            r.metadata.site,
            r.metadata.saved_at,
            r.metadata.read as i32,
            r.metadata.archived as i32,
            r.metadata.favorite as i32,
            r.metadata.source_hash,
            r.metadata.excerpt,
            r.metadata.word_count,
            r.metadata.lang,
            tags,
            r.body,
        ],
    )?;
    Ok(())
}

fn delete(conn: &Connection, id: &str) -> Result<()> {
    conn.execute("DELETE FROM readings WHERE id=?1", params![id])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;
    use crate::{index::open, new_id, scanner, write_reading, LibraryRoot, Metadata};

    fn make_library(dir: &TempDir) -> LibraryRoot {
        fs::create_dir_all(dir.path().join("articles")).unwrap();
        LibraryRoot::new(dir.path()).unwrap()
    }

    fn sample_meta(id: &str, url: &str) -> Metadata {
        Metadata {
            format_version: 1,
            id: id.to_string(),
            url: url.to_string(),
            canonical_url: url.to_string(),
            title: "Title".to_string(),
            author: None,
            site: None,
            saved_at: "2026-06-13T15:00:00Z".to_string(),
            read: false,
            archived: false,
            favorite: false,
            tags: vec![],
            excerpt: None,
            word_count: None,
            lang: None,
            source_hash: String::new(),
        }
    }

    fn row_count(conn: &Connection) -> i64 {
        conn.query_row("SELECT COUNT(*) FROM readings", [], |r| r.get(0))
            .unwrap()
    }

    #[test]
    fn rebuild_indexes_all_articles() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        write_reading(
            &lib,
            sample_meta(&new_id(), "https://a.com"),
            "body a".to_string(),
        )
        .unwrap();
        write_reading(
            &lib,
            sample_meta(&new_id(), "https://b.com"),
            "body b".to_string(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();
        assert_eq!(row_count(&conn), 2);
    }

    #[test]
    fn rebuild_is_idempotent() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        write_reading(
            &lib,
            sample_meta(&new_id(), "https://a.com"),
            "body".to_string(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();
        rebuild(&conn, &lib).unwrap();
        assert_eq!(row_count(&conn), 1);
    }

    #[test]
    fn apply_diffs_add_inserts_row() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(
            &lib,
            sample_meta(&id, "https://example.com"),
            "hello".to_string(),
        )
        .unwrap();

        let new_scan = scanner::scan_library(&lib).unwrap();
        let diffs = scanner::diff(&[], &new_scan);
        apply_diffs(&conn, &diffs).unwrap();

        assert_eq!(row_count(&conn), 1);
    }

    #[test]
    fn apply_diffs_remove_deletes_row() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(
            &lib,
            sample_meta(&id, "https://example.com"),
            "hello".to_string(),
        )
        .unwrap();
        let old_scan = scanner::scan_library(&lib).unwrap();
        apply_diffs(&conn, &scanner::diff(&[], &old_scan)).unwrap();

        fs::remove_file(lib.article_path(&id)).unwrap();
        let new_scan = scanner::scan_library(&lib).unwrap();
        let diffs = scanner::diff(&old_scan, &new_scan);
        apply_diffs(&conn, &diffs).unwrap();

        assert_eq!(row_count(&conn), 0);
    }

    #[test]
    fn apply_diffs_change_updates_row() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let id = new_id();
        write_reading(
            &lib,
            sample_meta(&id, "https://example.com"),
            "v1".to_string(),
        )
        .unwrap();
        let old_scan = scanner::scan_library(&lib).unwrap();
        apply_diffs(&conn, &scanner::diff(&[], &old_scan)).unwrap();

        write_reading(
            &lib,
            sample_meta(&id, "https://example.com"),
            "v2".to_string(),
        )
        .unwrap();
        let new_scan = scanner::scan_library(&lib).unwrap();
        let diffs = scanner::diff(&old_scan, &new_scan);
        apply_diffs(&conn, &diffs).unwrap();

        // Still one row, but body changed.
        assert_eq!(row_count(&conn), 1);
        let body: String = conn
            .query_row(
                "SELECT body_text FROM readings WHERE id=?1",
                params![id],
                |r| r.get(0),
            )
            .unwrap();
        assert!(body.contains("v2"));
    }

    #[test]
    fn rebuild_then_diff_no_ops_are_empty() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        write_reading(
            &lib,
            sample_meta(&new_id(), "https://a.com"),
            "body".to_string(),
        )
        .unwrap();

        let scan = scanner::scan_library(&lib).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Diff a scan against itself — nothing to apply.
        let diffs = scanner::diff(&scan, &scan);
        assert!(diffs.is_empty());
        apply_diffs(&conn, &diffs).unwrap();
        assert_eq!(row_count(&conn), 1);
    }
}
