// SPDX-License-Identifier: MIT

//! Star ratings (1–5, or 0 for unrated).
//!
//! A rating lives in the article's frontmatter (`rating:`) as the source of
//! truth and is mirrored into the `rating` index column. `list_ratings`
//! returns the per-value counts that drive the sidebar's Ratings filter.

use anyhow::{bail, Result};
use rusqlite::Connection;

use crate::{status::update_flag, LibraryRoot};

/// Set a reading's star rating. `rating` must be 0–5, where 0 clears it.
pub fn set_rating(library: &LibraryRoot, conn: &Connection, id: &str, rating: u8) -> Result<()> {
    if rating > 5 {
        bail!("rating must be 0..=5, got {rating}");
    }
    update_flag(library, conn, id, |m| m.rating = rating)
}

/// Count of non-archived readings at each star value 1–5 (values with no
/// readings are omitted), ordered highest rating first. Mirrors `list_tags`.
pub fn list_ratings(conn: &Connection) -> Result<Vec<(u8, u64)>> {
    let mut stmt = conn.prepare(
        "SELECT rating, COUNT(*) AS cnt
         FROM readings
         WHERE archived = 0 AND rating BETWEEN 1 AND 5
         GROUP BY rating
         ORDER BY rating DESC",
    )?;

    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, i64>(0)? as u8, row.get::<_, u64>(1)?))
    })?;

    rows.map(|r| r.map_err(Into::into)).collect()
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

    fn rating_of(conn: &Connection, id: &str) -> i64 {
        conn.query_row(
            "SELECT rating FROM readings WHERE id = ?1",
            rusqlite::params![id],
            |r| r.get(0),
        )
        .unwrap()
    }

    #[test]
    fn set_rating_updates_frontmatter_and_index() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        set_rating(&lib, &conn, &id, 4).unwrap();

        let content = fs::read_to_string(lib.article_path(&id)).unwrap();
        assert!(content.contains("rating: 4"));
        assert_eq!(rating_of(&conn, &id), 4);
    }

    #[test]
    fn set_rating_zero_clears() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        set_rating(&lib, &conn, &id, 3).unwrap();
        set_rating(&lib, &conn, &id, 0).unwrap();
        assert_eq!(rating_of(&conn, &id), 0);
    }

    #[test]
    fn set_rating_rejects_out_of_range() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();
        let id = new_id();
        write_reading(&lib, meta(&id), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        assert!(set_rating(&lib, &conn, &id, 6).is_err());
    }

    #[test]
    fn list_ratings_counts_and_excludes_archived() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let conn = open(&dir.path().join("index.db")).unwrap();

        let a = new_id();
        let b = new_id();
        let c = new_id();
        write_reading(&lib, meta(&a), "a".into()).unwrap();
        write_reading(&lib, meta(&b), "b".into()).unwrap();
        write_reading(&lib, meta(&c), "c".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        set_rating(&lib, &conn, &a, 5).unwrap();
        set_rating(&lib, &conn, &b, 5).unwrap();
        set_rating(&lib, &conn, &c, 3).unwrap();

        let ratings = list_ratings(&conn).unwrap();
        assert_eq!(ratings, vec![(5, 2), (3, 1)]);
    }
}
