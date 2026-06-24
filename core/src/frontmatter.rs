// SPDX-License-Identifier: MIT

use anyhow::{anyhow, Result};

use crate::types::{Metadata, Reading};

/// Parse a reading from a file's raw text content.
///
/// Expected format:
/// ```text
/// ---
/// <YAML frontmatter>
/// ---
///
/// <Markdown body>
/// ```
pub fn parse_reading(content: &str) -> Result<Reading> {
    let rest = content
        .strip_prefix("---\n")
        .ok_or_else(|| anyhow!("missing opening frontmatter fence"))?;

    let close = rest
        .find("\n---\n")
        .ok_or_else(|| anyhow!("missing closing frontmatter fence"))?;

    let yaml_str = &rest[..close];
    let after_fence = &rest[close + 5..]; // skip "\n---\n"
    let body = after_fence.trim_start_matches('\n').to_string();

    // Parse once into a generic value so we can read any legacy `read: true`
    // flag from files written before `read_at` existed, then into Metadata.
    let value: serde_yaml::Value =
        serde_yaml::from_str(yaml_str).map_err(|e| anyhow!("invalid frontmatter: {e}"))?;
    let legacy_read = value.get("read").and_then(|v| v.as_bool()).unwrap_or(false);

    let mut metadata: Metadata =
        serde_yaml::from_value(value).map_err(|e| anyhow!("invalid frontmatter: {e}"))?;

    // Forward-migrate the dropped `read` boolean: a legacy read article with no
    // `read_at` is treated as read at its save time. The next write drops the
    // `read` key entirely (it is no longer part of Metadata).
    if metadata.read_at.is_none() && legacy_read {
        metadata.read_at = Some(metadata.saved_at.clone());
    }

    Ok(Reading { metadata, body })
}

/// Render a reading back to its on-disk text format.
pub fn render_reading(reading: &Reading) -> Result<String> {
    let yaml = serde_yaml::to_string(&reading.metadata)
        .map_err(|e| anyhow!("frontmatter serialization failed: {e}"))?;

    let body = reading.body.trim_end_matches('\n').to_string() + "\n";
    Ok(format!("---\n{}---\n\n{body}", yaml))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Metadata;
    use proptest::prelude::*;

    fn sample_metadata(read: bool, archived: bool, favorite: bool) -> Metadata {
        Metadata {
            format_version: 1,
            id: "01J9Z8X7Q2VBKN3P4HXYZ01AB".to_string(),
            url: "https://example.com/article".to_string(),
            canonical_url: "https://example.com/article".to_string(),
            title: "Test Article".to_string(),
            author: Some("Jane Doe".to_string()),
            site: Some("example.com".to_string()),
            saved_at: "2026-06-13T15:00:00Z".to_string(),
            read_at: read.then(|| "2026-06-13T16:00:00.000Z".to_string()),
            archived,
            favorite,
            rating: 0,
            tags: vec!["rust".to_string(), "local-first".to_string()],
            excerpt: Some("A short excerpt.".to_string()),
            word_count: Some(1234),
            lang: Some("en".to_string()),
            source_hash: "sha256:abc123".to_string(),
        }
    }

    #[test]
    fn round_trip_full() {
        let meta = sample_metadata(false, false, true);
        let reading = Reading {
            metadata: meta.clone(),
            body: "# Test Article\n\nBody paragraph.\n".to_string(),
        };
        let rendered = render_reading(&reading).unwrap();
        let parsed = parse_reading(&rendered).unwrap();
        assert_eq!(parsed.metadata, meta);
        assert_eq!(parsed.body.trim(), reading.body.trim());
    }

    #[test]
    fn round_trip_optional_fields_absent() {
        let mut meta = sample_metadata(true, false, false);
        meta.author = None;
        meta.site = None;
        meta.excerpt = None;
        meta.word_count = None;
        meta.lang = None;

        let reading = Reading {
            metadata: meta.clone(),
            body: "# Minimal\n".to_string(),
        };
        let rendered = render_reading(&reading).unwrap();
        let parsed = parse_reading(&rendered).unwrap();
        assert_eq!(parsed.metadata, meta);
    }

    #[test]
    fn legacy_read_true_migrates_to_read_at() {
        // A file written before `read_at` existed: it carries `read: true` and
        // no `read_at`. Parsing must treat it as read, stamped at save time.
        let content = "\
---
format_version: 1
id: 01J9Z8X7Q2VBKN3P4HXYZ01AB
url: https://example.com/article
canonical_url: https://example.com/article
title: Old Article
saved_at: 2026-06-13T15:00:00Z
read: true
archived: false
favorite: false
tags: []
source_hash: sha256:abc
---

Body.
";
        let parsed = parse_reading(content).unwrap();
        assert_eq!(
            parsed.metadata.read_at.as_deref(),
            Some("2026-06-13T15:00:00Z")
        );
    }

    #[test]
    fn legacy_read_false_stays_unread() {
        let content = "\
---
format_version: 1
id: 01J9Z8X7Q2VBKN3P4HXYZ01AB
url: https://example.com/article
canonical_url: https://example.com/article
title: Old Article
saved_at: 2026-06-13T15:00:00Z
read: false
archived: false
favorite: false
tags: []
source_hash: sha256:abc
---

Body.
";
        let parsed = parse_reading(content).unwrap();
        assert_eq!(parsed.metadata.read_at, None);
    }

    proptest! {
        #[test]
        fn bool_fields_round_trip(
            read in proptest::bool::ANY,
            archived in proptest::bool::ANY,
            favorite in proptest::bool::ANY,
            word_count in proptest::option::of(0u32..100_000u32),
        ) {
            let mut meta = sample_metadata(read, archived, favorite);
            meta.word_count = word_count;

            let reading = Reading {
                metadata: meta.clone(),
                body: "# Test\n\nBody.\n".to_string(),
            };
            let rendered = render_reading(&reading).unwrap();
            let parsed = parse_reading(&rendered).unwrap();

            prop_assert_eq!(parsed.metadata.read_at, meta.read_at);
            prop_assert_eq!(parsed.metadata.archived, meta.archived);
            prop_assert_eq!(parsed.metadata.favorite, meta.favorite);
            prop_assert_eq!(parsed.metadata.word_count, meta.word_count);
        }
    }
}
