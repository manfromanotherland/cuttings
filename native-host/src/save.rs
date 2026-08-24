// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use anyhow::{bail, Result};
use base64::Engine;
use cuttings_core::{
    find_by_url, url_id, write_images, write_reading, ImageBytes, LibraryRoot, Metadata,
};

use crate::protocol::{SaveRequest, SaveResponse, PROTOCOL_VERSION};

pub fn handle(req: SaveRequest) -> Result<SaveResponse> {
    if req.protocol_version != PROTOCOL_VERSION {
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
                "No library folder has been set. Open the Cuttings app to configure one.",
            ))
        }
    };
    let library = LibraryRoot::new(&library_path)?;

    // The id is content-addressed: SHA256 of the normalized *visited* URL. This
    // is both the dedup key and the filename stem.
    let id = match url_id(&req.metadata.url) {
        Ok(id) => id,
        Err(_) => {
            return Ok(SaveResponse::error(
                "invalid_request",
                &format!("could not parse url: {}", req.metadata.url),
            ))
        }
    };

    // Duplicate check — a single stat on the content-addressed path.
    if let Some(existing_id) = find_by_url(&library, &req.metadata.url)? {
        return Ok(SaveResponse::error(
            "duplicate",
            &format!("A reading with this URL already exists (id: {existing_id})"),
        ));
    }

    // Decode the image bytes the extension captured. An image whose base64 won't
    // decode is skipped, so its URL stays in the Markdown as a placeholder.
    let images: Vec<ImageBytes> = req
        .images
        .iter()
        .filter_map(|img| {
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(&img.data_base64)
                .ok()?;
            Some(ImageBytes {
                url: img.url.clone(),
                content_type: img.content_type.clone(),
                bytes,
            })
        })
        .collect();

    // Write the supplied images and rewrite their links. The host never downloads.
    let markdown = write_images(&library, &id, &req.markdown, &images)?;

    let metadata = Metadata {
        format_version: 1,
        id: id.clone(),
        url: req.metadata.url,
        canonical_url: req.metadata.canonical_url,
        title: req.metadata.title,
        author: req.metadata.author,
        site: req.metadata.site,
        saved_at: req.metadata.saved_at,
        read_at: None,
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

    // Report the article's path relative to the library root (per-reading
    // folder, e.g. articles/8f/<id>/article.md).
    let article_path = library.article_path(&id);
    let path = article_path
        .strip_prefix(library.path())
        .unwrap_or(&article_path)
        .to_string_lossy()
        .into_owned();
    Ok(SaveResponse::success(id, path))
}

/// Classify an anyhow error into a protocol error code + message.
pub fn classify_error(e: &anyhow::Error) -> (&'static str, String) {
    ("io_error", e.to_string())
}

pub(crate) fn find_library_path() -> Result<PathBuf> {
    if let Ok(path) = std::env::var("CUTTINGS_LIBRARY") {
        return Ok(PathBuf::from(path));
    }

    let home = std::env::var("HOME")?;
    let config_file = PathBuf::from(home).join(".config/cuttings/library");
    if config_file.is_file() {
        let path = std::fs::read_to_string(config_file)?.trim().to_string();
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }

    bail!("library_not_configured")
}
