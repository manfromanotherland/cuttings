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
    /// Non-archived readings that have been read.
    Read,
    /// Archived readings.
    Archive,
    /// Readings marked as favorite (regardless of archived state).
    Favorites,
}

/// Field to sort a listing by. Direction is controlled separately by
/// [`ListOptions::ascending`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SortField {
    /// When the reading was saved (default).
    #[default]
    SavedAt,
    /// When the reading was last marked read. Unread rows (`read_at IS NULL`)
    /// always sort last, regardless of direction.
    ReadAt,
    /// Star rating (0–5).
    Rating,
    /// Estimated time to read, ranked by word count. Rows without a known
    /// word count (`word_count IS NULL`) always sort last, regardless of
    /// direction.
    WordCount,
}

/// Options for `list_readings`.
#[derive(Debug, Clone)]
pub struct ListOptions {
    pub view: View,
    pub sort: SortField,
    /// Sort ascending when `true`, descending when `false`. Descending is the
    /// natural default for every field (newest / highest / most-recently-read
    /// first).
    pub ascending: bool,
    /// Restrict to readings that carry this tag (exact match).
    pub tag: Option<String>,
    /// Restrict to readings with this exact star rating, 1–5. `None` = no filter.
    pub rating: Option<u8>,
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
            sort: SortField::SavedAt,
            ascending: false,
            tag: None,
            rating: None,
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
    /// `true` when the reading has been read — derived from `read_at` being set.
    pub read: bool,
    /// UTC ISO-8601 timestamp of the most recent time marked read, or `None`.
    pub read_at: Option<String>,
    pub archived: bool,
    pub favorite: bool,
    pub rating: u8,
    pub excerpt: Option<String>,
    pub word_count: Option<u32>,
    pub lang: Option<String>,
    pub tags: Vec<String>,
}

/// The SQL predicate that selects a smart view. Single source of truth shared
/// by [`list_readings`] and [`view_counts`] so a view's count can never
/// disagree with the list it produces.
fn view_clause(view: View) -> &'static str {
    match view {
        View::All => "archived = 0",
        View::Unread => "archived = 0 AND read_at IS NULL",
        View::Read => "archived = 0 AND read_at IS NOT NULL",
        View::Archive => "archived = 1",
        View::Favorites => "favorite = 1",
    }
}

/// The number of readings in each smart view.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ViewCounts {
    pub all: u64,
    pub unread: u64,
    pub read: u64,
    pub archive: u64,
    pub favorites: u64,
}

/// Count the readings in every smart view in a single pass over the table.
///
/// One grouped aggregate — not five `SELECT COUNT(*)`s, and emphatically not
/// `list_readings(..).len()` — so the cost is a single table scan regardless of
/// library size, with no rows materialized and no `LIMIT` to silently cap the
/// result. The `FILTER` clause needs SQLite >= 3.30 (satisfied by the bundled
/// build) and yields 0 rather than NULL for an empty view.
pub fn view_counts(conn: &Connection) -> Result<ViewCounts> {
    conn.query_row(
        "SELECT
             COUNT(*) FILTER (WHERE archived = 0),
             COUNT(*) FILTER (WHERE archived = 0 AND read_at IS NULL),
             COUNT(*) FILTER (WHERE archived = 0 AND read_at IS NOT NULL),
             COUNT(*) FILTER (WHERE archived = 1),
             COUNT(*) FILTER (WHERE favorite = 1)
         FROM readings",
        [],
        |row| {
            Ok(ViewCounts {
                all: row.get::<_, i64>(0)? as u64,
                unread: row.get::<_, i64>(1)? as u64,
                read: row.get::<_, i64>(2)? as u64,
                archive: row.get::<_, i64>(3)? as u64,
                favorites: row.get::<_, i64>(4)? as u64,
            })
        },
    )
    .map_err(Into::into)
}

/// List readings from the index according to `opts`.
pub fn list_readings(conn: &Connection, opts: &ListOptions) -> Result<Vec<ReadingRow>> {
    let view_clause = view_clause(opts.view);

    // Direction applies to the chosen field; a final `id DESC` makes the order
    // total so pagination is stable when the primary key ties. For `read_at`,
    // the leading `(read_at IS NULL)` term forces unread rows last in both
    // directions (it always sorts ascending: 0 = has-date before 1 = null).
    let dir = if opts.ascending { "ASC" } else { "DESC" };
    let order = match opts.sort {
        SortField::SavedAt => format!("saved_at {dir}, id DESC"),
        SortField::ReadAt => format!("(read_at IS NULL), read_at {dir}, id DESC"),
        SortField::Rating => format!("rating {dir}, id DESC"),
        SortField::WordCount => format!("(word_count IS NULL), word_count {dir}, id DESC"),
    };

    // Optional filters use sentinel values (empty string / 0) so the SQL is
    // always static with exactly 6 bound parameters — no dynamic param count.
    let sql = format!(
        "SELECT id, title, url, canonical_url, author, site, saved_at,
                (read_at IS NOT NULL), archived, favorite, excerpt, word_count, lang, tags_json,
                rating, read_at
         FROM readings
         WHERE {view_clause}
           AND (?3 = '' OR EXISTS (SELECT 1 FROM json_each(tags_json) WHERE value = ?3))
           AND (?4 = '' OR saved_at >= ?4)
           AND (?5 = '' OR saved_at <= ?5)
           AND (?6 = 0 OR rating = ?6)
         ORDER BY {order}
         LIMIT ?1 OFFSET ?2"
    );

    let mut stmt = conn.prepare(&sql)?;

    let tag_val = opts.tag.as_deref().unwrap_or("");
    let since_val = opts.since.as_deref().unwrap_or("");
    let until_val = opts.until.as_deref().unwrap_or("");
    let rating_val = opts.rating.unwrap_or(0) as i64;

    let rows = stmt.query_map(
        params![
            opts.limit as i64,
            opts.offset as i64,
            tag_val,
            since_val,
            until_val,
            rating_val
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
                (read_at IS NOT NULL), archived, favorite, excerpt, word_count, lang, tags_json,
                rating, read_at, body_text
         FROM readings WHERE id = ?1",
    )?;

    let mut rows = stmt.query_map(params![id], |row| {
        let row_data = parse_row(row)?;
        let body: String = row.get(16)?;
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
        rating: row.get::<_, i32>(14)? as u8,
        read_at: row.get(15)?,
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
        read_meta.read_at = Some("2026-06-13T16:00:00.000Z".to_string());
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
    fn list_read_returns_read_non_archived() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://a.com", "Unread"),
            "body".into(),
        )
        .unwrap();

        let mut read_meta = meta(&new_id(), "https://b.com", "Read");
        read_meta.read_at = Some("2026-06-13T16:00:00.000Z".to_string());
        write_reading(&lib, read_meta, "body".into()).unwrap();

        // A read but archived item must not appear under the Read view.
        let mut read_archived = meta(&new_id(), "https://c.com", "ReadArchived");
        read_archived.read_at = Some("2026-06-13T16:00:00.000Z".to_string());
        read_archived.archived = true;
        write_reading(&lib, read_archived, "body".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::Read,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Read");
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
    fn view_counts_match_list_lengths() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        // A: active, unread
        write_reading(&lib, meta(&new_id(), "https://a.com", "A"), "b".into()).unwrap();
        // B: active, read
        let mut b = meta(&new_id(), "https://b.com", "B");
        b.read_at = Some("2026-06-13T16:00:00.000Z".into());
        write_reading(&lib, b, "b".into()).unwrap();
        // C: archived
        let mut c = meta(&new_id(), "https://c.com", "C");
        c.archived = true;
        write_reading(&lib, c, "b".into()).unwrap();
        // D: active, unread, favorite
        let mut d = meta(&new_id(), "https://d.com", "D");
        d.favorite = true;
        write_reading(&lib, d, "b".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let counts = view_counts(&conn).unwrap();
        assert_eq!(counts.all, 3); // A, B, D (C is archived)
        assert_eq!(counts.unread, 2); // A, D
        assert_eq!(counts.read, 1); // B
        assert_eq!(counts.archive, 1); // C
        assert_eq!(counts.favorites, 1); // D

        // Each grouped count must equal the length of the corresponding list —
        // the one-pass query agrees with the old materialize-and-count.
        let len = |view| {
            list_readings(
                &conn,
                &ListOptions {
                    view,
                    limit: 9999,
                    ..Default::default()
                },
            )
            .unwrap()
            .len() as u64
        };
        assert_eq!(counts.all, len(View::All));
        assert_eq!(counts.unread, len(View::Unread));
        assert_eq!(counts.read, len(View::Read));
        assert_eq!(counts.archive, len(View::Archive));
        assert_eq!(counts.favorites, len(View::Favorites));
    }

    #[test]
    fn view_counts_zero_on_empty_library() {
        let (_dir, conn) = setup();
        // FILTER yields 0, not NULL, so every field is a clean zero.
        assert_eq!(view_counts(&conn).unwrap(), ViewCounts::default());
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
    fn list_filter_by_rating() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut four = meta(&new_id(), "https://a.com", "Four");
        four.rating = 4;
        write_reading(&lib, four, "body".into()).unwrap();

        let mut five = meta(&new_id(), "https://b.com", "Five");
        five.rating = 5;
        write_reading(&lib, five, "body".into()).unwrap();

        write_reading(
            &lib,
            meta(&new_id(), "https://c.com", "Unrated"),
            "body".into(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                rating: Some(4),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Four");
        assert_eq!(rows[0].rating, 4);
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
    fn sort_by_read_at_puts_unread_last_in_both_directions() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com", "A");
        a.read_at = Some("2026-01-02T00:00:00.000Z".into());
        write_reading(&lib, a, "body".into()).unwrap();

        let mut b = meta(&new_id(), "https://b.com", "B");
        b.read_at = Some("2026-01-03T00:00:00.000Z".into());
        write_reading(&lib, b, "body".into()).unwrap();

        write_reading(
            &lib,
            meta(&new_id(), "https://c.com", "C-unread"),
            "body".into(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let titles = |ascending: bool| {
            list_readings(
                &conn,
                &ListOptions {
                    view: View::All,
                    sort: SortField::ReadAt,
                    ascending,
                    ..Default::default()
                },
            )
            .unwrap()
            .into_iter()
            .map(|r| r.title)
            .collect::<Vec<_>>()
        };

        // Descending: most recently read first; unread last.
        assert_eq!(titles(false), ["B", "A", "C-unread"]);
        // Ascending: earliest read first; unread STILL last.
        assert_eq!(titles(true), ["A", "B", "C-unread"]);
    }

    #[test]
    fn sort_by_rating_orders_by_stars() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut five = meta(&new_id(), "https://a.com", "Five");
        five.rating = 5;
        write_reading(&lib, five, "body".into()).unwrap();

        let mut three = meta(&new_id(), "https://b.com", "Three");
        three.rating = 3;
        write_reading(&lib, three, "body".into()).unwrap();

        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                view: View::All,
                sort: SortField::Rating,
                ascending: false,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            rows.iter().map(|r| r.title.as_str()).collect::<Vec<_>>(),
            ["Five", "Three"]
        );
    }

    #[test]
    fn sort_by_word_count_puts_unknown_last_in_both_directions() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut long = meta(&new_id(), "https://a.com", "Long");
        long.word_count = Some(5000);
        write_reading(&lib, long, "body".into()).unwrap();

        let mut short = meta(&new_id(), "https://b.com", "Short");
        short.word_count = Some(200);
        write_reading(&lib, short, "body".into()).unwrap();

        // No word_count set -> ranks last regardless of direction.
        write_reading(
            &lib,
            meta(&new_id(), "https://c.com", "Unknown"),
            "body".into(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let titles = |ascending: bool| {
            list_readings(
                &conn,
                &ListOptions {
                    view: View::All,
                    sort: SortField::WordCount,
                    ascending,
                    ..Default::default()
                },
            )
            .unwrap()
            .into_iter()
            .map(|r| r.title)
            .collect::<Vec<_>>()
        };

        // Descending: longest read first; unknown last.
        assert_eq!(titles(false), ["Long", "Short", "Unknown"]);
        // Ascending: shortest read first; unknown STILL last.
        assert_eq!(titles(true), ["Short", "Long", "Unknown"]);
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
