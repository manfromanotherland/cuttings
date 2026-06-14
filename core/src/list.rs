// SPDX-License-Identifier: MIT

use anyhow::Result;
use rusqlite::{params, Connection};

/// Smart-view filter applied when listing readings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    /// All non-archived readings.
    All,
    /// Non-archived readings that have not been read.
    Unread,
    /// Archived readings.
    Archive,
    /// Readings marked as favorite (regardless of archived state).
    Favorites,
}

/// Sort order for listing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortOrder {
    /// Newest `saved_at` first (default).
    NewestFirst,
    OldestFirst,
}

impl Default for SortOrder {
    fn default() -> Self {
        Self::NewestFirst
    }
}

/// Options for `list_readings`.
#[derive(Debug, Clone)]
pub struct ListOptions {
    pub view: View,
    pub sort: SortOrder,
    /// Restrict to readings that carry this tag (exact match).
    pub tag: Option<String>,
    /// ISO-8601 lower bound on `saved_at` (inclusive).
    pub since: Option<String>,
    /// ISO-8601 upper bound on `saved_at` (inclusive).
    pub until: Option<String>,
    pub limit: usize,
    pub offset: usize,
}

impl Default for ListOptions {
    fn default() -> Self {
        Self {
            view: View::All,
            sort: SortOrder::NewestFirst,
            tag: None,
            since: None,
            until: None,
            limit: 50,
            offset: 0,
        }
    }
}

/// Lightweight row returned by `list_readings` — no body text.
#[derive(Debug, Clone, PartialEq)]
pub struct ReadingRow {
    pub id: String,
    pub title: String,
    pub url: String,
    pub canonical_url: String,
    pub author: Option<String>,
    pub site: Option<String>,
    pub saved_at: String,
    pub read: bool,
    pub archived: bool,
    pub favorite: bool,
    pub excerpt: Option<String>,
    pub word_count: Option<u32>,
    pub lang: Option<String>,
    pub tags: Vec<String>,
}

/// List readings from the index according to `opts`.
pub fn list_readings(conn: &Connection, opts: &ListOptions) -> Result<Vec<ReadingRow>> {
    let view_clause = match opts.view {
        View::All => "archived = 0",
        View::Unread => "archived = 0 AND read = 0",
        View::Archive => "archived = 1",
        View::Favorites => "favorite = 1",
    };

    let order = match opts.sort {
        SortOrder::NewestFirst => "saved_at DESC",
        SortOrder::OldestFirst => "saved_at ASC",
    };

    // Optional filters use empty-string sentinels so the SQL is always static
    // with exactly 5 bound parameters — no dynamic param count issues.
    let sql = format!(
        "SELECT id, title, url, canonical_url, author, site, saved_at,
                read, archived, favorite, excerpt, word_count, lang, tags_json
         FROM readings
         WHERE {view_clause}
           AND (?3 = '' OR EXISTS (SELECT 1 FROM json_each(tags_json) WHERE value = ?3))
           AND (?4 = '' OR saved_at >= ?4)
           AND (?5 = '' OR saved_at <= ?5)
         ORDER BY {order}
         LIMIT ?1 OFFSET ?2"
    );

    let mut stmt = conn.prepare(&sql)?;

    let tag_val = opts.tag.as_deref().unwrap_or("");
    let since_val = opts.since.as_deref().unwrap_or("");
    let until_val = opts.until.as_deref().unwrap_or("");

    let rows = stmt.query_map(
        params![
            opts.limit as i64,
            opts.offset as i64,
            tag_val,
            since_val,
            until_val
        ],
        parse_row,
    )?;

    rows.map(|r| r.map_err(Into::into)).collect()
}

/// Fetch the full content (metadata + body) of a single reading by id.
///
/// Returns `None` if the id is not in the index.
pub fn get_reading(conn: &Connection, id: &str) -> Result<Option<(ReadingRow, String)>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, url, canonical_url, author, site, saved_at,
                read, archived, favorite, excerpt, word_count, lang, tags_json,
                body_text
         FROM readings WHERE id = ?1",
    )?;

    let mut rows = stmt.query_map(params![id], |row| {
        let row_data = parse_row(row)?;
        let body: String = row.get(14)?;
        Ok((row_data, body))
    })?;

    match rows.next() {
        None => Ok(None),
        Some(r) => Ok(Some(r?)),
    }
}

fn parse_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ReadingRow> {
    let tags_json: String = row.get(13)?;
    let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
    Ok(ReadingRow {
        id: row.get(0)?,
        title: row.get(1)?,
        url: row.get(2)?,
        canonical_url: row.get(3)?,
        author: row.get(4)?,
        site: row.get(5)?,
        saved_at: row.get(6)?,
        read: row.get::<_, i32>(7)? != 0,
        archived: row.get::<_, i32>(8)? != 0,
        favorite: row.get::<_, i32>(9)? != 0,
        excerpt: row.get(10)?,
        word_count: row.get(11)?,
        lang: row.get(12)?,
        tags,
    })
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
    fn list_all_returns_non_archived() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(&lib, meta(&new_id(), "https://a.com", "A"), "body".into()).unwrap();
        let mut m = meta(&new_id(), "https://b.com", "B");
        m.archived = true;
        write_reading(&lib, m, "body".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "A");
    }

    #[test]
    fn list_unread_excludes_read_and_archived() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://a.com", "Unread"),
            "body".into(),
        )
        .unwrap();

        let mut read_meta = meta(&new_id(), "https://b.com", "Read");
        read_meta.read = true;
        write_reading(&lib, read_meta, "body".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::Unread,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Unread");
    }

    #[test]
    fn list_archive_returns_only_archived() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://a.com", "Active"),
            "body".into(),
        )
        .unwrap();
        let mut m = meta(&new_id(), "https://b.com", "Archived");
        m.archived = true;
        write_reading(&lib, m, "body".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::Archive,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Archived");
    }

    #[test]
    fn list_favorites() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut m = meta(&new_id(), "https://a.com", "Fav");
        m.favorite = true;
        write_reading(&lib, m, "body".into()).unwrap();
        write_reading(
            &lib,
            meta(&new_id(), "https://b.com", "Normal"),
            "body".into(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::Favorites,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Fav");
    }

    #[test]
    fn list_filter_by_tag() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut m = meta(&new_id(), "https://a.com", "Tagged");
        m.tags = vec!["rust".into()];
        write_reading(&lib, m, "body".into()).unwrap();
        write_reading(
            &lib,
            meta(&new_id(), "https://b.com", "Untagged"),
            "body".into(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                tag: Some("rust".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Tagged");
    }

    #[test]
    fn list_limit_and_offset() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        for i in 0..5u32 {
            write_reading(
                &lib,
                meta(
                    &new_id(),
                    &format!("https://example.com/{i}"),
                    &format!("Article {i}"),
                ),
                "body".into(),
            )
            .unwrap();
        }
        rebuild(&conn, &lib).unwrap();

        let page1 = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                limit: 3,
                offset: 0,
                ..Default::default()
            },
        )
        .unwrap();
        let page2 = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                limit: 3,
                offset: 3,
                ..Default::default()
            },
        )
        .unwrap();

        assert_eq!(page1.len(), 3);
        assert_eq!(page2.len(), 2);
        // No overlap.
        let ids1: Vec<_> = page1.iter().map(|r| &r.id).collect();
        let ids2: Vec<_> = page2.iter().map(|r| &r.id).collect();
        assert!(ids1.iter().all(|id| !ids2.contains(id)));
    }

    #[test]
    fn get_reading_returns_body() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "My Article"),
            "hello world".into(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let result = get_reading(&conn, &id).unwrap();
        assert!(result.is_some());
        let (row, body) = result.unwrap();
        assert_eq!(row.title, "My Article");
        assert!(body.contains("hello world"));
    }

    #[test]
    fn get_reading_returns_none_for_missing_id() {
        let (_dir, conn) = setup();
        let result = get_reading(&conn, "nonexistent").unwrap();
        assert!(result.is_none());
    }
}
