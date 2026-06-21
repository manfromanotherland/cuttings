// SPDX-License-Identifier: MIT

use anyhow::{bail, Result};
use rusqlite::Connection;

use crate::{
    parse_reading,
    reconcile::apply_diffs,
    scanner::{ScanDiff, ScannedReading},
    write_reading, LibraryRoot,
};

/// Add `tag` to the reading identified by `id`.
///
/// No-ops if the tag is already present. Updates the `.md` file first, then
/// syncs the index row.
pub fn add_tag(library: &LibraryRoot, conn: &Connection, id: &str, tag: &str) -> Result<()> {
    let path = library.article_path(id);
    if !path.is_file() {
        bail!("reading not found: {id}");
    }

    let content = std::fs::read_to_string(&path)?;
    let mut reading = parse_reading(&content)?;

    let tag = tag.trim().to_string();
    if reading.metadata.tags.contains(&tag) {
        return Ok(());
    }

    reading.metadata.tags.push(tag);
    let written = write_reading(library, reading.metadata, reading.body)?;
    sync_index(library, conn, &written.metadata.id)
}

/// Remove `tag` from the reading identified by `id`.
///
/// No-ops if the tag is not present. Updates the `.md` file first, then
/// syncs the index row.
pub fn remove_tag(library: &LibraryRoot, conn: &Connection, id: &str, tag: &str) -> Result<()> {
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

    let written = write_reading(library, reading.metadata, reading.body)?;
    sync_index(library, conn, &written.metadata.id)
}

/// Return all tags that appear on at least one non-archived reading,
/// with their occurrence counts, sorted by count descending then name ascending.
pub fn list_tags(conn: &Connection) -> Result<Vec<(String, u64)>> {
    let mut stmt = conn.prepare(
        "SELECT value, COUNT(*) AS cnt
         FROM readings, json_each(readings.tags_json)
         WHERE readings.archived = 0
         GROUP BY value
         ORDER BY cnt DESC, value ASC",
    )?;

    let rows = stmt.query_map([], |row| {
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

    let scanned = ScannedReading {
        id: reading.metadata.id.clone(),
        source_hash: reading.metadata.source_hash.clone(),
        modified_at,
        path,
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
            url: url.to_string(),
            canonical_url: url.to_string(),
            title: "Test".to_string(),
            author: None,
            site: None,
            saved_at: "2026-06-13T15:00:00Z".to_string(),
            read: false,
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

        let tags = list_tags(&conn).unwrap();
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

        let tags = list_tags(&conn).unwrap();
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].1, 1);
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

        let tags = list_tags(&conn).unwrap();
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

        let tags = list_tags(&conn).unwrap();
        // rust appears twice, async once; sorted by count desc then name asc
        assert_eq!(tags[0], ("rust".to_string(), 2));
        assert_eq!(tags[1], ("async".to_string(), 1));
    }

    #[test]
    fn list_tags_excludes_archived() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let mut m = meta(&new_id(), "https://a.com");
        m.tags = vec!["hidden".into()];
        m.archived = true;
        write_reading(&lib, m, "body".into()).unwrap();
        rebuild(&conn, &lib).unwrap();

        let tags = list_tags(&conn).unwrap();
        assert!(
            tags.is_empty(),
            "archived readings should not contribute to tag counts"
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
