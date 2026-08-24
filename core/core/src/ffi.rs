// SPDX-License-Identifier: MIT

//! UniFFI-exported interface for the macOS SwiftUI client.
//!
//! `Database` is the central object: open it with a SQLite path, then call
//! `rebuild` on first launch and `sync` on subsequent launches (or whenever
//! the library folder changes). All mutation helpers take a `library_path`
//! so the object stays path-agnostic and the caller controls where files live.

use std::{
    path::Path,
    sync::{Arc, Mutex},
};

use crate::{
    list::{CountScope, ListOptions, SortField, View},
    scanner::ScannedReading,
    LibraryRoot, ReadingKind, SaveDisposition, SaveOutcome,
};

// ── Error ────────────────────────────────────────────────────────────────────

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    #[error("{0}")]
    Error(String),
}

fn e(err: impl std::fmt::Display) -> CoreError {
    CoreError::Error(err.to_string())
}

// ── Record types (plain data, no methods) ────────────────────────────────────

#[derive(uniffi::Record)]
pub struct FfiReadingRow {
    pub id: String,
    pub title: String,
    pub kind: FfiReadingKind,
    pub url: String,
    pub media_url: Option<String>,
    pub preview_asset: Option<String>,
    pub canonical_url: String,
    pub author: Option<String>,
    pub site: Option<String>,
    pub saved_at: String,
    pub read: bool,
    pub archived: bool,
    pub favorite: bool,
    pub rating: u8,
    pub excerpt: Option<String>,
    pub word_count: Option<u32>,
    pub lang: Option<String>,
    pub tags: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct FfiTagCount {
    pub tag: String,
    pub count: u64,
}

#[derive(uniffi::Record)]
pub struct FfiRatingCount {
    pub rating: u8,
    pub count: u64,
}

#[derive(uniffi::Record)]
pub struct FfiViewCounts {
    pub all: u64,
    pub unread: u64,
    pub read: u64,
    pub archive: u64,
    pub favorites: u64,
}

/// Every sidebar count section in one payload: the view badges, the tag counts,
/// and the rating counts. Returned by [`Database::sidebar_counts`].
#[derive(uniffi::Record)]
pub struct FfiSidebarCounts {
    pub views: FfiViewCounts,
    pub tags: Vec<FfiTagCount>,
    pub ratings: Vec<FfiRatingCount>,
}

#[derive(uniffi::Record)]
pub struct FfiHighlight {
    pub id: String,
    pub text: String,
}

/// Result of importing content through the native app. Exact duplicates are a
/// successful, structured outcome so Swift can show friendly feedback without
/// parsing an error string.
#[derive(uniffi::Record)]
pub struct FfiImportResult {
    pub disposition: FfiImportDisposition,
    pub id: String,
    pub path: String,
}

#[derive(uniffi::Enum)]
pub enum FfiImportDisposition {
    Saved,
    Upgraded,
    Duplicate,
}

#[derive(uniffi::Enum)]
pub enum FfiReadingKind {
    Article,
    Image,
    Video,
    Quote,
}

#[derive(uniffi::Enum)]
pub enum FfiView {
    All,
    Unread,
    Read,
    Archive,
    Favorites,
}

#[derive(uniffi::Enum)]
pub enum FfiSortField {
    SavedAt,
    ReadAt,
    Rating,
    WordCount,
    Relevance,
}

#[derive(uniffi::Record)]
pub struct FfiListOptions {
    pub view: FfiView,
    pub sort: FfiSortField,
    /// Ascending when `true`, descending when `false` (the default direction).
    pub ascending: bool,
    pub tag: Option<String>,
    pub rating: Option<u8>,
    pub kind: Option<FfiReadingKind>,
    pub since: Option<String>,
    pub until: Option<String>,
    pub query: Option<String>,
    pub limit: u32,
    pub offset: u32,
}

/// The active sidebar filters behind the faceted counts. All five compose as an
/// intersection — the current search, selected smart view, selected tag,
/// selected rating, and selected content kind (at most one of each, any may be
/// unset; `view` defaults to `All`). Each count query ignores its own facet axis
/// while kind always composes — see [`crate::list::CountScope`].
#[derive(uniffi::Record)]
pub struct FfiCountScope {
    pub view: FfiView,
    pub tag: Option<String>,
    pub rating: Option<u8>,
    pub kind: Option<FfiReadingKind>,
    pub query: Option<String>,
}

// ── Conversions ──────────────────────────────────────────────────────────────

impl From<crate::list::ReadingRow> for FfiReadingRow {
    fn from(r: crate::list::ReadingRow) -> Self {
        Self {
            id: r.id,
            title: r.title,
            kind: r.kind.into(),
            url: r.url,
            media_url: r.media_url,
            preview_asset: r.preview_asset,
            canonical_url: r.canonical_url,
            author: r.author,
            site: r.site,
            saved_at: r.saved_at,
            read: r.read,
            archived: r.archived,
            favorite: r.favorite,
            rating: r.rating,
            excerpt: r.excerpt,
            word_count: r.word_count,
            lang: r.lang,
            tags: r.tags,
        }
    }
}

impl From<ReadingKind> for FfiReadingKind {
    fn from(kind: ReadingKind) -> Self {
        match kind {
            ReadingKind::Article => Self::Article,
            ReadingKind::Image => Self::Image,
            ReadingKind::Video => Self::Video,
            ReadingKind::Quote => Self::Quote,
        }
    }
}

impl From<FfiReadingKind> for ReadingKind {
    fn from(kind: FfiReadingKind) -> Self {
        match kind {
            FfiReadingKind::Article => Self::Article,
            FfiReadingKind::Image => Self::Image,
            FfiReadingKind::Video => Self::Video,
            FfiReadingKind::Quote => Self::Quote,
        }
    }
}

impl From<crate::highlights::Highlight> for FfiHighlight {
    fn from(h: crate::highlights::Highlight) -> Self {
        Self {
            id: h.id,
            text: h.text,
        }
    }
}

impl From<SaveOutcome> for FfiImportResult {
    fn from(outcome: SaveOutcome) -> Self {
        Self {
            disposition: match outcome.disposition {
                SaveDisposition::Saved => FfiImportDisposition::Saved,
                SaveDisposition::Upgraded => FfiImportDisposition::Upgraded,
                SaveDisposition::Duplicate => FfiImportDisposition::Duplicate,
            },
            id: outcome.id,
            path: outcome.path,
        }
    }
}

impl From<crate::list::ViewCounts> for FfiViewCounts {
    fn from(c: crate::list::ViewCounts) -> Self {
        Self {
            all: c.all,
            unread: c.unread,
            read: c.read,
            archive: c.archive,
            favorites: c.favorites,
        }
    }
}

impl From<crate::list::SidebarCounts> for FfiSidebarCounts {
    fn from(c: crate::list::SidebarCounts) -> Self {
        Self {
            views: c.views.into(),
            tags: c
                .tags
                .into_iter()
                .map(|(tag, count)| FfiTagCount { tag, count })
                .collect(),
            ratings: c
                .ratings
                .into_iter()
                .map(|(rating, count)| FfiRatingCount { rating, count })
                .collect(),
        }
    }
}

impl From<FfiView> for View {
    fn from(v: FfiView) -> Self {
        match v {
            FfiView::All => View::All,
            FfiView::Unread => View::Unread,
            FfiView::Read => View::Read,
            FfiView::Archive => View::Archive,
            FfiView::Favorites => View::Favorites,
        }
    }
}

impl From<FfiCountScope> for CountScope {
    fn from(s: FfiCountScope) -> Self {
        Self {
            view: s.view.into(),
            tag: s.tag,
            rating: s.rating,
            kind: s.kind.map(Into::into),
            query: s.query,
        }
    }
}

impl From<FfiListOptions> for ListOptions {
    fn from(o: FfiListOptions) -> Self {
        Self {
            view: o.view.into(),
            sort: match o.sort {
                FfiSortField::SavedAt => SortField::SavedAt,
                FfiSortField::ReadAt => SortField::ReadAt,
                FfiSortField::Rating => SortField::Rating,
                FfiSortField::WordCount => SortField::WordCount,
                FfiSortField::Relevance => SortField::Relevance,
            },
            ascending: o.ascending,
            tag: o.tag,
            rating: o.rating,
            kind: o.kind.map(Into::into),
            since: o.since,
            until: o.until,
            query: o.query,
            limit: o.limit as usize,
            offset: o.offset as usize,
        }
    }
}

// ── Database object ───────────────────────────────────────────────────────────

/// The main entry point for the Swift client.
///
/// Wraps the SQLite connection and the last-known scan snapshot so the
/// caller can call `sync()` for incremental updates after the initial
/// `rebuild()`.
#[derive(uniffi::Object)]
pub struct Database {
    conn: Mutex<rusqlite::Connection>,
    last_scan: Mutex<Vec<ScannedReading>>,
}

#[uniffi::export]
impl Database {
    /// Open (or create) the index at `db_path`.
    #[uniffi::constructor]
    pub fn open(db_path: String) -> Result<Arc<Self>, CoreError> {
        let conn = crate::open_index(Path::new(&db_path)).map_err(e)?;
        Ok(Arc::new(Self {
            conn: Mutex::new(conn),
            last_scan: Mutex::new(Vec::new()),
        }))
    }

    // ── Indexing ──────────────────────────────────────────────────────────

    /// Full rebuild: scan the library and repopulate the index from scratch.
    ///
    /// Call this on first launch or after the library folder is replaced.
    /// Stores the resulting scan snapshot so `sync` can diff against it.
    pub fn rebuild(&self, library_path: String) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::rebuild(&conn, &lib).map_err(e)?;
        let scan = crate::scan_library(&lib).map_err(e)?;
        *self.last_scan.lock().unwrap() = scan;
        Ok(())
    }

    /// Incremental sync: diff the current library against the stored snapshot
    /// and apply only the changes. Returns the number of diffs applied.
    ///
    /// Call this on subsequent launches or when a file-system watch fires.
    pub fn sync(&self, library_path: String) -> Result<u32, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let new_scan = crate::scan_library(&lib).map_err(e)?;
        let old_scan = self.last_scan.lock().unwrap().clone();
        let diffs = crate::diff(&old_scan, &new_scan);
        let count = diffs.len() as u32;
        if !diffs.is_empty() {
            let conn = self.conn.lock().unwrap();
            crate::apply_diffs(&conn, &diffs).map_err(e)?;
        }
        *self.last_scan.lock().unwrap() = new_scan;
        Ok(count)
    }

    // ── Imports ───────────────────────────────────────────────────────────

    /// Add an HTTP(S) link as a lightweight article placeholder. A later full
    /// browser capture upgrades it in place because both use the same id.
    pub fn import_link(
        &self,
        library_path: String,
        url: String,
    ) -> Result<FfiImportResult, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let outcome = crate::import_link(&lib, &url).map_err(e)?;
        self.sync(library_path)?;
        Ok(outcome.into())
    }

    /// Add source-less plain text as a quote.
    pub fn import_text(
        &self,
        library_path: String,
        text: String,
        title: Option<String>,
    ) -> Result<FfiImportResult, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let outcome = crate::import_text(&lib, &text, title.as_deref()).map_err(e)?;
        self.sync(library_path)?;
        Ok(outcome.into())
    }

    /// Add source-less image bytes. `content_type` determines the local asset
    /// extension and `title` supplies the visible card label.
    pub fn import_image(
        &self,
        library_path: String,
        bytes: Vec<u8>,
        content_type: String,
        title: String,
    ) -> Result<FfiImportResult, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let outcome = crate::import_image(&lib, bytes, &content_type, &title).map_err(e)?;
        self.sync(library_path)?;
        Ok(outcome.into())
    }

    // ── Query ─────────────────────────────────────────────────────────────

    pub fn list_readings(&self, opts: FfiListOptions) -> Result<Vec<FfiReadingRow>, CoreError> {
        let conn = self.conn.lock().unwrap();
        crate::list_readings(&conn, &opts.into())
            .map_err(e)
            .map(|v| v.into_iter().map(Into::into).collect())
    }

    /// Every sidebar count section — the view badges, the tag counts, and the
    /// rating counts — in one call, scoped by the active search and the selected
    /// facets. Resolves the full-text `MATCH` once and returns all three
    /// together; see `sidebar_counts`.
    pub fn sidebar_counts(&self, scope: FfiCountScope) -> Result<FfiSidebarCounts, CoreError> {
        let conn = self.conn.lock().unwrap();
        crate::sidebar_counts(&conn, &scope.into())
            .map_err(e)
            .map(Into::into)
    }

    /// Fetch a reading's metadata row. Returns `None` if not found.
    pub fn get_reading_row(&self, id: String) -> Result<Option<FfiReadingRow>, CoreError> {
        let conn = self.conn.lock().unwrap();
        crate::get_reading(&conn, &id)
            .map_err(e)
            .map(|opt| opt.map(|(row, _body)| row.into()))
    }

    /// Fetch the body text of a reading. Returns `None` if not found.
    pub fn get_body(&self, id: String) -> Result<Option<String>, CoreError> {
        let conn = self.conn.lock().unwrap();
        crate::get_reading(&conn, &id)
            .map_err(e)
            .map(|opt| opt.map(|(_row, body)| body))
    }

    // ── Tags ──────────────────────────────────────────────────────────────

    pub fn add_tag(&self, library_path: String, id: String, tag: String) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::add_tag(&lib, &conn, &id, &tag).map_err(e)
    }

    pub fn remove_tag(
        &self,
        library_path: String,
        id: String,
        tag: String,
    ) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::remove_tag(&lib, &conn, &id, &tag).map_err(e)
    }

    // ── Ratings ───────────────────────────────────────────────────────────

    /// Set a reading's star rating (0–5, where 0 clears it).
    pub fn set_rating(
        &self,
        library_path: String,
        id: String,
        rating: u8,
    ) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::set_rating(&lib, &conn, &id, rating).map_err(e)
    }

    // ── Status flags ──────────────────────────────────────────────────────

    pub fn set_read(&self, library_path: String, id: String, read: bool) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::set_read(&lib, &conn, &id, read).map_err(e)
    }

    pub fn set_archived(
        &self,
        library_path: String,
        id: String,
        archived: bool,
    ) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::set_archived(&lib, &conn, &id, archived).map_err(e)
    }

    pub fn set_favorite(
        &self,
        library_path: String,
        id: String,
        favorite: bool,
    ) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::set_favorite(&lib, &conn, &id, favorite).map_err(e)
    }

    // ── Deletion ──────────────────────────────────────────────────────────

    /// Permanently delete a reading: its file, assets, and index row. Unlike
    /// `set_archived`, this cannot be undone.
    pub fn delete_reading(&self, library_path: String, id: String) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        let conn = self.conn.lock().unwrap();
        crate::delete_reading(&lib, &conn, &id).map_err(e)
    }

    // ── Highlights ────────────────────────────────────────────────────────

    /// List a reading's saved highlights, in creation order.
    pub fn list_highlights(
        &self,
        library_path: String,
        reading_id: String,
    ) -> Result<Vec<FfiHighlight>, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        crate::list_highlights(&lib, &reading_id)
            .map_err(e)
            .map(|v| v.into_iter().map(Into::into).collect())
    }

    /// Save a new highlight (the verbatim selected text) for a reading and
    /// return it. Re-adding an existing passage is a no-op that returns the
    /// existing highlight.
    pub fn add_highlight(
        &self,
        library_path: String,
        reading_id: String,
        text: String,
    ) -> Result<FfiHighlight, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        crate::add_highlight(&lib, &reading_id, &text)
            .map_err(e)
            .map(Into::into)
    }

    /// Toggle a highlight by its text: removes it if the exact passage is
    /// already highlighted, otherwise adds it. Returns `true` if the passage is
    /// highlighted after the call, `false` if it was cleared.
    pub fn toggle_highlight(
        &self,
        library_path: String,
        reading_id: String,
        text: String,
    ) -> Result<bool, CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        crate::toggle_highlight(&lib, &reading_id, &text).map_err(e)
    }

    /// Remove a single highlight from a reading.
    pub fn delete_highlight(
        &self,
        library_path: String,
        reading_id: String,
        highlight_id: String,
    ) -> Result<(), CoreError> {
        let lib = LibraryRoot::new(Path::new(&library_path)).map_err(e)?;
        crate::delete_highlight(&lib, &reading_id, &highlight_id).map_err(e)
    }
}
