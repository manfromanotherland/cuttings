// SPDX-License-Identifier: MIT

//! Per-reading text highlights, stored as a Markdown document.
//!
//! Each reading's highlights live in `highlights.md` inside the reading's own
//! folder, beside its `article.md`. They stay out of the SQLite index, and the
//! scanner keys on the fixed `article.md` filename, so it never mistakes the
//! highlights file for a reading. A highlight is the verbatim text the user
//! selected in the reader; the file renders each as a Markdown block quote
//! followed by an HTML comment carrying a stable id, so highlights can be listed
//! and deleted individually while the file stays human-readable.

use anyhow::{bail, Result};

use crate::{new_id, LibraryRoot};

/// A single saved highlight: a stable id and the verbatim selected text.
#[derive(Debug, Clone, PartialEq)]
pub struct Highlight {
    pub id: String,
    pub text: String,
}

/// List a reading's highlights in creation order. A missing file (the common
/// case — most readings have none) yields an empty list.
pub fn list_highlights(library: &LibraryRoot, reading_id: &str) -> Result<Vec<Highlight>> {
    let path = library.highlights_path(reading_id);
    if !path.is_file() {
        return Ok(Vec::new());
    }
    let content = std::fs::read_to_string(&path)?;
    Ok(parse(&content))
}

/// Append a highlight for `reading_id` and return it. Creates the `highlights/`
/// directory and the file on first use. Whitespace-only text is rejected.
/// Duplicates are never stored: re-adding an existing passage returns the
/// existing highlight unchanged.
pub fn add_highlight(library: &LibraryRoot, reading_id: &str, text: &str) -> Result<Highlight> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        bail!("highlight text is empty");
    }
    let mut highlights = list_highlights(library, reading_id)?;
    if let Some(existing) = highlights.iter().find(|h| h.text == trimmed) {
        return Ok(existing.clone());
    }
    let highlight = Highlight {
        id: new_id(),
        text: trimmed.to_string(),
    };
    highlights.push(highlight.clone());
    write(library, reading_id, &highlights)?;
    Ok(highlight)
}

/// Toggle a highlight by its text: if a highlight with this exact (trimmed)
/// text already exists it is removed and `false` is returned; otherwise it is
/// added and `true` is returned. This lets re-selecting an already-highlighted
/// passage clear it, and guarantees no duplicates.
pub fn toggle_highlight(library: &LibraryRoot, reading_id: &str, text: &str) -> Result<bool> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        bail!("highlight text is empty");
    }
    let mut highlights = list_highlights(library, reading_id)?;
    if let Some(pos) = highlights.iter().position(|h| h.text == trimmed) {
        highlights.remove(pos);
        if highlights.is_empty() {
            delete_all_highlights(library, reading_id)?;
        } else {
            write(library, reading_id, &highlights)?;
        }
        Ok(false)
    } else {
        highlights.push(Highlight {
            id: new_id(),
            text: trimmed.to_string(),
        });
        write(library, reading_id, &highlights)?;
        Ok(true)
    }
}

/// Remove the highlight with `highlight_id`. A no-op if it isn't present. When
/// the last highlight is removed, the now-empty file is deleted.
pub fn delete_highlight(library: &LibraryRoot, reading_id: &str, highlight_id: &str) -> Result<()> {
    let mut highlights = list_highlights(library, reading_id)?;
    let before = highlights.len();
    highlights.retain(|h| h.id != highlight_id);
    if highlights.len() == before {
        return Ok(());
    }
    if highlights.is_empty() {
        delete_all_highlights(library, reading_id)
    } else {
        write(library, reading_id, &highlights)
    }
}

/// Remove a reading's entire highlights file. Used when the reading itself is
/// deleted. A no-op if the file does not exist.
pub fn delete_all_highlights(library: &LibraryRoot, reading_id: &str) -> Result<()> {
    let path = library.highlights_path(reading_id);
    if path.is_file() {
        std::fs::remove_file(&path)?;
    }
    Ok(())
}

// ── Serialization ────────────────────────────────────────────────────────────

/// Render highlights as a Markdown document. Each highlight is a block quote
/// (one `> ` line per text line) terminated by `<!-- hl {id} -->`.
fn write(library: &LibraryRoot, reading_id: &str, highlights: &[Highlight]) -> Result<()> {
    // The highlights file lives inside the reading's folder; create it in case a
    // highlight is somehow saved before the article file exists.
    std::fs::create_dir_all(library.reading_dir(reading_id))?;
    let mut out = String::new();
    for h in highlights {
        if h.text.is_empty() {
            out.push_str(">\n");
        } else {
            for line in h.text.split('\n') {
                out.push_str("> ");
                out.push_str(line);
                out.push('\n');
            }
        }
        out.push_str("<!-- hl ");
        out.push_str(&h.id);
        out.push_str(" -->\n\n");
    }
    std::fs::write(library.highlights_path(reading_id), out)?;
    Ok(())
}

/// Parse the block-quote-plus-marker format produced by `write`. Lines starting
/// with `> ` (or a bare `>`) accumulate into the current highlight; an
/// `<!-- hl {id} -->` line closes it. Anything else (blank lines) is ignored.
/// Rendered text lines are always `> `-prefixed, so a quote whose own text
/// begins with `<!-- hl ` cannot be confused for a terminator.
fn parse(content: &str) -> Vec<Highlight> {
    let mut result = Vec::new();
    let mut buf: Vec<String> = Vec::new();
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("<!-- hl ") {
            let id = rest.trim_end_matches("-->").trim().to_string();
            if !id.is_empty() {
                result.push(Highlight {
                    id,
                    text: buf.join("\n"),
                });
            }
            buf.clear();
        } else if let Some(rest) = line.strip_prefix("> ") {
            buf.push(rest.to_string());
        } else if line == ">" {
            buf.push(String::new());
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;

    fn make_library(dir: &TempDir) -> LibraryRoot {
        fs::create_dir_all(dir.path().join("articles")).unwrap();
        LibraryRoot::new(dir.path()).unwrap()
    }

    #[test]
    fn missing_file_lists_empty() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        assert!(list_highlights(&lib, "no-such-reading").unwrap().is_empty());
    }

    #[test]
    fn add_then_list_roundtrips() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        let a = add_highlight(&lib, "r1", "first passage").unwrap();
        let b = add_highlight(&lib, "r1", "second passage").unwrap();

        let listed = list_highlights(&lib, "r1").unwrap();
        assert_eq!(listed, vec![a, b]);
    }

    #[test]
    fn preserves_multi_line_text() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let text = "line one\nline two\nline three";
        add_highlight(&lib, "r1", text).unwrap();

        let listed = list_highlights(&lib, "r1").unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].text, text);
    }

    #[test]
    fn empty_text_is_rejected() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        assert!(add_highlight(&lib, "r1", "   \n  ").is_err());
    }

    #[test]
    fn delete_removes_one_highlight() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let a = add_highlight(&lib, "r1", "keep me").unwrap();
        let b = add_highlight(&lib, "r1", "remove me").unwrap();

        delete_highlight(&lib, "r1", &b.id).unwrap();

        let listed = list_highlights(&lib, "r1").unwrap();
        assert_eq!(listed, vec![a]);
    }

    #[test]
    fn deleting_last_highlight_removes_file() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let a = add_highlight(&lib, "r1", "only one").unwrap();

        delete_highlight(&lib, "r1", &a.id).unwrap();

        assert!(!lib.highlights_path("r1").exists());
        assert!(list_highlights(&lib, "r1").unwrap().is_empty());
    }

    #[test]
    fn delete_unknown_id_is_noop() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let a = add_highlight(&lib, "r1", "stays").unwrap();

        delete_highlight(&lib, "r1", "not-a-real-id").unwrap();

        assert_eq!(list_highlights(&lib, "r1").unwrap(), vec![a]);
    }

    #[test]
    fn delete_all_clears_file() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        add_highlight(&lib, "r1", "one").unwrap();
        add_highlight(&lib, "r1", "two").unwrap();

        delete_all_highlights(&lib, "r1").unwrap();

        assert!(!lib.highlights_path("r1").exists());
    }

    #[test]
    fn adding_same_text_does_not_duplicate() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let first = add_highlight(&lib, "r1", "same passage").unwrap();
        // Re-adding (with surrounding whitespace, which is trimmed) returns the
        // existing highlight and does not create a second entry.
        let again = add_highlight(&lib, "r1", "  same passage  ").unwrap();

        assert_eq!(first, again);
        assert_eq!(list_highlights(&lib, "r1").unwrap(), vec![first]);
    }

    #[test]
    fn toggle_adds_then_removes_same_text() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);

        assert!(toggle_highlight(&lib, "r1", "a passage").unwrap());
        assert_eq!(list_highlights(&lib, "r1").unwrap().len(), 1);

        // Toggling the same text again removes it.
        assert!(!toggle_highlight(&lib, "r1", "a passage").unwrap());
        assert!(list_highlights(&lib, "r1").unwrap().is_empty());
        assert!(!lib.highlights_path("r1").exists());
    }

    #[test]
    fn toggle_off_keeps_other_highlights() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        let keep = add_highlight(&lib, "r1", "keep").unwrap();
        add_highlight(&lib, "r1", "drop").unwrap();

        assert!(!toggle_highlight(&lib, "r1", "drop").unwrap());

        assert_eq!(list_highlights(&lib, "r1").unwrap(), vec![keep]);
    }

    #[test]
    fn text_containing_marker_like_line_roundtrips() {
        let dir = TempDir::new().unwrap();
        let lib = make_library(&dir);
        // A quote whose text itself looks like the terminator must survive,
        // because rendered text lines are always `> `-prefixed.
        let text = "<!-- hl fake -->";
        add_highlight(&lib, "r1", text).unwrap();

        let listed = list_highlights(&lib, "r1").unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].text, text);
    }
}
