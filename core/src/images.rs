// SPDX-License-Identifier: MIT

use std::fs;

use anyhow::Result;

use crate::types::LibraryRoot;
use crate::writer::sha256_hex;

/// Download all `image_urls` into `assets/<id>/`, rewrite their occurrences in `markdown`
/// to relative paths, and return the updated Markdown.
///
/// This save-time fetch is the only attempt made for an image. On per-image download
/// failure the remote URL is left untouched in the Markdown — the reference and its alt
/// text survive so the reader can show a labelled placeholder — and the image is never
/// fetched again.
pub fn download_images(
    library: &LibraryRoot,
    id: &str,
    markdown: &str,
    image_urls: &[String],
) -> Result<String> {
    let assets_dir = library.assets_dir(id);
    fs::create_dir_all(&assets_dir)?;

    let client = image_client()?;
    let mut result = markdown.to_string();

    for url in image_urls {
        // The save-time fetch is the only attempt. If it fails, the remote URL is
        // left as-is in the Markdown and the image is not downloaded later.
        if let Ok((bytes, ext)) = fetch_image(&client, url) {
            let hash = sha256_hex(&bytes);
            let filename = format!("{hash}.{ext}");
            fs::write(assets_dir.join(&filename), &bytes)?;

            let rel = format!("../assets/{id}/{filename}");
            result = result.replace(url.as_str(), &rel);
        }
    }

    Ok(result)
}

/// The `User-Agent` sent with every image request.
///
/// It must be non-empty and identifiable: some hosts — notably Wikimedia's
/// `upload.wikimedia.org`, which serves every Wikipedia article image — reject
/// requests without one with `403 Forbidden`. The version is taken from the
/// crate version so the User-Agent and the release never drift.
const USER_AGENT: &str = concat!("ReadControl/", env!("CARGO_PKG_VERSION"));

/// Build the HTTP client used for image downloads.
fn image_client() -> Result<reqwest::blocking::Client> {
    Ok(reqwest::blocking::Client::builder()
        .user_agent(USER_AGENT)
        .build()?)
}

fn fetch_image(client: &reqwest::blocking::Client, url: &str) -> Result<(Vec<u8>, String)> {
    // `error_for_status` turns a non-2xx response (e.g. a 403 or 404) into an
    // `Err` so the caller keeps the remote URL in the Markdown as a labelled
    // placeholder, rather than saving the error page's body as a broken asset.
    let resp = client.get(url).send()?.error_for_status()?;
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

    // A non-empty, identifiable User-Agent is what stops hosts like Wikimedia
    // from answering image requests with `403 Forbidden`, so pin its shape and
    // tie it to the crate version (its single source of truth).
    #[test]
    fn user_agent_is_identifiable_and_versioned() {
        let version = USER_AGENT
            .strip_prefix("ReadControl/")
            .expect("User-Agent must identify the client as ReadControl");
        assert!(!version.is_empty(), "User-Agent must carry a version");
        assert_eq!(version, env!("CARGO_PKG_VERSION"));
    }

    // A non-2xx response must surface as an `Err` so `download_images` keeps the
    // remote URL as a labelled placeholder instead of saving the error body as a
    // broken asset. Served from a one-shot loopback server so the test is
    // hermetic and needs no network.
    #[test]
    fn fetch_image_treats_non_success_status_as_failure() {
        use std::io::{Read, Write};
        use std::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let _ = stream.read(&mut [0u8; 1024]);
                let body = "forbidden";
                let resp = format!(
                    "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\n\
                     Content-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = stream.write_all(resp.as_bytes());
            }
        });

        // Bypass any ambient proxy so the request reaches the loopback server.
        let client = reqwest::blocking::Client::builder()
            .no_proxy()
            .build()
            .unwrap();
        let result = fetch_image(&client, &format!("http://{addr}/img.png"));
        assert!(
            result.is_err(),
            "a 403 response must be treated as a failure"
        );

      