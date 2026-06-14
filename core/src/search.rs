// SPDX-License-Identifier: MIT

use anyhow::Result;
use rusqlite::{params, Connection};

/// A single result returned by a full-text search.
#[derive(Debug, Clone, PartialEq)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub excerpt: Option<String>,
    /// Context snippet with matched terms wrapped in `<mark>…</mark>`.
    pub snippet: String,
    pub tags: Vec<String>,
    pub saved_at: String,
}

/// Run a full-text search against the index.
///
/// `query` is passed directly to FTS5 MATCH, so callers can use FTS5 syntax
/// (e.g. `"exact phrase"`, `term*` for prefix). Results are ranked by BM25
/// relevance (best first) and capped at `limit`.
pub fn search(conn: &Connection, query: &str, limit: usize) -> Result<Vec<SearchResult>> {
    if query.trim().is_empty() {
        return Ok(vec![]);
    }

    let mut stmt = conn.prepare(
        "SELECT r.id, r.title, r.excerpt, r.tags_json, r.saved_at,
                snippet(readings_fts, 1, '<mark>', '</mark>', '…', 20)
         FROM readings_fts
         JOIN readings r ON r.rowid = readings_fts.rowid
         WHERE readings_fts MATCH ?1
         ORDER BY bm25(readings_fts)
         LIMIT ?2",
    )?;

    let rows = stmt.query_map(params![query, limit as i64], |row| {
        let tags_json: String = row.get(3)?;
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
            tags_json,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
        ))
    })?;

    let mut results = Vec::new();
    for row in rows {
        let (id, title, excerpt, tags_json, saved_at, snippet) = row?;
        let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
        results.push(SearchResult {
            id,
            title,
            excerpt,
            snippet,
            tags,
            saved_at,
        });
    }

    Ok(results)
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

    fn meta(id: &str, url: &str, title: &str) -> Metadata {
        Metadata {
            format_version: 1,
            id: id.to_string(),
            url: url.to_string(),
            canonical_url: url.to_string(),
            title: title.to_string(),
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

    fn setup() -> (TempDir, Connection) {
        let dir = TempDir::new().unwrap();
        let conn = open(&dir.path().join("index.db")).unwrap();
        (dir, conn)
    }

    #[test]
    fn empty_query_returns_nothing() {
        let (_dir, conn) = setup();
        let results = search(&conn, "", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn finds_match_in_title() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "Rust Programming Language"),
            "Some body text.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "rust", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn finds_match_in_body() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "An Article"),
            "Ownership and borrowing are core Rust concepts.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "borrowing", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn no_match_returns_empty() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Rust Article"),
            "Body about Rust.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "python", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn limit_caps_results() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        for i in 0..5 {
            write_reading(
                &lib,
                meta(&new_id(), &format!("https://example.com/{i}"), "Rust tips"),
                "Rust is great.".to_string(),
            )
            .unwrap();
        }
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "rust", 3).unwrap();
        assert_eq!(results.len(), 3);
    }

    #[test]
    fn snippet_contains_mark_tags() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Article"),
            "The lifetime system in Rust prevents dangling pointers.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "lifetime", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert!(
            results[0].snippet.contains("<mark>"),
            "snippet should highlight matched term"
        );
    }

    #[test]
    fn prefix_search_works() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Article"),
            "Asynchronous programming with async/await in Rust.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // FTS5 prefix search via trailing *
        let results = search(&conn, "async*", 10).unwrap();
        assert_eq!(results.len(), 1);
    }
}
