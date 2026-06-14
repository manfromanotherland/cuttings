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
            "read",
            "archived",
            "favorite",
            "source_hash",
            "tags_json",
            "body_text",
        ] {
            assert!(columns.contains(&col.to_string()), "missing column: {col}");
        }
    }
}
