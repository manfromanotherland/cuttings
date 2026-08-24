// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use anyhow::{bail, Result};
use base64::Engine;
use cuttings_core::{
    find_by_media, find_by_url, first_local_image_asset, media_id, quote_id, url_id, write_images,
    write_reading, ImageBytes, LibraryRoot, Metadata, ReadingKind,
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

    // Articles retain their original URL-only identity. Media includes its
    // clicked URL; quotes include their normalized selected Markdown.
    let id_result = match req.metadata.kind {
        ReadingKind::Article => url_id(&req.metadata.url),
        ReadingKind::Image | ReadingKind::Video => match req.metadata.media_url.as_deref() {
            Some(media_url) => media_id(req.metadata.kind, &req.metadata.url, media_url),
            None => {
                return Ok(SaveResponse::error(
                    "invalid_request",
                    "image and video saves require metadata.media_url",
                ))
            }
        },
        ReadingKind::Quote => quote_id(&req.metadata.url, &req.markdown),
    };
    let id = match id_result {
        Ok(id) => id,
        Err(error) => {
            return Ok(SaveResponse::error(
                "invalid_request",
                &format!("could not derive reading id: {error}"),
            ))
        }
    };

    // Duplicate check — a single stat on the content-addressed path.
    let existing_id = match req.metadata.kind {
        ReadingKind::Article => find_by_url(&library, &req.metadata.url)?,
        ReadingKind::Image | ReadingKind::Video => find_by_media(
            &library,
            req.metadata.kind,
            &req.metadata.url,
            req.metadata.media_url.as_deref().expect("validated above"),
        )?,
        ReadingKind::Quote => library.article_path(&id).is_file().then(|| id.clone()),
    };
    if let Some(existing_id) = existing_id {
        return Ok(SaveResponse::error(
            "duplicate",
            &format!("This reading already exists (id: {existing_id})"),
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
    let preview_asset = first_local_image_asset(&markdown);

    let metadata = Metadata {
        format_version: 1,
        id: id.clone(),
        kind: req.metadata.kind,
        url: req.metadata.url,
        media_url: req.metadata.media_url,
        preview_asset,
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
