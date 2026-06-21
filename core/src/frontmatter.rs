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

    let metadata: Metadata =
        serde_yaml::from_str(yaml_str).map_err(|e| anyhow!("invalid frontmatter: {e}"))?;

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
            read,
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

            prop_assert_eq!(parsed.metadata.read, meta.read);
            prop_assert_eq!(parsed.metadata.archived, meta.archived);
            prop_assert_eq!(parsed.metadata.favorite, meta.favorite);
            prop_assert_eq!(parsed.metadata.word_count, meta.word_count);
        }
    }
}
