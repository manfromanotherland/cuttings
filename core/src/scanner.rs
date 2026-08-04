// SPDX-License-Identifier: MIT

use std::{collections::HashMap, path::PathBuf, time::SystemTime};

use anyhow::Result;

use crate::{parse_reading, types::LibraryRoot, Metadata};

/// One article as seen on disk.
#[derive(Debug, Clone)]
pub struct ScannedReading {
    pub id: String,
    pub path: PathBuf,
    pub source_hash: String,
    pub modified_at: SystemTime,
    pub metadata: Metadata,
    /// Raw Markdown body (after stripping frontmatter), stored for FTS indexing.
    pub body: String,
}

/// Change detected between two scans.
#[derive(Debug)]
pub enum ScanDiff {
    Added(ScannedReading),
    Changed(ScannedReading),
    Removed(String),
}

/// Walk `articles/` and return one entry per `.md` file.
///
/// Files that fail to parse are skipped with an error logged to stderr rather
/// than aborting the whole scan, so a single corrupt file doesn't break the
/// indexer.
pub fn scan_library(library: &LibraryRoot) -> Result<Vec<ScannedReading>> {
    let articles_dir = library.articles_dir();
    if !articles_dir.is_dir() {
        return Ok(vec![]);
    }

    let mut results = Vec::new();
    // Fan-out layout: articles/<2-char prefix>/<id>/article.md. Each reading is a
    // self-contained folder, so walk two levels of sub-directories (bucket → the
    // reading folder) and read the `article.md` inside each reading folder. The
    // sibling `assets/` folder and `highlights.md` are not readings, so keying on
    // the fixed `article.md` filename skips them without extra checks.
    for bucket in std::fs::read_dir(&articles_dir)? {
        let bucket = bucket?;
        if !bucket.file_type()?.is_dir() {
            continue; // ignore stray files sitting directly in articles/
        }
        for reading_dir in std::fs::read_dir(bucket.path())? {
            let reading_dir = reading_dir?;
            if !reading_dir.file_type()?.is_dir() {
                continue; // ignore stray files sitting directly in a bucket
            }
            let path = reading_dir.path().join("article.md");
            let file_meta = match std::fs::metadata(&path) {
                Ok(m) => m,
                Err(_) => continue, // a folder without an article.md is not a reading
            };

            let modified_at = file_meta.modified()?;
            let content = match std::fs::read_to_string(&path) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("scanner: skipping {}: {e}", path.display());
                    continue;
                }
            };
            let reading = match parse_reading(&content) {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("scanner: skipping {}: {e}", path.display());
                    continue;
                }
            };

            results.push(ScannedReading {
                id: reading.metadata.id.clone(),
                source_hash: reading.metadata.source_hash.clone(),
                modified_at,
                path,
                metadata: reading.metadata,
                body: reading.body,
            });
        }
    }

    Ok(results)
}

/// Diff two snapshots, using `source_hash` as the change signal.
///
/// Items present in `new` but absent in `old` → `Added`.
/// Items present in both but with a differing `source_hash` → `Changed`.
/// Items present in `old` but absent in `new` → `Removed`.
pub fn diff(old: &[ScannedReading], new: &[ScannedReading]) -> Vec<ScanDiff> {
    let old_hashes: HashMap<&str, &str> = old
        .iter()
        .map(|r| (r.id.as_str(), r.source_hash.as_str()))
        .collect();
    let new_ids: std::collections::HashSet<&str> = new.iter().map(|r| r.id.as_str()).collect();

    let mut diffs = Vec::new();

    for reading in new {
        match old_hashes.get(reading.id.as_str()) {
            None => diffs.push(ScanDiff::Added(reading.clone())),
            Some(&old_hash) if old_hash != reading.source_hash => {
                diffs.push(ScanDiff::Changed(reading.clone()))
            }
            _ => {}
        }
    }

    for reading in old {
        if !new_ids.contains(reading.id.as_str()) {
            diffs.push(ScanDiff::Removed(reading.id.clone()));
        }
    }

    diffs
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    use crate::{new_id, write_reading, LibraryRoot, Metadata};

    fn sample_metadata(id: &str, url: &str) -> Metadata {
        Metadata {
            format_version: 1,
            id: id.to_string(),
            url: url.to_string(),
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

    fn make_library(dir: &TempDir) -> LibraryRoot {
        fs::create_dir_all(dir.path().join("articles")).unwrap();
        LibraryRoot::new(dir.path()).unwrap()
    }

    #[test]
    fn empty_library_returns_empty_scan() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let results = scan_library(&lib).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn scan_returns_one_entry_per_article() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id1 = new_id();
        let id2 = new_id();
        write_reading(
            &lib,
            sample_metadata(&id1, "https://a.com"),
            "body one".to_string(),
        )
        .unwrap();
        write_reading(
            &lib,
            sample_metadata(&id2, "https://b.com"),
            "body two".to_string(),
        )
        .unwrap();

        let results = scan_library(&lib).unwrap();
        assert_eq!(results.len(), 2);
    }

    #[test]
    fn scan_populates_source_hash() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id = new_id();
        let reading = write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "hello".to_string(),
        )
        .unwrap();

        let results = scan_library(&lib).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].source_hash, reading.metadata.source_hash);
    }

    #[test]
    fn diff_detects_added() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "body".to_string(),
        )
        .unwrap();

        let new_scan = scan_library(&lib).unwrap();
        let diffs = diff(&[], &new_scan);
        assert_eq!(diffs.len(), 1);
        assert!(matches!(diffs[0], ScanDiff::Added(_)));
    }

    #[test]
    fn diff_detects_removed() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "body".to_string(),
        )
        .unwrap();
        let old_scan = scan_library(&lib).unwrap();

        // Delete the file to simulate removal.
        fs::remove_file(lib.article_path(&id)).unwrap();

        let new_scan = scan_library(&lib).unwrap();
        let diffs = diff(&old_scan, &new_scan);
        assert_eq!(diffs.len(), 1);
        assert!(matches!(&diffs[0], ScanDiff::Removed(rid) if rid == &id));
    }

    #[test]
    fn diff_detects_changed() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "original body".to_string(),
        )
        .unwrap();
        let old_scan = scan_library(&lib).unwrap();

        // Overwrite with different body → different source_hash.
        write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "updated body".to_string(),
        )
        .unwrap();
        let new_scan = scan_library(&lib).unwrap();

        let diffs = diff(&old_scan, &new_scan);
        assert_eq!(diffs.len(), 1);
        assert!(matches!(diffs[0], ScanDiff::Changed(_)));
    }

    #[test]
    fn diff_no_change_when_hash_matches() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            sample_metadata(&id, "https://example.com"),
            "body".to_string(),
        )
        .unwrap();
        let scan = scan_library(&lib).unwrap();

        // Diff against itself — nothing should change.
        let diffs = diff(&scan, &scan);
        assert!(diffs.is_empty());
    }
}
