// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use anyhow::{bail, Result};
use base64::Engine;
use cuttings_core::{
    save_capture, ImageBytes, LibraryRoot, ReadingKind, SaveDisposition, SaveError, SaveInput,
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
    if req.metadata.kind == ReadingKind::Video {
        return Ok(SaveResponse::error(
            "invalid_request",
            "browser video saves require the streaming video import",
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

    // Decode the image bytes the extension captured. An image whose base64 won't
    // decode is skipped, so its URL stays in the Markdown as a placeholder.
    let images = decode_images(&req.images);

    let outcome = match save_capture(
        &library,
        SaveInput {
            quote_identity_markdown: None,
            kind: req.metadata.kind,
            lightweight: false,
            url: req.metadata.url,
            media_url: req.metadata.media_url,
            canonical_url: req.metadata.canonical_url,
            title: req.metadata.title,
            author: req.metadata.author,
            site: req.metadata.site,
            saved_at: req.metadata.saved_at,
            markdown: req.markdown,
            images,
            preview_url: req.preview_url,
            favicon_url: req.favicon_url,
            excerpt: req.metadata.excerpt,
            word_count: req.metadata.word_count,
            lang: req.metadata.lang,
        },
    ) {
        Ok(outcome) => outcome,
        Err(SaveError::InvalidRequest(message)) => {
            return Ok(SaveResponse::error("invalid_request", &message));
        }
        Err(SaveError::Storage(error)) => return Err(error),
    };

    if outcome.disposition == SaveDisposition::Duplicate {
        return Ok(SaveResponse::error(
            "duplicate",
            &format!("This reading already exists (id: {})", outcome.id),
        ));
    }

    Ok(SaveResponse::success(outcome.id, outcome.path))
}

pub(crate) fn decode_images(images: &[crate::protocol::RequestImage]) -> Vec<ImageBytes> {
    images
        .iter()
        .filter_map(|image| {
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(&image.data_base64)
                .ok()?;
            Some(ImageBytes {
                url: image.url.clone(),
                content_type: image.content_type.clone(),
                bytes,
            })
        })
        .collect()
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
