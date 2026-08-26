// SPDX-License-Identifier: MIT

use anyhow::{bail, Result};
use rusqlite::{params_from_iter, types::Value, Connection};

use crate::{
    list::{pinned_count_filter, CountScope, Facet, ResolvedSearch},
    locking::lock_reading,
    parse_reading,
    reconcile::apply_diffs,
    scanner::{ScanDiff, ScannedReading},
    writer::write_reading_under_lock,
    LibraryRoot,
};

/// The longest a tag name may be, counted in Unicode scalar values (`char`s),
/// not bytes. Enforced by [`add_tag`]; the macOS client mirrors this limit to
/// surface the error before it reaches the core.
pub const MAX_TAG_LEN: usize = 20;

/// Validate and normalize an imported tag according to the library format.
///
/// Interactive tag entry retains its established behavior in [`add_tag`]. A
/// migration crosses a stricter trust boundary, so imported state must already
/// be lowercase and whitespace-free after surrounding whitespace is trimmed.
pub(crate) fn validate_imported_tag(tag: &str) -> Result<String> {
    let tag = tag.trim();
    if tag.is_empty() {
        bail!("tag must not be empty");
    }

    let len = tag.chars().count();
    if len > MAX_TAG_LEN {
        bail!("tag is too long: {len} characters (max {MAX_TAG_LEN})");
    }
    if tag.chars().any(char::is_whitespace) {
        bail!("tag must not contain whitespace: {tag:?}");
    }
    if tag.to_lowercase() != tag {
        bail!("tag must be lowercase: {tag:?}");
    }

    Ok(tag.to_string())
}

/// Add `tag` to the reading identified by `id`.
///
/// No-ops if the tag is already present. Rejects a tag longer than
/// [`MAX_TAG_LEN`] characters. Updates the `.md` file first, then syncs the
/// index row.
pub fn add_tag(library: &LibraryRoot, conn: &Connection, id: &str, tag: &str) -> Result<()> {
    let lock = lock_reading(library, id)?;
    let path = library.article_path(id);
    if !path.is_file() {
        bail!("reading not found: {id}");
    }

    let content = std::fs::read_to_string(&path)?;
    let mut reading = parse_reading(&content)?;

    let tag = tag.trim().to_string();
    let len = tag.chars().count();
    if len > MAX_TAG_LEN {
        bail!("tag is too long: {len} characters (max {MAX_TAG_LEN})");
    }
    if reading.metadata.tags.contains(&tag) {
        return Ok(());
    }

    reading.metadata.tags.push(tag);
    let written = write_reading_under_lock(library, reading.metadata, reading.body, &lock)?;
    sync_index(library, conn, &written.metadata.id)
}

/// Remove `tag` from the reading identified by `id`.
///
/// No-ops if the tag is not present. Updates the `.md` file first, then
/// syncs the index row.
pub fn remove_tag(library: &LibraryRoot, conn: &Connection, id: &str, tag: &str) -> Result<()> {
    let lock = lock_reading(library, id)?;
    let path = library.article_path(id);
    if !path.is_file() {
        bail!("reading not found: {id}");
    }

    let content = std::fs::read_to_string(&path)?;
    let mut reading = parse_reading(&content)?;

    let before = reading.metadata.tags.len();
    reading.metadata.tags.retain(|t| t != tag);
    if reading.metadata.tags.len() == before {
        return Ok(());
    }

    let written = write_reading_under_lock(library, reading.metadata, reading.body, &lock)?;
    sync_index(library, conn, &written.metadata.id)
}

/// Return the tags to show in the sidebar's Tags section, each with its badge
/// count, sorted **alphabetically by name**.
///
/// The tiles behave like the smart-view rows, which are a fixed set: *every* tag
/// in the library is always present, so switching view, searching, or picking a
/// rating only changes the *badge*, zeroing it rather than hiding the tile. This
/// is the Tags facet, so `scope`'s own tag selection is ignored (a facet never
/// filters itself).
///
/// The order is alphabetical, not by count, precisely *because* the set is fixed:
/// a count-based order would make tiles jump around as a search or facet changes
/// their badges. Alphabetical keeps every tile in the same position no matter
/// what the counts do.
///
/// The count re-applies the full view, the search, and the selected rating
/// through a `COUNT(...) FILTER`, so a tag with no matching reading reports 0
/// while keeping its tile. With the default scope (`view = All`) an archived-only
/// tag therefore shows a 0, and every other tag its plain non-archived count.
pub fn list_tags(conn: &Connection, scope: &CountScope) -> Result<Vec<(String, u64)>> {
    let search = ResolvedSearch::resolve_scoped(conn, scope)?;
    list_tags_with(conn, scope, &search)
}

/// [`list_tags`] with the search pre-resolved, so [`crate::list::sidebar_counts`]
/// can share one resolution across all three sidebar sections.
pub(crate) fn list_tags_with(
    conn: &Connection,
    scope: &CountScope,
    search: &ResolvedSearch,
) -> Result<Vec<(String, u64)>> {
    // Presence = every tag in the library (fixed set). The badge narrows to the
    // exact view plus the search and sibling rating facet.
    let mut vals: Vec<Value> = Vec::new();
    let count_filter = pinned_count_filter(scope, Facet::Rating, search, &mut vals);

    let sql = format!(
        "SELECT value, COUNT(*) FILTER (WHERE {count_filter}) AS cnt
         FROM readings, json_each(readings.tags_json)
         GROUP BY value
         ORDER BY value ASC"
    );
    let mut stmt = conn.prepare(&sql)?;

    let rows = stmt.query_map(params_from_iter(vals), |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, u64>(1)?))
    })?;

    rows.map(|r| r.map_err(Into::into)).collect()
}

/// Re-read the article file from disk and update its index row.
fn sync_index(library: &LibraryRoot, conn: &Connection, id: &str) -> Result<()> {
    let path = library.article_path(id);
    let content = std::fs::read_to_string(&path)?;
    let reading = parse_reading(&content)?;
    let modified_at = std::fs::metadata(&path)?.modified()?;
    let visual_asset = reading.metadata.preview_asset.as_deref().and_then(|asset| {
        if reading.metadata.kind == crate::ReadingKind::Image {
            crate::visual_index::inspect_image_asset(library, &reading.metadata.id, asset).ok()
        } else {
            crate::visual_index::inspect_asset(library, &reading.metadata.id, asset).ok()
        }
    });
    let media_aspect_ratio = crate::scanner::inspect_media_aspect_ratio(
        library,
        &reading.metadata,
        visual_asset.as_ref(),
    );

    let scanned = ScannedReading {
        id: reading.metadata.id.clone(),
        source_hash: reading.metadata.source_hash.clone(),
        modified_at,
        path,
        has_note: crate::scanner::note_file_exists(library, &reading.metadata.id),
        visual_asset,
        media_aspect_ratio,
        body: reading.body,
        metadata: reading.metadata,
    };

    apply_diffs(conn, &[ScanDiff::Changed(scanned)])
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

    fn meta(id: &str, url: &str) -> Metadata {
        Metadata {
            format_version: 1,
            id: id.to_string(),
            kind: Default::default(),
            lightweight: false,
            url: url.to_string(),
            media_url: None,
            preview_asset: None,
            favicon_asset: None,
            theme_color: None,
            canonical_url: url.to_string(),
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

    fn setup() -> (TempDir, Connection) {
        let dir = TempDir::new().unwrap();
        let conn = open(&dir.path().join("index.db")).unwrap();
        (dir, conn)
    }

    #[test]
    fn add_tag_updates_frontmatter() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        add_tag(&lib, &conn, &id, "rust").unwrap();

        let content = std::fs::read_to_string(lib.article_path(&id)).unwrap();
        assert!(content.contains("rust"), "tag should appear in frontmatter");
    }

    #[test]
    fn add_tag_updates_index() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();
        add_tag(&lib, &conn, &id, "rust").unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags, vec![("rust".to_string(), 1)]);
    }

    #[test]
    fn add_tag_is_idempotent() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        add_tag(&lib, &conn, &id, "rust").unwrap();
        add_tag(&lib, &conn, &id, "rust").unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].1, 1);
    }

    #[test]
    fn add_tag_accepts_tag_at_max_length() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Exactly MAX_TAG_LEN characters is allowed (the boundary is inclusive).
        let tag = "a".repeat(MAX_TAG_LEN);
        add_tag(&lib, &conn, &id, &tag).unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags, vec![(tag, 1)]);
    }

    #[test]
    fn add_tag_rejects_tag_over_max_length() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // One past the limit is rejected, and nothing is written to the index.
        let tag = "a".repeat(MAX_TAG_LEN + 1);
        assert!(add_tag(&lib, &conn, &id, &tag).is_err());
        assert!(list_tags(&conn, &CountScope::default()).unwrap().is_empty());
    }

    #[test]
    fn add_tag_counts_length_in_characters_not_bytes() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // 25 multi-byte characters (é is 2 bytes) is 50 bytes but only 25 chars,
        // so it must be accepted — the limit counts characters, not bytes.
        let tag = "é".repeat(MAX_TAG_LEN);
        add_tag(&lib, &conn, &id, &tag).unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags, vec![(tag, 1)]);
    }

    #[test]
    fn add_tag_measures_length_after_trimming() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Surrounding whitespace is trimmed before the length check, so a
        // MAX_TAG_LEN name padded with spaces still fits.
        let padded = format!("   {}   ", "a".repeat(MAX_TAG_LEN));
        add_tag(&lib, &conn, &id, &padded).unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags, vec![("a".repeat(MAX_TAG_LEN), 1)]);
    }

    #[test]
    fn imported_tag_validation_enforces_the_library_format() {
        assert_eq!(
            validate_imported_tag("  local-first  ").unwrap(),
            "local-first"
        );
        assert!(validate_imported_tag("").is_err());
        assert!(validate_imported_tag("   ").is_err());
        assert!(validate_imported_tag("Local-first").is_err());
        assert!(validate_imported_tag("local first").is_err());
        assert!(validate_imported_tag("local\tfirst").is_err());
        assert!(validate_imported_tag(&"a".repeat(MAX_TAG_LEN + 1)).is_err());
        assert!(validate_imported_tag(&"é".repeat(MAX_TAG_LEN)).is_ok());
    }

    #[test]
    fn remove_tag_updates_frontmatter_and_index() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        let mut m = meta(&id, "https://example.com");
        m.tags = vec!["rust".into(), "async".into()];
        write_reading(&lib, m, "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        remove_tag(&lib, &conn, &id, "rust").unwrap();

        let content = std::fs::read_to_string(lib.article_path(&id)).unwrap();
        assert!(
            !content.contains("rust"),
            "removed tag should be gone from frontmatter"
        );

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].0, "async");
    }

    #[test]
    fn remove_tag_noop_when_absent() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        let id = new_id();

        write_reading(&lib, meta(&id, "https://example.com"), "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Should not error even though the tag doesn't exist.
        remove_tag(&lib, &conn, &id, "nonexistent").unwrap();
    }

    #[test]
    fn list_tags_counts_across_readings() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id1 = new_id();
        let id2 = new_id();
        let mut m1 = meta(&id1, "https://a.com");
        m1.tags = vec!["rust".into(), "async".into()];
        let mut m2 = meta(&id2, "https://b.com");
        m2.tags = vec!["rust".into()];

        write_reading(&lib, m1, "body".into()).unwrap();
        write_reading(&lib, m2, "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        // Sorted alphabetically by name (not by count): async before rust.
        assert_eq!(tags[0], ("async".to_string(), 1));
        assert_eq!(tags[1], ("rust".to_string(), 2));
    }

    #[test]
    fn list_tags_includes_legacy_archived_readings_in_all() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut m = meta(&new_id(), "https://a.com");
        m.tags = vec!["hidden".into()];
        m.archived = true;
        write_reading(&lib, m, "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // All is the complete inspiration library, so cards written by older builds
        // remain discoverable even when their metadata still says archived.
        let tags = list_tags(&conn, &CountScope::default()).unwrap();
        assert_eq!(tags, vec![("hidden".to_string(), 1)]);
    }

    /// Build the faceting corpus shared by the scoped tag-count tests:
    /// A (active, rust+prog, 5★, "alpha"), B (active, rust, 3★, "beta"),
    /// C (archived, rust+old, 5★, "gamma").
    fn faceting_corpus(lib: &LibraryRoot, conn: &Connection) {
        let mut a = meta(&new_id(), "https://a.com");
        a.tags = vec!["rust".into(), "prog".into()];
        a.rating = 5;
        write_reading(lib, a, "alpha".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com");
        b.tags = vec!["rust".into()];
        b.rating = 3;
        write_reading(lib, b, "beta".into()).unwrap();
        let mut c = meta(&new_id(), "https://c.com");
        c.tags = vec!["rust".into(), "old".into()];
        c.rating = 5;
        c.archived = true;
        write_reading(lib, c, "gamma".into()).unwrap();
        rebuild(conn, lib).unwrap();
    }

    #[test]
    fn list_tags_scoped_by_search() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // "beta" is only in B (tags: rust). The search scopes the *counts*, not the
        // visible tiles: rust reports 1, while "prog" (on A, which doesn't match)
        // and "old" (archived) both stay pinned at 0 rather than disappearing.
        // Order is alphabetical, independent of the counts.
        let tags = list_tags(
            &conn,
            &CountScope {
                query: Some("beta".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            tags,
            vec![
                ("old".to_string(), 0),
                ("prog".to_string(), 0),
                ("rust".to_string(), 1),
            ]
        );
    }

    #[test]
    fn list_tags_follow_the_archive_view_facet() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // Selecting the Archive view flips the tag counts to the archived side:
        // C's tags (rust, old) count, while the active-only "prog" stays pinned at 0.
        let tags = list_tags(
            &conn,
            &CountScope {
                view: crate::list::View::Archive,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            tags,
            vec![
                ("old".to_string(), 1),
                ("prog".to_string(), 0),
                ("rust".to_string(), 1),
            ]
        );
    }

    #[test]
    fn list_tags_scoped_by_rating_facet() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // The legacy 5★ facet still sees both A and archived C in the complete All
        // library, so rust reports 2 while prog and old each report 1.
        let tags = list_tags(
            &conn,
            &CountScope {
                rating: Some(5),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            tags,
            vec![
                ("old".to_string(), 1),
                ("prog".to_string(), 1),
                ("rust".to_string(), 2),
            ]
        );
    }

    #[test]
    fn list_tags_pins_zero_count_tiles_under_a_rating_facet() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        // A: rust, 5★. B: cook, 3★. Both non-archived.
        let mut a = meta(&new_id(), "https://a.com");
        a.tags = vec!["rust".into()];
        a.rating = 5;
        write_reading(&lib, a, "alpha".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com");
        b.tags = vec!["cook".into()];
        b.rating = 3;
        write_reading(&lib, b, "beta".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Selecting 5★ keeps BOTH tiles visible (presence ignores the rating
        // facet); "cook" reports 0 instead of vanishing, since its only reading
        // is 3★. Order is alphabetical: cook before rust.
        let tags = list_tags(
            &conn,
            &CountScope {
                rating: Some(5),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(tags, vec![("cook".to_string(), 0), ("rust".to_string(), 1)]);
    }

    #[test]
    fn list_tags_pins_zero_under_search_plus_rating_facet() {
        // The exact sidebar flow: search narrows the set, then a rating facet is
        // clicked. Tags matching the search stay pinned; those with no reading at
        // the selected rating show 0 instead of disappearing.
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com"); // scifi, 5★, matches search
        a.tags = vec!["scifi".into()];
        a.rating = 5;
        write_reading(&lib, a, "a lone starship".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com"); // space, 3★, matches search
        b.tags = vec!["space".into()];
        b.rating = 3;
        write_reading(&lib, b, "a docking starship".into()).unwrap();
        let mut c = meta(&new_id(), "https://c.com"); // cooking, 5★, NO search match
        c.tags = vec!["cooking".into()];
        c.rating = 5;
        write_reading(&lib, c, "today I cooked pasta".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(
            &conn,
            &CountScope {
                query: Some("starship".into()),
                rating: Some(5),
                ..Default::default()
            },
        )
        .unwrap();
        // Presence is the whole (non-archived) view, so every tag stays visible:
        // scifi counts its one 5★ starship hit; space (3★) and cooking (no search
        // match at all) both stay pinned at 0. Order is alphabetical.
        assert_eq!(
            tags,
            vec![
                ("cooking".to_string(), 0),
                ("scifi".to_string(), 1),
                ("space".to_string(), 0),
            ]
        );
    }

    #[test]
    fn list_tags_pins_all_under_search_plus_tag_selection() {
        // The reported case: a tag is selected AND a search is typed. Every tag in
        // the view must stay visible; only the badges reflect the search.
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com"); // scifi, matches "starship"
        a.tags = vec!["scifi".into()];
        a.rating = 5;
        write_reading(&lib, a, "a lone starship".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com"); // space, matches "starship"
        b.tags = vec!["space".into()];
        b.rating = 3;
        write_reading(&lib, b, "a docking starship".into()).unwrap();
        let mut c = meta(&new_id(), "https://c.com"); // cooking, NO "starship"
        c.tags = vec!["cooking".into()];
        c.rating = 2;
        write_reading(&lib, c, "today I cooked pasta".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(
            &conn,
            &CountScope {
                tag: Some("scifi".into()),
                query: Some("starship".into()),
                ..Default::default()
            },
        )
        .unwrap();
        // The selected tag is the Tags section's own axis, so it's ignored here —
        // every tag stays. "cooking" (no search match) is pinned at 0. Order is
        // alphabetical.
        assert_eq!(
            tags,
            vec![
                ("cooking".to_string(), 0),
                ("scifi".to_string(), 1),
                ("space".to_string(), 1),
            ]
        );
    }

    #[test]
    fn list_tags_pins_across_the_unread_view() {
        // The reported case: searching, then clicking a smart view (Unread) must
        // not drop tags. A tag whose only reading is *read* stays visible at 0,
        // because All/Unread/Read share one presence pool.
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com"); // unread, #alpha
        a.tags = vec!["alpha".into()];
        write_reading(&lib, a, "coding in rust".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com"); // read, #beta
        b.tags = vec!["beta".into()];
        b.read_at = Some("2026-06-13T16:00:00.000Z".into());
        write_reading(&lib, b, "coding in swift".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(
            &conn,
            &CountScope {
                view: crate::list::View::Unread,
                query: Some("coding".into()),
                ..Default::default()
            },
        )
        .unwrap();
        // "beta" (on the read article) is pinned at 0 rather than hidden.
        assert_eq!(
            tags,
            vec![("alpha".to_string(), 1), ("beta".to_string(), 0)]
        );
    }

    #[test]
    fn list_tags_pins_across_the_favorites_view_without_search() {
        // The reported case: selecting Favorites (no search) must keep every tag.
        // A tag on a non-favorite reading stays visible at 0.
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com"); // favorite, #keep
        a.tags = vec!["keep".into()];
        a.favorite = true;
        write_reading(&lib, a, "body".into()).unwrap();
        let mut b = meta(&new_id(), "https://b.com"); // not favorite, #other
        b.tags = vec!["other".into()];
        write_reading(&lib, b, "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(
            &conn,
            &CountScope {
                view: crate::list::View::Favorites,
                ..Default::default()
            },
        )
        .unwrap();
        // "other" (on the non-favorite reading) is pinned at 0, not hidden.
        assert_eq!(
            tags,
            vec![("keep".to_string(), 1), ("other".to_string(), 0)]
        );
    }

    #[test]
    fn list_tags_order_is_alphabetical_and_stable_across_search() {
        // Tiles must keep the same position regardless of counts, so a search
        // never reshuffles them. zulu has the highest count, alpha the lowest, yet
        // the order stays alphabetical both unfiltered and under a search.
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut a = meta(&new_id(), "https://a.com"); // alpha, matches "widget"
        a.tags = vec!["alpha".into()];
        write_reading(&lib, a, "a widget".into()).unwrap();
        let mut z1 = meta(&new_id(), "https://z1.com"); // zulu x2, no "widget"
        z1.tags = vec!["zulu".into()];
        write_reading(&lib, z1, "nothing here".into()).unwrap();
        let mut z2 = meta(&new_id(), "https://z2.com");
        z2.tags = vec!["zulu".into()];
        write_reading(&lib, z2, "still nothing".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        // Unfiltered: alpha(1) before zulu(2) despite zulu's higher count.
        let names = |tags: Vec<(String, u64)>| tags.into_iter().map(|t| t.0).collect::<Vec<_>>();
        assert_eq!(
            names(list_tags(&conn, &CountScope::default()).unwrap()),
            vec!["alpha", "zulu"]
        );

        // Under a search that zeroes zulu, the positions are unchanged.
        let searched = list_tags(
            &conn,
            &CountScope {
                query: Some("widget".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            searched,
            vec![("alpha".to_string(), 1), ("zulu".to_string(), 0)]
        );
    }

    #[test]
    fn list_tags_ignores_its_own_tag_selection() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);
        faceting_corpus(&lib, &conn);

        // A selected tag must NOT filter the tag list — the facet shows every
        // sibling tag so the user can switch — so it matches the default listing.
        let selected = list_tags(
            &conn,
            &CountScope {
                tag: Some("rust".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(selected, list_tags(&conn, &CountScope::default()).unwrap());
        assert_eq!(
            selected,
            vec![
                ("old".to_string(), 1),
                ("prog".to_string(), 1),
                ("rust".to_string(), 3),
            ]
        );
    }

    #[test]
    fn add_tag_returns_error_for_unknown_id() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let result = add_tag(&lib, &conn, "nonexistent-id", "rust");
        assert!(result.is_err());
    }
}
