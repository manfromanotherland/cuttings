// SPDX-License-Identifier: MIT

use std::fs;

use anyhow::Result;

use crate::types::LibraryRoot;
use crate::writer::sha256_hex;

/// Download all `image_urls` into `assets/<id>/`, rewrite their occurrences in `markdown`
/// to relative paths, and return the updated Markdown.
///
/// On per-image download failure: leaves the remote URL intact and appends an HTML comment
/// `<!-- asset-fetch-failed: <url> -->` after the broken image reference so the failure
/// is visible and recoverable.
pub fn download_images(
    library: &LibraryRoot,
    id: &str,
    markdown: &str,
    image_urls: &[String],
) -> Result<String> {
    let assets_dir = library.assets_dir(id);
    fs::create_dir_all(&assets_dir)?;

    let mut result = markdown.to_string();

    for url in image_urls {
        match fetch_image(url) {
            Ok((bytes, ext)) => {
                let hash = sha256_hex(&bytes);
                let filename = format!("{hash}.{ext}");
                fs::write(assets_dir.join(&filename), &bytes)?;

                let rel = format!("../assets/{id}/{filename}");
                result = result.replace(url.as_str(), &rel);
            }
            Err(_) => {
                let marker = format!("\n<!-- asset-fetch-failed: {url} -->");
                result = result.replace(
                    &format!("]({url})"),
                    &format!("]({url}){marker}"),
                );
            }
        }
    }

    Ok(result)
}

fn fetch_image(url: &str) -> Result<(Vec<u8>, String)> {
    let resp = reqwest::blocking::get(url)?;
    let ext = ext_from_response(&resp, url);
    let bytes = resp.bytes()?.to_vec();
    Ok((bytes, ext))
}

fn ext_from_response(resp: &reqwest::blocking::Response, url: &str) -> String {
    if let Some(ct) = resp.headers().get("content-type") {
        if let Ok(s) = ct.to_str() {
            if let Some(ext) = content_type_to_ext(s) {
                return ext.to_string();
            }
        }
    }
    url_ext(url).unwrap_or_else(|| "bin".to_string())
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
    let ext = filename.rsplit('.').next()?;
    if ext.len() <= 5 && ext.chars().all(|c| c.is_ascii_alphanumeric()) {
        Some(ext.to_ascii_lowercase())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_ext_extracts_extension() {
        assert_eq!(url_ext("https://example.com/img/photo.jpg"), Some("jpg".to_string()));
        assert_eq!(url_ext("https://example.com/img/photo.JPG"), Some("jpg".to_string()));
        assert_eq!(url_ext("https://example.com/img/photo.jpg?size=large"), Some("jpg".to_string()));
        assert_eq!(url_ext("https://example.com/image"), None);
    }

    #[test]
    fn content_type_mapping() {
        assert_eq!(content_type_to_ext("image/jpeg"), Some("jpg"));
        assert_eq!(content_type_to_ext("image/png"), Some("png"));
        assert_eq!(content_type_to_ext("image/jpeg; charset=utf-8"), Some("jpg"));
        assert_eq!(content_type_to_ext("text/html"), None);
    }
}
