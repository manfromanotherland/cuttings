// SPDX-License-Identifier: MIT

use std::path::Path;

use anyhow::Result;
use rusqlite::Connection;

/// Open (or create) the index database at `db_path` and run any pending migrations.
pub fn open(db_path: &Path) -> Result<Connection> {
    let conn = Connection::open(db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
    migrate(&conn)?;
    Ok(conn)
}

fn migrate(conn: &Connection) -> Result<()> {
    let version: u32 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version < 1 {
        migrate_v1(conn)?;
    }
    if version < 2 {
        migrate_v2(conn)?;
    }
    if version < 3 {
        migrate_v3(conn)?;
    }
    if version < 4 {
        migrate_v4(conn)?;
    }
    Ok(())
}

fn migrate_v1(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "
        BEGIN;

        CREATE TABLE IF NOT EXISTS readings (
            id           TEXT    PRIMARY KEY NOT NULL,
            url          TEXT    NOT NULL,
            canonical_url TEXT   NOT NULL,
            title        TEXT    NOT NULL,
            author       TEXT,
            site         TEXT,
            saved_at     TEXT    NOT NULL,
            read         INTEGER NOT NULL DEFAULT 0,
            archived     INTEGER NOT NULL DEFAULT 0,
            favorite     INTEGER NOT NULL DEFAULT 0,
            source_hash  TEXT    NOT NULL,
            excerpt      TEXT,
            word_count   INTEGER,
            lang         TEXT,
            tags_json    TEXT    NOT NULL DEFAULT '[]',
            body_text    TEXT    NOT NULL DEFAULT ''
            -- embedding BLOB reserved for future vector search (CORE-16)
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS readings_fts USING fts5(
            title,
            body_text,
            content=readings,
            content_rowid=rowid
        );

        -- Keep FTS in sync with the readings table.
        CREATE TRIGGER IF NOT EXISTS readings_ai
        AFTER INSERT ON readings BEGIN
            INSERT INTO readings_fts(rowid, title, body_text)
            VALUES (new.rowid, new.title, new.body_text);
        END;

        CREATE TRIGGER IF NOT EXISTS readings_ad
        AFTER DELETE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text)
            VALUES ('delete', old.rowid, old.title, old.body_text);
        END;

        CREATE TRIGGER IF NOT EXISTS readings_au
        AFTER UPDATE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text)
            VALUES ('delete', old.rowid, old.title, old.body_text);
            INSERT INTO readings_fts(rowid, title, body_text)
            VALUES (new.rowid, new.title, new.body_text);
        END;

        PRAGMA user_version = 1;

        COMMIT;
        ",
    )?;
    Ok(())
}

/// v2: add the `rating` column (0–5, 0 = unrated) for star ratings.
fn migrate_v2(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "
        BEGIN;
        ALTER TABLE readings ADD COLUMN rating INTEGER NOT NULL DEFAULT 0;
        PRAGMA user_version = 2;
        COMMIT;
        ",
    )?;
    Ok(())
}

/// v3: index the `site` column with a plain B-tree index.
///
/// Superseded by v4, which makes `site` part of the FTS index instead. This
/// step is kept verbatim because it may already have run on installs that were
/// stamped at version 3; migrations are append-only, so v4 (not a redefinition
/// of v3) carries the newer schema and drops this now-unused index.
fn migrate_v3(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "
        BEGIN;
        CREATE INDEX IF NOT EXISTS idx_readings_site ON readings(site);
        PRAGMA user_version = 3;
        COMMIT;
        ",
    )?;
    Ok(())
}

/// v4: add `site` to the full-text index so search matches a reading's source
/// site (e.g. "nytimes" surfaces articles from nytimes.com) using the same
/// tokenized, ranked matching as title and body.
///
/// FTS5 columns can't be altered in place, so the external-content table and
/// its sync triggers are dropped and recreated with the new column, then the
/// index is rebuilt from the `readings` content table (which already holds
/// `site`). `site` keeps column index 2, leaving the `snippet()` call on
/// body_text (index 1) untouched. The v3 B-tree index is dropped — FTS now
/// covers site lookups. This converges installs coming from v3 and fresh
/// installs (v1→v4) on an identical schema.
fn migrate_v4(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "
        BEGIN;

        DROP INDEX IF EXISTS idx_readings_site;

        DROP TRIGGER IF EXISTS readings_ai;
        DROP TRIGGER IF EXISTS readings_ad;
        DROP TRIGGER IF EXISTS readings_au;
        DROP TABLE IF EXISTS readings_fts;

        CREATE VIRTUAL TABLE readings_fts USING fts5(
            title,
            body_text,
            site,
            content=readings,
            content_rowid=rowid
        );

        CREATE TRIGGER readings_ai
        AFTER INSERT ON readings BEGIN
            INSERT INTO readings_fts(rowid, title, body_text, site)
            VALUES (new.rowid, new.title, new.body_text, new.site);
        END;

        CREATE TRIGGER readings_ad
        AFTER DELETE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text, site)
            VALUES ('delete', old.rowid, old.title, old.body_text, old.site);
        END;

        CREATE TRIGGER readings_au
        AFTER UPDATE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text, site)
            VALUES ('delete', old.rowid, old.title, old.body_text, old.site);
            INSERT INTO readings_fts(rowid, title, body_text, site)
            VALUES (new.rowid, new.title, new.body_text, new.site);
        END;

        -- Repopulate the index from the content table.
        INSERT INTO readings_fts(readings_fts) VALUES('rebuild');

        PRAGMA user_version = 4;

        COMMIT;
        ",
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn open_temp() -> (TempDir, Connection) {
        let dir = TempDir::new().unwrap();
        let conn = open(&dir.path().join("index.db")).unwrap();
        (dir, conn)
    }

    #[test]
    fn creates_schema_on_fresh_db() {
        let (_dir, conn) = open_temp();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, 4);

        // readings table exists
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM readings", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0);
    }

    #[test]
    fn fts_table_exists() {
        let (_dir, conn) = open_temp();
        // FTS5 tables show up in sqlite_master.
        let exists: bool = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='readings_fts'",
                [],
                |r| r.get::<_, i64>(0),
            )
            .map(|n| n > 0)
            .unwrap();
        assert!(exists, "readings_fts table should exist");
    }

    #[test]
    fn fts_indexes_site() {
        let (_dir, conn) = open_temp();

        conn.execute(
            "INSERT INTO readings
             (id, url, canonical_url, title, site, saved_at, source_hash, body_text)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                "01TESTID",
                "https://nytimes.com",
                "https://nytimes.com",
                "Headline",
                "nytimes.com",
                "2026-06-13T15:00:00Z",
                "sha256:abc",
                "Body without the search term."
            ],
        )
        .unwrap();

        // The term lives only in the site column, yet FTS finds it.
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM readings_fts WHERE readings_fts MATCH 'nytimes'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 1, "site token should be searchable via FTS");
    }

    #[test]
    fn migration_is_idempotent() {
        let dir = TempDir::new().unwrap();
        let db_path = dir.path().join("index.db");

        // Open twice — second open should not fail.
        open(&db_path).unwrap();
        open(&db_path).unwrap();
    }

    #[test]
    fn upgrade_from_v3_indexes_site_in_fts() {
        let dir = TempDir::new().unwrap();
        let db_path = dir.path().join("index.db");

        // Simulate an install stamped at v3 (pre-FTS-site): run v1–v3 directly,
        // insert a reading whose only occurrence of "nytimes" is its site, and
        // confirm the v3-era FTS index can't find it.
        {
            let conn = rusqlite::Connection::open(&db_path).unwrap();
            conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
                .unwrap();
            migrate_v1(&conn).unwrap();
            migrate_v2(&conn).unwrap();
            migrate_v3(&conn).unwrap();

            conn.execute(
                "INSERT INTO readings
                 (id, url, canonical_url, title, site, saved_at, source_hash, body_text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    "01TESTID",
                    "https://nytimes.com",
                    "https://nytimes.com",
                    "Headline",
                    "nytimes.com",
                    "2026-06-13T15:00:00Z",
                    "sha256:abc",
                    "Body without the search term."
                ],
            )
            .unwrap();

            let version: u32 = conn
                .pragma_query_value(None, "user_version", |r| r.get(0))
                .unwrap();
            assert_eq!(version, 3, "precondition: stamped at v3");

            let before: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM readings_fts WHERE readings_fts MATCH 'nytimes'",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(before, 0, "v3 FTS has no site column to match");
        }

        // Reopen through the public path: migrations must carry it to v4 and
        // rebuild the FTS index — so the *existing* row becomes site-searchable.
        let conn = open(&db_path).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, 4, "v4 migration ran on top of the v3 database");

        let after: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM readings_fts WHERE readings_fts MATCH 'nytimes'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(after, 1, "v4 rebuild indexed site for the existing row");

        // The superseded B-tree index is cleaned up.
        let idx: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_readings_site'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(idx, 0, "v3 index dropped by v4");
    }

    #[test]
    fn insert_and_fts_search() {
        let (_dir, conn) = open_temp();

        conn.execute(
            "INSERT INTO readings
             (id, url, canonical_url, title, saved_at, source_hash, body_text)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![
                "01TESTID",
                "https://example.com",
                "https://example.com",
                "Rust programming",
                "2026-06-13T15:00:00Z",
                "sha256:abc",
                "Rust is a systems programming language."
            ],
        )
        .unwrap();

        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM readings_fts WHERE readings_fts MATCH 'rust'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(
            count, 1,
            "FTS search for 'rust' should find the inserted row"
        );
    }

    #[test]
    fn schema_has_expected_columns() {
        let (_dir, conn) = open_temp();

        // PRAGMA table_info returns one row per column.
        let mut stmt = conn.prepare("PRAGMA table_info(readings)").unwrap();
        let columns: Vec<String> = stmt
            .query_map([], |r| r.get::<_, String>(1))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        for col in &[
            "id",
            "url",
            "canonical_url",
            "title",
            "read",
            "archived",
            "favorite",
            "rating",
            "source_hash",
            "tags_json",
            "body_text",
        ] {
            assert!(columns.contains(&col.to_string()), "missing column: {col}");
        }
    }
}
