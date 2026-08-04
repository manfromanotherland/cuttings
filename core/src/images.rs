// SPDX-License-Identifier: MIT

use std::collections::HashSet;
use std::fs;

use anyhow::Result;

use crate::types::LibraryRoot;
use crate::writer::sha256_hex;

/// One image captured by the browser extension: the URL as it appears in the
/// Markdown, the `Content-Type` the browser saw, and the raw decoded bytes.
///
/// The extension fetches images from the page (reusing the browser's cache), so
/// the core never makes a network request — it only writes what it is handed.
pub struct ImageBytes {
    pub url: String,
    pub content_type: String,
    pub bytes: Vec<u8>,
}

/// Write each supplied image into the reading's `assets/` sub-folder and rewrite
/// its URL in the Markdown to the local relative path. Returns the updated
/// Markdown.
///
/// This performs no downloads: an image the extension could not capture is
/// simply absent from `images`, so its URL stays in the Markdown and the reader
/// shows a labelled placeholder. A single image that can't be written is skipped
/// rather than failing the whole save.
pub fn write_images(
    library: &LibraryRoot,
    id: &str,
    markdown: &str,
    images: &[ImageBytes],
) -> Result<String> {
    let assets_dir = library.assets_dir(id);
    fs::create_dir_all(&assets_dir)?;

    let mut result = markdown.to_string();
    let mut seen = HashSet::new();
    for image in images {
        // The same URL can be supplied more than once; write it only once.
        if !seen.insert(image.url.as_str()) {
            continue;
        }
        let hash = sha256_hex(&image.bytes);
        let ext = ext_for(&image.content_type, &image.url);
        let filename = format!("{hash}.{ext}");
        if fs::write(assets_dir.join(&filename), &image.bytes).is_ok() {
            // The article file (article.md) and its assets/ folder are siblings
            // inside the reading's folder, so the link is just `assets/<file>`.
            let rel = format!("assets/{filename}");
            result = result.replace(image.url.as_str(), &rel);
        }
    }
    Ok(result)
}

/// Choose a file extension from the `Content-Type`, falling back to the URL's
/// own extension, then `bin`.
fn ext_for(content_type: &str, url: &str) -> String {
    content_type_to_ext(content_type)
        .map(str::to_string)
        .or_else(|| url_ext(url))
        .unwrap_or_else(|| "bin".to_string())
}

fn content_type_to_ext(ct: &str) -> Option<&'static str> {
    match ct.split(';').next()?.trim() {
        "image/jpeg" | "image/jpg" => Some("jpg"),
        "image/png" => Some("png"),
        "image/gif" => Some("gif"),
        "image/webp" => Some("webp"),
        "image/svg+xml" => Some("svg"),
        "image/avif" => Some("avif"),
        _ => None,
    }
}

fn url_ext(url: &str) -> Option<String> {
    let path = url.split('?').next()?;
    let filename = path.rsplit('/').next()?;
    // rsplitn(2) gives [ext, stem]; if there's no dot we only get one part → None
    let mut parts = filename.rsplitn(2, '.');
    let ext = parts.next()?;
    parts.next()?; // require a stem before the dot
    if ext.len() <= 5 && ext.chars().all(|c| c.is_ascii_alphanumeric()) {
        Some(ext.to_ascii_lowercase())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn img(url: &str, content_type: &str, bytes: &[u8]) -> ImageBytes {
        ImageBytes {
            url: url.to_string(),
            content_type: content_type.to_string(),
            bytes: bytes.to_vec(),
        }
    }

    #[test]
    fn url_ext_extracts_extension() {
        assert_eq!(
            url_ext("https://example.com/img/photo.jpg"),
            Some("jpg".to_string())
        );
        assert_eq!(
            url_ext("https://example.com/img/photo.JPG"),
            Some("jpg".to_string())
        );
        assert_eq!(
            url_ext("https://example.com/img/photo.jpg?size=large"),
            Some("jpg".to_string())
        );
        assert_eq!(url_ext("https://example.com/image"), None);
    }

    #[test]
    fn content_type_mapping() {
        assert_eq!(content_type_to_ext("image/jpeg"), Some("jpg"));
        assert_eq!(content_type_to_ext("image/png"), Some("png"));
        assert_eq!(
            content_type_to_ext("image/jpeg; charset=utf-8"),
            Some("jpg")
        );
        assert_eq!(content_type_to_ext("text/html"), None);
    }

    #[test]
    fn ext_prefers_content_type_then_url_then_bin() {
        assert_eq!(ext_for("image/png", "https://e.com/x"), "png");
        assert_eq!(ext_for("", "https://e.com/x.gif"), "gif");
        assert_eq!(
            ext_for("application/octet-stream", "https://e.com/x"),
            "bin"
        );
    }

    #[test]
    fn writes_asset_and_rewrites_markdown() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "TESTID";
        let url = "https://e.com/a.png";
        let bytes = b"\x89PNG\r\n\x1a\npixels";
        let markdown = format!("![alt]({url})");

        let out = write_images(&library, id, &markdown, &[img(url, "image/png", bytes)]).unwrap();

        assert!(!out.contains(url), "remote URL should be replaced: {out}");
        assert!(out.contains("assets/"), "got: {out}");
        assert!(
            !out.contains("../"),
            "link is relative to the article file (no ../): {out}"
        );

        // The written file's name is the sha256 of the bytes plus the extension.
        let expected = format!("{}.png", sha256_hex(bytes));
        let path = library.assets_dir(id).join(&expected);
        assert!(path.exists(), "asset {expected} not written");
        assert_eq!(fs::read(&path).unwrap(), bytes);
    }

    #[test]
    fn duplicate_url_is_written_once() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "DUP";
        let url = "https://e.com/a.png";
        let bytes = b"samebytes";
        let images = vec![img(url, "image/png", bytes), img(url, "image/png", bytes)];

        write_images(&library, id, &format!("![a]({url})"), &images).unwrap();

        let count = fs::read_dir(library.assets_dir(id)).unwrap().count();
        assert_eq!(count, 1, "the repeated URL should produce one asset");
    }

    #[test]
    fn missing_image_keeps_remote_url_as_placeholder() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "MISS";
        let url = "https://e.com/not-supplied.png";
        let markdown = format!("![a]({url})");

        // No bytes supplied for the URL → it stays remote.
        let out = write_images(&library, id, &markdown, &[]).unwrap();
        assert_eq!(out, markdown);
    }
}
