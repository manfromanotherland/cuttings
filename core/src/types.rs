// SPDX-License-Identifier: MIT

use std::path::{Path, PathBuf};

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

/// All YAML frontmatter fields for a saved reading.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Metadata {
    pub format_version: u32,
    pub id: String,
    pub url: String,
    pub canonical_url: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub site: Option<String>,
    pub saved_at: String,
    /// UTC ISO-8601 timestamp (millisecond precision, `Z` suffix — same format
    /// as `saved_at`) of the most recent time the reading was marked read.
    /// `None` means unread: presence of this field *is* the read state, so there
    /// is no separate `read` boolean.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub read_at: Option<String>,
    pub archived: bool,
    pub favorite: bool,
    /// Star rating 0–5, where 0 means unrated. Defaults to 0 for articles
    /// saved before ratings existed (field absent from older frontmatter).
    #[serde(default)]
    pub rating: u8,
    pub tags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub excerpt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub word_count: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lang: Option<String>,
    pub source_hash: String,
}

/// A parsed article: its frontmatter metadata plus the Markdown body.
#[derive(Debug, Clone)]
pub struct Reading {
    pub metadata: Metadata,
    pub body: String,
}

/// A validated path to the user's library folder.
pub struct LibraryRoot(PathBuf);

impl LibraryRoot {
    pub fn new(path: impl Into<PathBuf>) -> Result<Self> {
        let path = path.into();
        if !path.is_dir() {
            bail!("library root is not a directory: {}", path.display());
        }
        Ok(Self(path))
    }

    pub fn path(&self) -> &Path {
        &self.0
    }

    pub fn articles_dir(&self) -> PathBuf {
        self.0.join("articles")
    }

    pub fn assets_dir(&self, id: &str) -> PathBuf {
        self.0.join("assets").join(id)
    }

    pub fn article_path(&self, id: &str) -> PathBuf {
        self.articles_dir().join(format!("{id}.md"))
    }

    pub fn highlights_dir(&self) -> PathBuf {
        self.0.join("highlights")
    }

    pub fn highlights_path(&self, id: &str) -> PathBuf {
        self.highlights_dir().join(format!("{id}.md"))
    }
}
