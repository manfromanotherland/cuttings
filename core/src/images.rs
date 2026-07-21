// SPDX-License-Identifier: MIT

use std::collections::HashSet;
use std::fs;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use anyhow::Result;

use crate::types::LibraryRoot;
use crate::writer::sha256_hex;

/// Images are fetched on at most this many worker threads at once. A page can
/// reference dozens of images; downloading them serially makes a save needlessly
/// slow and widens the window in which the batch could be interrupted.
const MAX_CONCURRENCY: usize = 8;

/// Caps on a single request so one stalled connection can never hang the save.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// A single image is attempted up to this many times. Transient failures
/// (timeouts, connection resets, 429/5xx) are retried with a short backoff so a
/// momentary blip doesn't permanently drop the image.
const MAX_ATTEMPTS: u32 = 3;
const RETRY_BACKOFF: Duration = Duration::from_millis(250);

/// Download every image referenced by the Markdown into `assets/<id>/`, rewrite
/// each URL to its local relative path, and return the updated Markdown.
///
/// Every distinct URL is fetched — with retries, concurrently across a small
/// thread pool — and all of those fetches complete before this function returns,
/// so the process never moves on (or exits) with downloads still outstanding. On
/// per-image failure (after retries) the remote URL is left untouched in the
/// Markdown, so the reference and its alt text survive as a labelled placeholder.
pub fn download_images(
    library: &LibraryRoot,
    id: &str,
    markdown: &str,
    image_urls: &[String],
) -> Result<String> {
    let assets_dir = library.assets_dir(id);
    fs::create_dir_all(&assets_dir)?;

    // The same image often appears many times on a page (repeated icons, a figure
    // shown twice); fetch each distinct URL only once.
    let unique = dedup_urls(image_urls);
    let client = image_client()?;

    // (url → local relative path) for every image that downloaded successfully.
    // Populated by the workers; the Markdown string edits happen afterwards on a
    // single thread so they can't race.
    let downloaded: Mutex<Vec<(&str, String)>> = Mutex::new(Vec::new());
    let next = AtomicUsize::new(0);

    // Scoped threads borrow `unique`, `client`, `downloaded`, … from this frame.
    // `scope` joins every worker before returning — that join is what guarantees
    // all downloads have finished by the time we rewrite the Markdown below.
    std::thread::scope(|scope| {
        for _ in 0..unique.len().min(MAX_CONCURRENCY) {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                let Some(&url) = unique.get(i) else { break };
                if let Ok((bytes, ext)) = fetch_image(&client, url) {
                    let hash = sha256_hex(&bytes);
                    let filename = format!("{hash}.{ext}");
                    // A single image that can't be written is skipped rather than
                    // failing the whole save; its remote URL stays in the Markdown.
                    if fs::write(assets_dir.join(&filename), &bytes).is_ok() {
                        let rel = format!("../assets/{id}/{filename}");
                        downloaded.lock().unwrap().push((url, rel));
                    }
                }
            });
        }
    });

    let mut result = markdown.to_string();
    for (url, rel) in downloaded.into_inner().unwrap() {
        result = result.replace(url, &rel);
    }
    Ok(result)
}

/// Distinct URLs in first-seen order.
fn dedup_urls(urls: &[String]) -> Vec<&str> {
    let mut seen = HashSet::new();
    urls.iter()
        .map(String::as_str)
        .filter(|u| seen.insert(*u))
        .collect()
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
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
        .build()?)
}

/// Fetch one image, retrying transient failures with a short backoff.
fn fetch_image(client: &reqwest::blocking::Client, url: &str) -> Result<(Vec<u8>, String)> {
    let mut attempt = 1;
    loop {
        match try_fetch_image(client, url) {
            Ok(image) => return Ok(image),
            Err(e) => {
                if attempt >= MAX_ATTEMPTS || !is_retryable(&e) {
                    return Err(e.into());
                }
                std::thread::sleep(RETRY_BACKOFF * attempt);
                attempt += 1;
            }
        }
    }
}

/// A single fetch attempt. `error_for_status` turns a non-2xx response (e.g. a
/// 403 or 404) into an `Err` so a failed fetch keeps the remote URL in the
/// Markdown rather than saving the error page's body as a broken asset.
fn try_fetch_image(
    client: &reqwest::blocking::Client,
    url: &str,
) -> reqwest::Result<(Vec<u8>, String)> {
    let resp = client.get(url).send()?.error_for_status()?;
    let ext = ext_from_response(&resp, url);
    let bytes = resp.bytes()?.to_vec();
    Ok((bytes, ext))
}

/// Whether a failed attempt is worth retrying: transport errors (no HTTP status —
/// timeout, connection reset, DNS) and the transient HTTP codes 429 and 5xx. A
/// 4xx other than 429 is a permanent client error and is not retried.
fn is_retryable(e: &reqwest::Error) -> bool {
    match e.status() {
        Some(status) => {
            status == reqwest::StatusCode::TOO_MANY_REQUESTS || status.is_server_error()
        }
        None => true,
    }
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
    use std::io::{Read, Write};
    use std::net::TcpListener;

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

    #[test]
    fn dedup_urls_keeps_first_seen_order_without_repeats() {
        let urls = vec![
            "https://e.com/a.png".to_string(),
            "https://e.com/b.png".to_string(),
            "https://e.com/a.png".to_string(),
        ];
        assert_eq!(
            dedup_urls(&urls),
            vec!["https://e.com/a.png", "https://e.com/b.png"]
        );
    }

    #[test]
    fn is_retryable_only_for_transient_failures() {
        // 5xx and 429 are transient and retried; other 4xx are permanent.
        assert!(is_retryable(&status_error("503 Service Unavailable")));
        assert!(is_retryable(&status_error("429 Too Many Requests")));
        assert!(!is_retryable(&status_error("404 Not Found")));
        assert!(!is_retryable(&status_error("403 Forbidden")));
    }

    // A `reqwest::Error` whose `.status()` is the given code, produced by hitting
    // a one-shot loopback server (there is no public constructor for these).
    fn status_error(status_line: &'static str) -> reqwest::Error {
        let url = serve_once(status_line, b"x".to_vec(), "text/plain");
        no_proxy_client()
            .get(&url)
            .send()
            .unwrap()
            .error_for_status()
            .expect_err("status line was a non-success code")
    }

    #[test]
    fn fetch_image_treats_permanent_4xx_as_failure() {
        // A 403 is not retryable, so the single scripted response is enough.
        let url = serve_once("403 Forbidden", b"forbidden".to_vec(), "text/html");
        let result = fetch_image(&no_proxy_client(), &url);
        assert!(
            result.is_err(),
            "a 403 response must be treated as a failure"
        );
    }

    #[test]
    fn fetch_image_retries_transient_failure_then_succeeds() {
        // Two 503s followed by a real image: fetch_image must ride through the
        // transient failures (MAX_ATTEMPTS == 3) and return the final bytes.
        let png = b"\x89PNG\r\n\x1a\npixels".to_vec();
        let responses = vec![
            ("503 Service Unavailable", b"busy".to_vec(), "text/plain"),
            ("503 Service Unavailable", b"busy".to_vec(), "text/plain"),
            ("200 OK", png.clone(), "image/png"),
        ];
        let url = serve_scripted(responses);
        let (bytes, ext) =
            fetch_image(&no_proxy_client(), &url).expect("should succeed by attempt 3");
        assert_eq!(bytes, png);
        assert_eq!(ext, "png");
    }

    #[test]
    fn download_images_writes_asset_and_rewrites_markdown() {
        let png = b"\x89PNG\r\n\x1a\npixels".to_vec();
        let url = serve_once("200 OK", png.clone(), "image/png");
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "TESTID";
        let markdown = format!("![alt]({url})");

        let out = download_images(&library, id, &markdown, &[url.clone(), url.clone()]).unwrap();

        assert!(
            out.contains(&format!("../assets/{id}/")),
            "URL should be rewritten to a local asset path, got: {out}"
        );
        assert!(!out.contains(&url), "the remote URL should be gone: {out}");

        let assets: Vec<_> = fs::read_dir(library.assets_dir(id))
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert_eq!(assets.len(), 1, "the duplicate URL should be fetched once");
        assert_eq!(fs::read(assets[0].path()).unwrap(), png);
    }

    fn no_proxy_client() -> reqwest::blocking::Client {
        // Bypass any ambient proxy so requests reach the loopback server.
        reqwest::blocking::Client::builder()
            .no_proxy()
            .build()
            .unwrap()
    }

    /// Serve a single scripted HTTP response on a fresh loopback port and return
    /// its URL. The server thread is detached; it exits after one connection.
    fn serve_once(status_line: &'static str, body: Vec<u8>, content_type: &'static str) -> String {
        serve_scripted(vec![(status_line, body, content_type)])
    }

    /// Serve each `(status, body, content-type)` in order — one per connection —
    /// then stop. Returns the URL clients should hit.
    fn serve_scripted(responses: Vec<(&'static str, Vec<u8>, &'static str)>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            for (status_line, body, content_type) in responses {
                let Ok((mut stream, _)) = listener.accept() else {
                    return;
                };
                let _ = stream.read(&mut [0u8; 1024]);
                let head = format!(
                    "HTTP/1.1 {status_line}\r\nContent-Type: {content_type}\r\n\
                     Content-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                );
                let _ = stream.write_all(head.as_bytes());
                let _ = stream.write_all(&body);
            }
        });
        format!("http://{addr}/img.png")
    }
}
