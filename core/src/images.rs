// SPDX-License-Identifier: MIT

use std::collections::HashSet;
use std::fs;
use std::time::Duration;

use anyhow::{anyhow, Result};

use crate::types::LibraryRoot;
use crate::writer::sha256_hex;

/// Caps on a single request so one stalled connection can never hang the save.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// A single image is attempted up to this many times before it is given up on.
const MAX_ATTEMPTS: u32 = 4;

/// Backoff for a transient failure that carries no `Retry-After` hint. Grows per
/// attempt (500ms, 1s, 1.5s, …).
const BASE_BACKOFF: Duration = Duration::from_millis(500);

/// Upper bound on how long we'll wait between attempts, even if a server asks for
/// more via `Retry-After`. Keeps a hostile/broken hint from stalling the save.
const MAX_BACKOFF: Duration = Duration::from_secs(10);

/// Download every image referenced by the Markdown into `assets/<id>/`, rewrite
/// each URL to its local relative path, and return the updated Markdown.
///
/// Images are fetched **one at a time**, on purpose: hosts like Wikimedia's
/// `upload.wikimedia.org` burst-limit a client that fires dozens of requests at
/// once and answer `429 Too Many Requests`. A transient failure (429, 5xx, a
/// dropped connection) is retried, honoring the server's `Retry-After` hint, so
/// the batch stays within the limit and every image still lands. All fetches
/// finish before this function returns — the process never moves on with a
/// download outstanding. On per-image failure (after retries) the remote URL is
/// left in the Markdown, so its alt text survives as a labelled placeholder.
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

    let mut result = markdown.to_string();
    for url in unique {
        if let Ok((bytes, ext)) = fetch_image(&client, url) {
            let hash = sha256_hex(&bytes);
            let filename = format!("{hash}.{ext}");
            // A single image that can't be written is skipped rather than failing
            // the whole save; its remote URL stays in the Markdown.
            if fs::write(assets_dir.join(&filename), &bytes).is_ok() {
                let rel = format!("../assets/{id}/{filename}");
                result = result.replace(url, &rel);
            }
        }
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

/// Fetch one image, retrying transient failures (a dropped connection, `429`, or
/// a `5xx`) up to `MAX_ATTEMPTS`, waiting the server's `Retry-After` when given.
fn fetch_image(client: &reqwest::blocking::Client, url: &str) -> Result<(Vec<u8>, String)> {
    let mut attempt = 0;
    loop {
        attempt += 1;
        match client.get(url).send() {
            // Transport-level failure (timeout, connection reset, DNS): retry.
            Err(e) => {
                if attempt >= MAX_ATTEMPTS {
                    return Err(e.into());
                }
                std::thread::sleep(default_backoff(attempt));
            }
            Ok(resp) => {
                let status = resp.status();
                if status.is_success() {
                    let ext = ext_from_response(&resp, url);
                    let bytes = resp.bytes()?.to_vec();
                    return Ok((bytes, ext));
                }
                // A 429 or 5xx is transient — retry, honoring Retry-After. Any
                // other status (e.g. 403/404) is permanent, so give up now and
                // let the remote URL stay in the Markdown as a placeholder.
                let transient =
                    status == reqwest::StatusCode::TOO_MANY_REQUESTS || status.is_server_error();
                if !transient || attempt >= MAX_ATTEMPTS {
                    return Err(anyhow!("image fetch failed: HTTP {status} for {url}"));
                }
                let wait = retry_after(&resp).unwrap_or_else(|| default_backoff(attempt));
                std::thread::sleep(wait);
            }
        }
    }
}

/// Backoff when the server gives no `Retry-After`: `BASE_BACKOFF * attempt`,
/// capped at `MAX_BACKOFF`.
fn default_backoff(attempt: u32) -> Duration {
    (BASE_BACKOFF * attempt).min(MAX_BACKOFF)
}

/// The `Retry-After` delay in delta-seconds form, capped at `MAX_BACKOFF`. The
/// HTTP-date form is not parsed (servers that rate-limit use delta-seconds).
fn retry_after(resp: &reqwest::blocking::Response) -> Option<Duration> {
    let secs: u64 = resp
        .headers()
        .get(reqwest::header::RETRY_AFTER)?
        .to_str()
        .ok()?
        .trim()
        .parse()
        .ok()?;
    Some(Duration::from_secs(secs).min(MAX_BACKOFF))
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
    fn retry_after_parses_delta_seconds_and_caps() {
        assert_eq!(serve_and_retry_after("2"), Some(Duration::from_secs(2)));
        // Absurd values are capped so a hostile hint can't stall the save.
        assert_eq!(serve_and_retry_after("99999"), Some(MAX_BACKOFF));
        // The HTTP-date form is intentionally ignored.
        assert_eq!(serve_and_retry_after("Wed, 21 Oct 2099 07:28:00 GMT"), None);
    }

    #[test]
    fn fetch_image_gives_up_on_permanent_4xx_without_retrying() {
        // 403 is permanent: a single scripted response is enough. If fetch_image
        // wrongly retried, the server (one response) would hang and the body read
        // would fail — either way `is_err` must hold and the call must be quick.
        let url = serve(vec![("403 Forbidden", b"no".to_vec(), "text/html", None)]);
        let result = fetch_image(&no_proxy_client(), &url);
        assert!(
            result.is_err(),
            "a 403 must be treated as a permanent failure"
        );
    }

    #[test]
    fn fetch_image_honors_retry_after_then_succeeds() {
        // A 429 with Retry-After: 1, then the real image on the retry.
        let png = b"\x89PNG\r\n\x1a\npixels".to_vec();
        let url = serve(vec![
            (
                "429 Too Many Requests",
                b"slow down".to_vec(),
                "text/plain",
                Some("1"),
            ),
            ("200 OK", png.clone(), "image/png", None),
        ]);
        let (bytes, ext) =
            fetch_image(&no_proxy_client(), &url).expect("should succeed after waiting");
        assert_eq!(bytes, png);
        assert_eq!(ext, "png");
    }

    #[test]
    fn fetch_image_retries_5xx_then_succeeds() {
        let png = b"\x89PNG\r\n\x1a\npixels".to_vec();
        let url = serve(vec![
            (
                "503 Service Unavailable",
                b"busy".to_vec(),
                "text/plain",
                None,
            ),
            ("200 OK", png.clone(), "image/png", None),
        ]);
        let (bytes, _) = fetch_image(&no_proxy_client(), &url).expect("should succeed on retry");
        assert_eq!(bytes, png);
    }

    #[test]
    fn download_images_writes_asset_and_rewrites_markdown() {
        let png = b"\x89PNG\r\n\x1a\npixels".to_vec();
        let url = serve(vec![("200 OK", png.clone(), "image/png", None)]);
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "TESTID";
        // The duplicate URL must be fetched once (only one scripted response).
        let markdown = format!("![alt]({url})");

        let out = download_images(&library, id, &markdown, &[url.clone(), url.clone()]).unwrap();

        assert!(
            out.contains(&format!("../assets/{id}/")),
            "URL should be rewritten to a local asset path, got: {out}"
        );
        assert!(!out.contains(&url), "the remote URL should be gone: {out}");

        let assets: Vec<_> = fs::read_dir(library.assets_dir(id))
            .unwrap()
            .filter_map(std::result::Result::ok)
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

    /// Hit a one-shot server serving a single response with the given
    /// `Retry-After` header and return the parsed `retry_after` Duration.
    fn serve_and_retry_after(header_value: &'static str) -> Option<Duration> {
        let url = serve(vec![(
            "503 Service Unavailable",
            b"x".to_vec(),
            "text/plain",
            Some(header_value),
        )]);
        let resp = no_proxy_client().get(&url).send().unwrap();
        retry_after(&resp)
    }

    /// Serve each `(status, body, content-type, retry-after)` in order — one per
    /// connection — then stop. Returns the URL clients should hit.
    fn serve(
        responses: Vec<(&'static str, Vec<u8>, &'static str, Option<&'static str>)>,
    ) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            for (status_line, body, content_type, retry_after) in responses {
                let Ok((mut stream, _)) = listener.accept() else {
                    return;
                };
                let _ = stream.read(&mut [0u8; 1024]);
                let ra = retry_after
                    .map(|v| format!("Retry-After: {v}\r\n"))
                    .unwrap_or_default();
                let head = format!(
                    "HTTP/1.1 {status_line}\r\nContent-Type: {content_type}\r\n{ra}\
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
