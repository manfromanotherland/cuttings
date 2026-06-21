// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use anyhow::{bail, Result};
use read_later_core::{
    download_images, find_duplicate, new_id, write_reading, LibraryRoot, Metadata,
};

use crate::protocol::{SaveRequest, SaveResponse};

pub fn handle(req: SaveRequest) -> Result<SaveResponse> {
    if req.protocol_version != 1 {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unsupported protocol_version: {}", req.protocol_version),
        ));
    }
    if req.action != "save" {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unknown action: {}", req.action),
        ));
    }

    let library_path = match find_library_path() {
        Ok(p) => p,
        Err(_) => {
            return Ok(SaveResponse::error(
                "library_not_configured",
                "No library folder has been set. Open the read-later app to configure one.",
            ))
        }
    };
    let library = LibraryRoot::new(&library_path)?;

    // Duplicate check
    if let Some(existing_id) = find_duplicate(&library, &req.metadata.canonical_url)? {
        return Ok(SaveResponse::error(
            "duplicate",
            &format!("A reading with this URL already exists (id: {existing_id})"),
        ));
    }

    let id = new_id();

    // Download images and rewrite markdown links
    let markdown = download_images(&library, &id, &req.markdown, &req.image_urls)?;

    let metadata = Metadata {
        format_version: 1,
        id: id.clone(),
        url: req.metadata.url,
        canonical_url: req.metadata.canonical_url,
        title: req.metadata.title,
        author: req.metadata.author,
        site: req.metadata.site,
        saved_at: req.metadata.saved_at,
        read: false,
        archived: false,
        favorite: false,
        rating: 0,
        tags: vec![],
        excerpt: req.metadata.excerpt,
        word_count: req.metadata.word_count,
        lang: req.metadata.lang,
        source_hash: String::new(), // set by write_reading
    };

    write_reading(&library, metadata, markdown)?;

    let path = format!("articles/{id}.md");
    Ok(SaveResponse::success(id, path))
}

/// Classify an anyhow error into a protocol error code + message.
pub fn classify_error(e: &anyhow::Error) -> (&'static str, String) {
    ("io_error", e.to_string())
}

pub(crate) fn find_library_path() -> Result<PathBuf> {
    if let Ok(path) = std::env::var("READ_LATER_LIBRARY") {
        return Ok(PathBuf::from(path));
    }

    let home = std::env::var("HOME")?;
    let config_file = PathBuf::from(home).join(".config/read-later/library");
    if config_file.is_file() {
        let path = std::fs::read_to_string(config_file)?.trim().to_string();
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }

    bail!("library_not_configured")
}
