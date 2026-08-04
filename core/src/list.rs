// SPDX-License-Identifier: MIT

use anyhow::Result;
use rusqlite::{params, params_from_iter, types::Value, Connection};

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
    /// Full-text relevance (BM25), best first. Only meaningful with a query set;
    /// listings without one fall back to `SavedAt`.
    Relevance,
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
    /// Full-text query. When set, rows are filtered through the FTS index;
    /// `None` is a plain listing.
    pub query: Option<String>,
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
            query: None,
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
pub(crate) fn view_clause(view: View) -> &'static str {
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

/// Every sidebar count section — the view badges, the tag counts, and the rating
/// counts — gathered in a single call. See [`sidebar_counts`].
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SidebarCounts {
    /// Per-smart-view badge counts.
    pub views: ViewCounts,
    /// `(tag, count)` for every tag in the library, alphabetical (`list_tags`).
    pub tags: Vec<(String, u64)>,
    /// `(rating, count)` for every in-use star bucket, highest first
    /// (`list_ratings`).
    pub ratings: Vec<(u8, u64)>,
}

/// The active sidebar filters that scope the faceted counts. All four fields
/// compose as an intersection — the current search, the selected smart view, the
/// selected tag, and the selected rating (`View ∩ Tag ∩ Rating ∩ Search`). The UI
/// lets at most one of each be active at a time, and any may be unset (`view`
/// defaults to `All`, the unfiltered base; the rest to `None`).
///
/// Each count query applies every field of the scope *except its own axis* — a
/// facet never constrains itself, so its badges still show the alternatives you
/// could switch to (see [`count_where`]). This is standard faceted navigation:
/// selecting 5★ recounts the Library and Tags sections against the 5★ subset
/// while the Ratings section keeps showing every rating you could pick instead.
#[derive(Debug, Clone)]
pub struct CountScope {
    /// The selected smart view (`All` when none is chosen — the unfiltered base).
    /// Constrains the tag and rating counts; ignored by [`view_counts`] itself
    /// (which groups every view via `FILTER`).
    pub view: View,
    /// The selected tag, if one is active. Constrains the view and rating counts;
    /// ignored by [`list_tags`].
    pub tag: Option<String>,
    /// The selected rating, if one is active. Constrains the view and tag counts;
    /// ignored by [`list_ratings`].
    pub rating: Option<u8>,
    /// The active full-text query. Composes with every facet. `None` means no
    /// search; a present-but-unmatchable query scopes every count to zero,
    /// mirroring [`list_readings`].
    pub query: Option<String>,
}

impl Default for CountScope {
    fn default() -> Self {
        Self {
            view: View::All,
            tag: None,
            rating: None,
            query: None,
        }
    }
}

/// The facet axis a count query groups by — the one scope filter it must skip so
/// a section never constrains its own badges.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Facet {
    View,
    Tag,
    Rating,
}

/// A [`CountScope`]'s search resolved to its FTS state exactly once. Resolving
/// the `MATCH` string probes the FTS index (the phrase-vs-AND fallback in
/// [`crate::search::match_query`]), so [`sidebar_counts`] plans it a single time
/// and shares the result across all three sections.
#[derive(Debug, Clone)]
pub(crate) enum ResolvedSearch {
    /// The scope carried no query — no full-text predicate applies.
    Unfiltered,
    /// A query was present but tokenized/matched to nothing; every count is zero.
    Unmatchable,
    /// The query resolved to this FTS5 `MATCH` string.
    Fts(String),
}

impl ResolvedSearch {
    /// Resolve `query` against the FTS index once. `None` query is
    /// [`Unfiltered`](Self::Unfiltered); a present query becomes
    /// [`Fts`](Self::Fts) or, when it tokenizes/matches to nothing,
    /// [`Unmatchable`](Self::Unmatchable) — mirroring how `list_readings` treats
    /// an unmatchable search as "no results".
    pub(crate) fn resolve(conn: &Connection, query: Option<&str>) -> Result<Self> {
        Ok(match query {
            None => Self::Unfiltered,
            Some(q) => match crate::search::match_query(conn, q)? {
                None => Self::Unmatchable,
                Some(m) => Self::Fts(m),
            },
        })
    }
}

/// Build the shared `WHERE` fragment (and its positional bind values) for a
/// faceted count over `readings`, applying every [`CountScope`] filter except
/// the one for `axis`, plus the pre-resolved `search`. Columns are qualified
/// `readings.` so the fragment is safe to splice into `list_tags`'
/// `readings, json_each(...)` cross join.
///
/// Returns `None` when `search` is [`ResolvedSearch::Unmatchable`]: the caller
/// yields empty counts rather than a full listing, exactly as `list_readings`
/// treats an unmatchable search as "no results".
pub(crate) fn count_where(
    scope: &CountScope,
    axis: Facet,
    search: &ResolvedSearch,
) -> Option<(String, Vec<Value>)> {
    let mut clauses: Vec<String> = Vec::new();
    let mut vals: Vec<Value> = Vec::new();

    // The selected view constrains tag/rating counts; view_counts skips it and
    // partitions every view itself via FILTER.
    if axis != Facet::View {
        clauses.push(view_clause(scope.view).to_string());
    }

    if axis != Facet::Tag {
        if let Some(tag) = scope.tag.as_deref() {
            vals.push(Value::Text(tag.to_string()));
            clauses.push(format!(
                "EXISTS (SELECT 1 FROM json_each(readings.tags_json) WHERE value = ?{})",
                vals.len()
            ));
        }
    }

    if axis != Facet::Rating {
        if let Some(rating) = scope.rating {
            vals.push(Value::Integer(rating as i64));
            clauses.push(format!("readings.rating = ?{}", vals.len()));
        }
    }

    // A search composes with every facet; the caller resolved it once so counts
    // and results always agree. An unmatchable search means the whole count is
    // empty.
    match search {
        ResolvedSearch::Unmatchable => return None,
        ResolvedSearch::Fts(m) => {
            vals.push(Value::Text(m.clone()));
            clauses.push(format!(
                "readings.rowid IN \
                 (SELECT rowid FROM readings_fts WHERE readings_fts MATCH ?{})",
                vals.len()
            ));
        }
        ResolvedSearch::Unfiltered => {}
    }

    let where_sql = if clauses.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", clauses.join(" AND "))
    };
    Some((where_sql, vals))
}

/// Build the `COUNT(...) FILTER (WHERE …)` predicate for a *pinned* facet section
/// (Tags or Ratings). The presence set (which tiles show) is every tag / rating
/// in the library, regardless of view, so the badge must re-apply the *full*
/// faceted scope: the exact view clause, the pre-resolved `search`, and the
/// sibling facet. `sibling` is the cross facet that is neither the section's own
/// axis nor the view (`Facet::Rating` for the Tags section, `Facet::Tag` for the
/// Ratings section).
///
/// Returns the predicate SQL and pushes any bound values onto `vals`. An
/// [`ResolvedSearch::Unmatchable`] search contributes the constant-false
/// predicate `0`, so every tile reports 0 while staying pinned, rather than the
/// section emptying out.
pub(crate) fn pinned_count_filter(
    scope: &CountScope,
    sibling: Facet,
    search: &ResolvedSearch,
    vals: &mut Vec<Value>,
) -> String {
    // Start from the exact view clause: presence is broader than the view (e.g.
    // Unread pins every non-archived tag), so the badge itself must narrow back to
    // the actual view.
    let mut conds: Vec<String> = vec![view_clause(scope.view).to_string()];

    match search {
        ResolvedSearch::Unmatchable => conds.push("0".to_string()),
        ResolvedSearch::Fts(m) => {
            vals.push(Value::Text(m.clone()));
            conds.push(format!(
                "readings.rowid IN \
                 (SELECT rowid FROM readings_fts WHERE readings_fts MATCH ?{})",
                vals.len()
            ));
        }
        ResolvedSearch::Unfiltered => {}
    }

    match sibling {
        Facet::Rating => {
            if let Some(rating) = scope.rating {
                vals.push(Value::Integer(rating as i64));
                conds.push(format!("readings.rating = ?{}", vals.len()));
            }
        }
        Facet::Tag => {
            if let Some(tag) = scope.tag.as_deref() {
                vals.push(Value::Text(tag.to_string()));
                conds.push(format!(
                    "EXISTS (SELECT 1 FROM json_each(readings.tags_json) WHERE value = ?{})",
                    vals.len()
                ));
            }
        }
        Facet::View => unreachable!("view is the presence axis, never a sibling"),
    }

    conds.join(" AND ")
}

/// Count the readings in every smart view in a single pass over the table,
/// scoped by the active search and cross-facet selection (tag/rating) so the
/// Library badges track what a search or facet actually narrows to.
///
/// One grouped aggregate — not five `SELECT COUNT(*)`s, and emphatically not
/// `list_readings(..).len()` — so the cost is a single table scan regardless of
/// library size, with no rows materialized and no `LIMIT` to silently cap the
/// result. The `WHERE` restricts the population to the scope (minus the view
/// axis); each `FILTER` then partitions that population per view. `FILTER` needs
/// SQLite >= 3.30 (satisfied by the bundled build) and yields 0 rather than NULL
/// for an empty view.
pub fn view_counts(conn: &Connection, scope: &CountScope) -> Result<ViewCounts> {
    let search = ResolvedSearch::resolve(conn, scope.query.as_deref())?;
    view_counts_with(conn, scope, &search)
}

/// [`view_counts`] with the search pre-resolved, so [`sidebar_counts`] can share
/// one resolution across all three sections.
pub(crate) fn view_counts_with(
    conn: &Connection,
    scope: &CountScope,
    search: &ResolvedSearch,
) -> Result<ViewCounts> {
    let Some((where_sql, vals)) = count_where(scope, Facet::View, search) else {
        // A present-but-unmatchable search scopes every view to zero.
        return Ok(ViewCounts::default());
    };
    let sql = format!(
        "SELECT
             COUNT(*) FILTER (WHERE archived = 0),
             COUNT(*) FILTER (WHERE archived = 0 AND read_at IS NULL),
             COUNT(*) FILTER (WHERE archived = 0 AND read_at IS NOT NULL),
             COUNT(*) FILTER (WHERE archived = 1),
             COUNT(*) FILTER (WHERE favorite = 1)
         FROM readings {where_sql}"
    );
    conn.query_row(&sql, params_from_iter(vals), |row| {
        Ok(ViewCounts {
            all: row.get::<_, i64>(0)? as u64,
            unread: row.get::<_, i64>(1)? as u64,
            read: row.get::<_, i64>(2)? as u64,
            archive: row.get::<_, i64>(3)? as u64,
            favorites: row.get::<_, i64>(4)? as u64,
        })
    })
    .map_err(Into::into)
}

/// Compute all three sidebar sections — the view badges, the tag counts, and the
/// rating counts — in one call, resolving the search's FTS `MATCH` string a
/// single time and threading it through every section. The sidebar always
/// recounts all three together on a settled search or facet change, so gathering
/// them here plans the query once and returns them in a single pass.
pub fn sidebar_counts(conn: &Connection, scope: &CountScope) -> Result<SidebarCounts> {
    let search = ResolvedSearch::resolve(conn, scope.query.as_deref())?;
    Ok(SidebarCounts {
        views: view_counts_with(conn, scope, &search)?,
        tags: crate::tags::list_tags_with(conn, scope, &search)?,
        ratings: crate::rating::list_ratings_with(conn, scope, &search)?,
    })
}

/// List readings from the index according to `opts`.
///
/// When `opts.query` is set, rows are filtered through the full-text index
/// (composing with the view/tag/rating/date filters) and rank by BM25 under
/// `SortField::Relevance`. Otherwise this is a plain listing over the `readings`
/// table.
pub fn list_readings(conn: &Connection, opts: &ListOptions) -> Result<Vec<ReadingRow>> {
    // A present query means "search" — even whitespace/punctuation-only input,
    // which matches nothing rather than falling back to the full listing.
    if let Some(query) = opts.query.as_deref() {
        return match crate::search::match_query(conn, query)? {
            Some(match_query) => list_readings_fts(conn, opts, &match_query),
            None => Ok(Vec::new()),
        };
    }

    let view_clause = view_clause(opts.view);

    // Direction applies to the chosen field; a final `id DESC` makes the order
    // total so pagination is stable when the primary key ties. For `read_at`,
    // the leading `(read_at IS NULL)` term forces unread rows last in both
    // directions (it always sorts ascending: 0 = has-date before 1 = null).
    let dir = if opts.ascending { "ASC" } else { "DESC" };
    let order = match opts.sort {
        // Relevance needs the FTS table; off-search it's meaningless, so fall
        // back to the default field.
        SortField::SavedAt | SortField::Relevance => format!("saved_at {dir}, id DESC"),
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

/// Full-text variant of [`list_readings`]: filter rows through the FTS index
/// with `match_query` and rank by BM25 (`SortField::Relevance`) or the requested
/// field — all while honouring the view/tag/rating/date filters and pagination.
fn list_readings_fts(
    conn: &Connection,
    opts: &ListOptions,
    match_query: &str,
) -> Result<Vec<ReadingRow>> {
    let view_clause = view_clause(opts.view);
    let dir = if opts.ascending { "ASC" } else { "DESC" };
    // bm25() scores better matches lower, so plain ascending order is best-first.
    let order = match opts.sort {
        SortField::Relevance => "bm25(readings_fts), r.id DESC".to_string(),
        SortField::SavedAt => format!("r.saved_at {dir}, r.id DESC"),
        SortField::ReadAt => format!("(r.read_at IS NULL), r.read_at {dir}, r.id DESC"),
        SortField::Rating => format!("r.rating {dir}, r.id DESC"),
        SortField::WordCount => format!("(r.word_count IS NULL), r.word_count {dir}, r.id DESC"),
    };

    // The view/tag/rating columns live only on `readings`, so they're
    // unambiguous unqualified; `title`/`body_text` exist on both tables, hence
    // the `r.` on the selected columns.
    let sql = format!(
        "SELECT r.id, r.title, r.url, r.canonical_url, r.author, r.site, r.saved_at,
                (r.read_at IS NOT NULL), r.archived, r.favorite, r.excerpt, r.word_count,
                r.lang, r.tags_json, r.rating, r.read_at
         FROM readings_fts
         JOIN readings r ON r.rowid = readings_fts.rowid
         WHERE readings_fts MATCH ?7
           AND {view_clause}
           AND (?3 = '' OR EXISTS (SELECT 1 FROM json_each(r.tags_json) WHERE value = ?3))
           AND (?4 = '' OR r.saved_at >= ?4)
           AND (?5 = '' OR r.saved_at <= ?5)
           AND (?6 = 0 OR r.rating = ?6)
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
            rating_val,
            match_query
        ],
        parse_row,
    )?;

    rows.map(|r| r.map_err(Into::into)).collect()
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
    fn list_query_filters_by_fulltext() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://a.com", "Rust async"),
            "learning rust async".into(),
        )
        .unwrap();
        write_reading(
            &lib,
            meta(&new_id(), "https://b.com", "Cooking"),
            "pasta recipe".into(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let rows = list_readings(
            &conn,
            &ListOptions {
                query: Some("rust".into()),
                ..Default::default()
            },
        )
        .unwrap();

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].title, "Rust async");
    }

    #[test]
    fn search_finds_a_reading_sharing_a_bucket_with_others() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        // Two readings whose ids share one fan-out bucket, with distinct content.
        let a = "ab00000000000000000000000000000000000000000000000000000000000001";
        let b = "ab00000000000000000000000000000000000000000000000000000000000002";
        write_reading(
            &lib,
            meta(a, "https://a.com", "Rust async"),
            "learning rust async".into(),
        )
        .unwrap();
        write_reading(
            &lib,
            meta(b, "https://b.com", "Cooking"),
            "a pasta recipe".into(),
        )
        .unwrap();
        assert_eq!(
            lib.reading_dir(a).parent().unwrap(),
            lib.reading_dir(b).parent().unwrap(),
            "the two readings must share one bucket"
        );
        rebuild(&conn, &lib).unwrap();

        // Search resolves to exactly the matching bucket sibling.
        let rows = list_readings(
            &conn,
            &ListOptions {
                query: Some("pasta".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(rows.len(), 1, "only one reading matches");
        assert_eq!(rows[0].id, b);
        assert_eq!(rows[0].title, "Cooking");
    }

    #[test]
    fn list_blank_query_matches_nothing() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        write_reading(&lib, meta(&new_id(), "https://a.com", "A"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // A present-but-untokenizable query is still a search, so it returns no
        // rows rather than falling back to the full listing.
        let rows = list_readings(
            &conn,
            &ListOptions {
                query: Some("   ".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(rows.is_empty());
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

        let counts = view_counts(&conn, &CountScope::default()).unwrap();
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
        assert_eq!(
            view_counts(&conn, &CountScope::default()).unwrap(),
            ViewCounts::default()
        );
    }

    /// Build the four-reading faceting corpus shared by the scoped view-count
    /// tests. "space" appears in X, Y, W but not Z; ratings and archived state
    /// are spread so search/tag/rating facets each narrow differently.
    fn faceting_corpus(lib: &LibraryRoot, conn: &Connection) {
        // X: active, unread, tag "sci", rating 5.
        let mut x = meta(&new_id(), "https://a.com", "X");
        x.tags = vec!["sci".into()];
        x.rating = 5;
        write_reading(lib, x, "space opera".into()).unwrap();
        // Y: active, read, tag "sci", rating 3.
        let mut y = meta(&new_id(), "https://b.com", "Y");
        y.tags = vec!["sci".into()];
        y.rating = 3;
        y.read_at = Some("2026-06-13T16:00:00.000Z".into());
        write_reading(lib, y, "space station".into()).unwrap();
        // Z: active, unread, tag "cook", rating 2 — never matches "space".
        let mut z = meta(&new_id(), "https://c.com", "Z");
        z.tags = vec!["cook".into()];
        z.rating = 2;
        write_reading(lib, z, "pasta recipe".into()).unwrap();
        // W: archived, tag "sci", rating 5.
        let mut w = meta(&new_id(), "https://d.com", "W");
        w.tags = vec!["sci".into()];
        w.rating = 5;
        w.archived = true;
        write_reading(lib, w, "space archived".into()).unwrap();
        rebuild(conn, lib).unwrap();
    }

    #[test]
    fn view_counts_scoped_by_search() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // "space" matches X (active unread), Y (active read), W (archived); Z is out.
        let counts = view_counts(
            &conn,
            &CountScope {
                query: Some("space".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(counts.all, 2, "X, Y (W archived)");
        assert_eq!(counts.unread, 1, "X");
        assert_eq!(counts.read, 1, "Y");
        assert_eq!(counts.archive, 1, "W");
        assert_eq!(counts.favorites, 0);
    }

    #[test]
    fn view_counts_scoped_by_rating_facet_composes_with_search() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // Selecting 5★ narrows the "space" set to X (active) and W (archived);
        // Y is rating 3 and drops out. The view axis is never applied to itself.
        let counts = view_counts(
            &conn,
            &CountScope {
                query: Some("space".into()),
                rating: Some(5),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(counts.all, 1, "X only (Y is 3★, W archived)");
        assert_eq!(counts.unread, 1, "X");
        assert_eq!(counts.read, 0, "Y dropped by the 5★ facet");
        assert_eq!(counts.archive, 1, "W");
    }

    #[test]
    fn view_counts_scoped_by_tag_facet() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // The "cook" tag matches only Z (active, unread) — no search.
        let counts = view_counts(
            &conn,
            &CountScope {
                tag: Some("cook".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(counts.all, 1, "Z");
        assert_eq!(counts.unread, 1, "Z");
        assert_eq!(counts.read, 0);
        assert_eq!(counts.archive, 0);
    }

    #[test]
    fn view_counts_unmatchable_search_is_all_zero() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // A real word that matches nothing (Some(match) but no rows) and a
        // blank/punctuation query (early None) both scope every view to zero.
        for q in ["zzzznomatch", "   "] {
            let counts = view_counts(
                &conn,
                &CountScope {
                    query: Some(q.into()),
                    ..Default::default()
                },
            )
            .unwrap();
            assert_eq!(counts, ViewCounts::default(), "query {q:?} matches nothing");
        }
    }

    #[test]
    fn sidebar_counts_matches_the_individual_sections() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // The batched call resolves the search once, but every section must return
        // exactly what its standalone function does — across plain, searched,
        // faceted, view-scoped, and unmatchable-search scopes. This ties the
        // batched path to the individual functions' behavior tests.
        let scopes = [
            CountScope::default(),
            CountScope {
                query: Some("space".into()),
                ..Default::default()
            },
            CountScope {
                query: Some("space".into()),
                rating: Some(5),
                ..Default::default()
            },
            CountScope {
                view: View::Unread,
                tag: Some("sci".into()),
                ..Default::default()
            },
            CountScope {
                query: Some("zzzznomatch".into()),
                ..Default::default()
            },
        ];
        for scope in scopes {
            let batched = sidebar_counts(&conn, &scope).unwrap();
            assert_eq!(
                batched.views,
                view_counts(&conn, &scope).unwrap(),
                "views for {scope:?}"
            );
            assert_eq!(
                batched.tags,
                crate::list_tags(&conn, &scope).unwrap(),
                "tags for {scope:?}"
            );
            assert_eq!(
                batched.ratings,
                crate::list_ratings(&conn, &scope).unwrap(),
                "ratings for {scope:?}"
            );
        }
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
