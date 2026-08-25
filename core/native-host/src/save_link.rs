// SPDX-License-Identifier: MIT

use anyhow::Result;
use cuttings_core::{save_link_capture, LibraryRoot, SaveDisposition, SaveError, SaveLinkInput};

use crate::{
    protocol::{SaveLinkRequest, SaveResponse, PROTOCOL_VERSION},
    save::{decode_images, find_library_path},
};

pub fn handle(request: SaveLinkRequest) -> Result<SaveResponse> {
    if request.protocol_version != PROTOCOL_VERSION {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unsupported protocol_version: {}", request.protocol_version),
        ));
    }
    if request.action != "save_link" {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unknown action: {}", request.action),
        ));
    }
    if request.metadata.kind != cuttings_core::ReadingKind::Article {
        return Ok(SaveResponse::error(
            "invalid_request",
            "save_link requires article metadata",
        ));
    }

    let library_path = match find_library_path() {
        Ok(path) => path,
        Err(_) => {
            return Ok(SaveResponse::error(
                "library_not_configured",
                "No library folder has been set. Open the Cuttings app to configure one.",
            ))
        }
    };
    let library = LibraryRoot::new(&library_path)?;
    let images = decode_images(&request.images);

    let outcome = match save_link_capture(
        &library,
        SaveLinkInput {
            url: request.metadata.url,
            canonical_url: request.metadata.canonical_url,
            title: request.metadata.title,
            author: request.metadata.author,
            site: request.metadata.site,
            saved_at: request.metadata.saved_at,
            images,
            preview_url: request.preview_url,
            favicon_url: request.favicon_url,
            theme_color: request.metadata.theme_color,
            excerpt: request.metadata.excerpt,
            lang: request.metadata.lang,
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
