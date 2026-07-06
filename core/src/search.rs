// SPDX-License-Identifier: MIT

use anyhow::Result;
use rusqlite::{params, Connection};

/// A single result returned by a full-text search.
#[derive(Debug, Clone, PartialEq)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub excerpt: Option<String>,
    /// Context snippet with matched terms wrapped in `<mark>…</mark>`.
    pub snippet: String,
    pub tags: Vec<String>,
    pub saved_at: String,
}

/// Split user text into word tokens, dropping all punctuation/operators.
///
/// User input (especially pasted prose) routinely contains characters FTS5
/// treats as operators — `"` (phrase), `-` (NOT), `:` (column), `*` (prefix),
/// `(` `)` (grouping), and the `AND`/`OR`/`NOT` keywords. Reducing the input
/// to bare word tokens and re-quoting them ourselves means none of those can
/// reach the FTS5 parser, so a query can never raise a syntax error.
fn tokenize(raw: &str) -> Vec<String> {
    raw.split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect()
}

/// Exact contiguous phrase, e.g. `"core rust concepts"*`. The whole input is
/// one quoted phrase (so FTS5 keywords/operators stay literal); the trailing
/// `*` makes only the final token a prefix, so a half-typed last word matches
/// as you type while the earlier, completed words stay exact.
fn phrase_query(tokens: &[String]) -> String {
    format!("\"{}\"*", tokens.join(" "))
}

/// All-words AND, e.g. `"core" "rust" "concepts"*`. Space-separated quoted
/// terms are implicitly AND-ed by FTS5: every word must appear in the article,
/// in any order or position. Only the final term gets a prefix `*` (the word
/// being typed); the rest must match in full.
fn and_query(tokens: &[String]) -> String {
    let last = tokens.len() - 1;
    tokens
        .iter()
        .enumerate()
        .map(|(i, t)| {
            if i == last {
                format!("\"{t}\"*")
            } else {
                format!("\"{t}\"")
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Build the FTS5 `MATCH` string for `query`, preferring an exact phrase and
/// falling back to all-words-AND when the phrase matches nothing. Returns
/// `None` when there's nothing searchable (blank / pure punctuation).
///
/// Shared by [`search`] and `list_readings`' full-text branch so both agree on
/// how user text becomes an FTS query.
pub(crate) fn match_query(conn: &Connection, query: &str) -> Result<Option<String>> {
    let tokens = tokenize(query);
    if tokens.is_empty() {
        return Ok(None);
    }
    let phrase = phrase_query(&tokens);
    let phrase_matches: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM readings_fts WHERE readings_fts MATCH ?1)",
        params![phrase],
        |row| row.get(0),
    )?;
    Ok(Some(if phrase_matches {
        phrase
    } else {
        and_query(&tokens)
    }))
}

/// Run a full-text search against the index.
///
/// `query` is plain user text. It is first matched as an exact contiguous
/// phrase; if that finds nothing, it falls back to requiring all the words to
/// appear anywhere in the article. The fallback matters because `body_text`
/// holds the raw Markdown, so link URLs and other markup are tokenized
/// *between* the visible words — pasted rendered prose rarely lines up as a
/// literal phrase, but every word is still present.
///
/// The FTS index spans the title, body, *and* source site, so a query like
/// "nytimes" surfaces articles from nytimes.com even when the term appears
/// nowhere in their text — site tokens match (and prefix-match) just like any
/// other word. Results are ranked by BM25 relevance (best first), capped at
/// `limit`.
pub fn search(conn: &Connection, query: &str, limit: usize) -> Result<Vec<SearchResult>> {
    let tokens = tokenize(query);
    // Nothing searchable (blank, or pure punctuation/operators).
    if tokens.is_empty() {
        return Ok(vec![]);
    }

    let phrase = run_match(conn, &phrase_query(&tokens), limit)?;
    if !phrase.is_empty() {
        return Ok(phrase);
    }
    run_match(conn, &and_query(&tokens), limit)
}

/// Execute one FTS5 `MATCH` query and collect the ranked results.
fn run_match(conn: &Connection, match_query: &str, limit: usize) -> Result<Vec<SearchResult>> {
    let mut stmt = conn.prepare(
        "SELECT r.id, r.title, r.excerpt, r.tags_json, r.saved_at,
                snippet(readings_fts, 1, '<mark>', '</mark>', '…', 20)
         FROM readings_fts
         JOIN readings r ON r.rowid = readings_fts.rowid
         WHERE readings_fts MATCH ?1
         ORDER BY bm25(readings_fts)
         LIMIT ?2",
    )?;

    let rows = stmt.query_map(params![match_query, limit as i64], |row| {
        let tags_json: String = row.get(3)?;
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
            tags_json,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
        ))
    })?;

    let mut results = Vec::new();
    for row in rows {
        let (id, title, excerpt, tags_json, saved_at, snippet) = row?;
        let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
        results.push(SearchResult {
            id,
            title,
            excerpt,
            snippet,
            tags,
            saved_at,
        });
    }

    Ok(results)
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
    fn empty_query_returns_nothing() {
        let (_dir, conn) = setup();
        let results = search(&conn, "", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn finds_match_in_title() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "Rust Programming Language"),
            "Some body text.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "rust", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn finds_match_in_body() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "An Article"),
            "Ownership and borrowing are core Rust concepts.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "borrowing", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn no_match_returns_empty() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Rust Article"),
            "Body about Rust.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "python", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn limit_caps_results() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        for i in 0..5 {
            write_reading(
                &lib,
                meta(&new_id(), &format!("https://example.com/{i}"), "Rust tips"),
                "Rust is great.".to_string(),
            )
            .unwrap();
        }
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "rust", 3).unwrap();
        assert_eq!(results.len(), 3);
    }

    #[test]
    fn snippet_contains_mark_tags() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Article"),
            "The lifetime system in Rust prevents dangling pointers.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "lifetime", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert!(
            results[0].snippet.contains("<mark>"),
            "snippet should highlight matched term"
        );
    }

    #[test]
    fn multi_word_phrase_matches_contiguous_body() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "An Article"),
            "Ownership and borrowing are core Rust concepts.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "core Rust concepts", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn pasted_text_with_punctuation_matches_source() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "An Article"),
            "Ownership and borrowing are core Rust concepts.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // A pasted snippet carrying punctuation, a stray quote, a hyphen and a
        // colon must not raise an FTS5 syntax error and must still find the
        // source (both sides tokenize identically).
        let results = search(&conn, "borrowing are \"core\" Rust-concepts:", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn non_contiguous_words_match_via_and_fallback() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "An Article"),
            "Ownership and borrowing are core Rust concepts.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // Not adjacent → no exact phrase match, but both words are present, so
        // the all-words AND fallback still finds the article.
        let results = search(&conn, "Ownership concepts", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn pasted_prose_across_a_link_still_matches() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        // body_text is raw Markdown, so the link URL is tokenized *between*
        // the visible words: read the official docs <https doc rust ...> now.
        write_reading(
            &lib,
            meta(&id, "https://example.com", "Docs"),
            "Read the [official docs](https://doc.rust-lang.org/book) now.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // Pasting the rendered sentence can't match as a contiguous phrase
        // (the URL tokens interleave), but every word is present → AND fallback.
        let results = search(&conn, "Read the official docs now", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn truncated_last_word_matches_via_phrase_prefix() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "Loops"),
            "Loop engineering is replacing yourself as the person who prompts the agent."
                .to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // Typing stops mid-word: "…prompts the ag". The trailing prefix lets
        // "ag" match "agent" so the result appears before the word is finished.
        let results = search(&conn, "prompts the ag", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn truncated_last_word_matches_across_link_via_and_prefix() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta(&id, "https://example.com", "Docs"),
            "Read the [official docs](https://doc.rust-lang.org/book) now.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // Phrase fails (URL interleaves) AND the last word is truncated; the
        // AND fallback with a prefix on the final term still finds it.
        let results = search(&conn, "official docs no", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    fn meta_site(id: &str, url: &str, title: &str, site: &str) -> Metadata {
        let mut m = meta(id, url, title);
        m.site = Some(site.to_string());
        m
    }

    #[test]
    fn finds_match_by_site() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta_site(&id, "https://nytimes.com/a", "Some Headline", "nytimes.com"),
            "Body with no mention of the source.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // The term appears nowhere in title/body — only in the site column.
        let results = search(&conn, "nytimes", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn site_match_is_case_insensitive() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta_site(&id, "https://www.GitHub.com/x", "Repo", "www.GitHub.com"),
            "body".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // FTS lowercases tokens, so a lowercase query matches a mixed-case site.
        let results = search(&conn, "github", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn site_prefix_match_works() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        let id = new_id();
        write_reading(
            &lib,
            meta_site(&id, "https://nytimes.com/a", "Headline", "nytimes.com"),
            "Body with no mention of the source.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // A half-typed site token prefix-matches, just like title/body terms:
        // the trailing-`*` on the last token lets "nyt" reach "nytimes".
        let results = search(&conn, "nyt", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, id);
    }

    #[test]
    fn site_and_content_matches_have_no_duplicates() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        // Article A: "rust" only in the body.
        let a = new_id();
        write_reading(
            &lib,
            meta_site(
                &a,
                "https://blog.example.com/a",
                "Post A",
                "blog.example.com",
            ),
            "All about rust and ownership.".to_string(),
        )
        .unwrap();

        // Article B: site is rust-lang.org; "rust" appears in the site only.
        let b = new_id();
        write_reading(
            &lib,
            meta_site(&b, "https://rust-lang.org/b", "Post B", "rust-lang.org"),
            "Body with no keyword.".to_string(),
        )
        .unwrap();

        // Article C: "rust" in BOTH body and site — a single MATCH must still
        // return it exactly once.
        let c = new_id();
        write_reading(
            &lib,
            meta_site(&c, "https://rust-lang.org/c", "Post C", "rust-lang.org"),
            "Learning rust today.".to_string(),
        )
        .unwrap();

        rebuild(&conn, &lib).unwrap();

        let results = search(&conn, "rust", 10).unwrap();
        let ids: Vec<&str> = results.iter().map(|r| r.id.as_str()).collect();

        assert!(ids.contains(&a.as_str()), "body hit A should be present");
        assert!(ids.contains(&b.as_str()), "site hit B should be present");
        assert!(ids.contains(&c.as_str()), "hit C should be present");
        // C matches in two columns but FTS lists each row once.
        assert_eq!(results.len(), 3, "C must not be duplicated");
    }

    #[test]
    fn operator_characters_are_treated_literally() {
        let (dir, conn) = setup();
        let lib = make_library(&dir);

        write_reading(
            &lib,
            meta(&new_id(), "https://example.com", "Article"),
            "Asynchronous programming with async/await in Rust.".to_string(),
        )
        .unwrap();
        rebuild(&conn, &lib).unwrap();

        // A trailing `*` is no longer FTS5 prefix syntax; it's a literal,
        // ignorable separator, so this matches the `async` token without error.
        let results = search(&conn, "async*", 10).unwrap();
        assert_eq!(results.len(), 1);

        // Input that is nothing but operator characters tokenizes to an empty
        // phrase: zero matches, never an error.
        let results = search(&conn, "-\"()*:", 10).unwrap();
        assert!(results.is_empty());
    }
}
