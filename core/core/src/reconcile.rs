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
    let tags_text = r.metadata.tags.join(" ");
    conn.execute(
        "INSERT OR REPLACE INTO readings
         (id, kind, lightweight, has_note, url, media_url, preview_asset, canonical_url, title,
          author, site, saved_at, read_at, archived, favorite, rating, source_hash, excerpt,
          word_count, lang, tags_json, tags_text, body_text)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23)",
        params![
            r.metadata.id,
            r.metadata.kind.as_str(),
            r.metadata.lightweight as i32,
            r.has_note as i32,
            r.metadata.url,
            r.metadata.media_url,
            r.metadata.preview_asset,
            r.metadata.canonical_url,
            r.metadata.title,
            r.metadata.author,
            r.metadata.site,
            r.metadata.saved_at,
            r.metadata.read_at,
            r.metadata.archived as i32,
            r.metadata.favorite as i32,
            r.metadata.rating,
            r.metadata.source_hash,
            r.metadata.excerpt,
            r.metadata.word_count,
            r.metadata.lang,
            tags,
            tags_text,
            r.body,
        ],
    )?;
    Ok(())
}

fn update(conn: &Connection, r: &ScannedReading) -> Result<()> {
    let tags = serde_json::to_string(&r.metadata.tags)?;
    let tags_text = r.metadata.tags.join(" ");
    conn.execute(
        "UPDATE readings SET
         kind=?2, lightweight=?3, has_note=?4, url=?5, media_url=?6, preview_asset=?7,
         canonical_url=?8, title=?9, author=?10, site=?11, saved_at=?12, read_at=?13,
         archived=?14, favorite=?15, rating=?16, source_hash=?17, excerpt=?18,
         word_count=?19, lang=?20, tags_json=?21, tags_text=?22, body_text=?23
         WHERE id=?1",
        params![
            r.metadata.id,
            r.metadata.kind.as_str(),
            r.metadata.lightweight as i32,
            r.has_note as i32,
            r.metadata.url,
            r.metadata.media_url,
            r.metadata.preview_asset,
            r.metadata.canonical_url,
            r.metadata.title,
            r.metadata.author,
            r.metadata.site,
            r.metadata.saved_at,
            r.metadata.read_at,
            r.metadata.archived as i32,
            r.metadata.favorite as i32,
            r.metadata.rating,
            r.metadata.source_hash,
            r.metadata.excerpt,
            r.metadata.word_count,
            r.metadata.lang,
            tags,
            tags_text,
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
            kind: Default::default(),
            lightweight: false,
            url: url.to_string(),
            media_url: None,
            preview_asset: None,
            canonical_url: url.to_string(),
            title: "Title".to_string(),
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
    fn rebuild_indexes_media_metadata() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        let id = new_id();
        let mut metadata = sample_meta(&id, "https://example.com/gallery");
        metadata.kind = crate::ReadingKind::Image;
        metadata.media_url = Some("https://cdn.example.com/photo.jpg".into());
        metadata.preview_asset = Some("assets/photo.jpg".into());
        write_reading(&lib, metadata, "![Photo](assets/photo.jpg)".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let values: (String, Option<String>, Option<String>) = conn
            .query_row(
                "SELECT kind, media_url, preview_asset FROM readings WHERE id = ?1",
                params![id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(
            values,
            (
                "image".into(),
                Some("https://cdn.example.com/photo.jpg".into()),
                Some("assets/photo.jpg".into())
            )
        );
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
