// SPDX-License-Identifier: MIT

use std::path::Path;

use anyhow::Result;
use rusqlite::Connection;

/// Open (or create) the index database at `db_path` and run any pending migrations.
pub fn open(db_path: &Path) -> Result<Connection> {
    let mut conn = Connection::open(db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
    migrate(&conn)?;
    if std::env::var_os("SQL_TRACE").is_some() {
        install_sql_trace(&mut conn);
    }
    Ok(conn)
}

/// Log every executed SQL statement (with its wall-clock duration) to stderr.
///
/// Gated on the `SQL_TRACE` env var so release builds pay nothing. Useful for
/// spotting chatty callers and N+1 patterns — a statement that repeats dozens
/// of times per UI action shows up as an obvious run of identical lines.
fn install_sql_trace(conn: &mut Connection) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNT: AtomicU64 = AtomicU64::new(0);
    conn.profile(Some(|sql: &str, dur: std::time::Duration| {
        let n = COUNT.fetch_add(1, Ordering::Relaxed) + 1;
        let ms = dur.as_secs_f64() * 1e3;
        if ms < 1.0 {
            eprintln!("[sql #{n} {:>6.2}µs] {sql}", ms * 1e3);
        } else {
            eprintln!("[sql #{n} {:>6.2}ms] {sql}", ms);
        }
    }));
}

fn migrate(conn: &Connection) -> Result<()> {
    let version: u32 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version < 1 {
        migrate_v1(conn)?;
    }
    // Future schema changes append here as new, monotonically-numbered steps —
    // never edit `migrate_v1`, add `if version < 2 { migrate_v2(conn)?; }` and a
    // matching `migrate_v2` that alters the schema forward and stamps
    // `PRAGMA user_version = 2`.
    Ok(())
}

/// v1: the initial schema.
///
/// This is a fresh baseline: the app has no released users, so the earlier
/// incremental migrations were collapsed into this single step rather than
/// carried forever. It creates the `readings` table, the `readings_fts`
/// full-text index (covering title, body, and site), and the triggers that keep
/// the two in sync. Later releases add migrations on top of this — see
/// [`migrate`].
fn migrate_v1(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "
        BEGIN;

        CREATE TABLE IF NOT EXISTS readings (
            id            TEXT    PRIMARY KEY NOT NULL,
            url           TEXT    NOT NULL,
            canonical_url TEXT    NOT NULL,
            title         TEXT    NOT NULL,
            author        TEXT,
            site          TEXT,
            saved_at      TEXT    NOT NULL,
            read_at       TEXT,
            archived      INTEGER NOT NULL DEFAULT 0,
            favorite      INTEGER NOT NULL DEFAULT 0,
            rating        INTEGER NOT NULL DEFAULT 0,
            source_hash   TEXT    NOT NULL,
            excerpt       TEXT,
            word_count    INTEGER,
            lang          TEXT,
            tags_json     TEXT    NOT NULL DEFAULT '[]',
            body_text     TEXT    NOT NULL DEFAULT ''
            -- embedding BLOB reserved for future vector search (CORE-16)
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS readings_fts USING fts5(
            title,
            body_text,
            site,
            content=readings,
            content_rowid=rowid
        );

        -- Keep FTS in sync with the readings table.
        CREATE TRIGGER IF NOT EXISTS readings_ai
        AFTER INSERT ON readings BEGIN
            INSERT INTO readings_fts(rowid, title, body_text, site)
            VALUES (new.rowid, new.title, new.body_text, new.site);
        END;

        CREATE TRIGGER IF NOT EXISTS readings_ad
        AFTER DELETE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text, site)
            VALUES ('delete', old.rowid, old.title, old.body_text, old.site);
        END;

        CREATE TRIGGER IF NOT EXISTS readings_au
        AFTER UPDATE ON readings BEGIN
            INSERT INTO readings_fts(readings_fts, rowid, title, body_text, site)
            VALUES ('delete', old.rowid, old.title, old.body_text, old.site);
            INSERT INTO readings_fts(rowid, title, body_text, site)
            VALUES (new.rowid, new.title, new.body_text, new.site);
        END;

        PRAGMA user_version = 1;

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
        assert_eq!(version, 1);

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
            "read_at",
            "archived",
            "favorite",
            "rating",
            "source_hash",
            "tags_json",
            "body_text",
        ] {
            assert!(columns.contains(&col.to_string()), "missing column: {col}");
        }

        // The old `read` boolean is gone — read state lives in `read_at`.
        assert!(
            !columns.contains(&"read".to_string()),
            "legacy `read` column should be dropped"
        );
    }
}
