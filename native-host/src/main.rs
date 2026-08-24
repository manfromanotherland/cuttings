// SPDX-License-Identifier: MIT

mod check;
mod install;
mod protocol;
mod save;

use std::io::{Read, Write};

use anyhow::Result;
use protocol::{CheckRequest, SaveRequest, SaveResponse};
use serde::Deserialize;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--version") {
        println!("cuttings-native-host v{}", cuttings_core::version());
        return Ok(());
    }

    if args.iter().any(|a| a == "--install-manifest") {
        let ext_id = args
            .windows(2)
            .find(|w| w[0] == "--extension-id")
            .map(|w| w[1].as_str());
        install::install_manifest(ext_id)?;
        return Ok(());
    }

    run_loop()
}

/// Read and handle native messaging messages until stdin closes.
fn run_loop() -> Result<()> {
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();

    loop {
        let raw = match read_message(&mut stdin.lock()) {
            Ok(bytes) => bytes,
            Err(e) if is_eof_error(&e) => break,
            Err(e) => return Err(e),
        };

        let response = dispatch(&raw);
        let payload = serde_json::to_vec(&response)?;

        // Enforce the 1 MB host→browser limit.
        if payload.len() > 1_048_576 {
            let truncated = SaveResponse::error("io_error", "response exceeds 1 MB limit");
            write_message(&mut stdout.lock(), &serde_json::to_vec(&truncated)?)?;
        } else {
            write_message(&mut stdout.lock(), &payload)?;
        }
    }

    Ok(())
}

#[derive(Deserialize)]
struct ActionPeek {
    action: String,
}

fn dispatch(raw: &[u8]) -> SaveResponse {
    let action = match serde_json::from_slice::<ActionPeek>(raw) {
        Err(e) => return SaveResponse::error("invalid_request", &e.to_string()),
        Ok(p) => p.action,
    };

    match action.as_str() {
        "check" => match serde_json::from_slice::<CheckRequest>(raw) {
            Err(e) => SaveResponse::error("invalid_request", &e.to_string()),
            Ok(req) => match check::handle(req) {
                Ok(resp) => resp,
                Err(e) => SaveResponse::error("io_error", &e.to_string()),
            },
        },
        _ => match serde_json::from_slice::<SaveRequest>(raw) {
            Err(e) => SaveResponse::error("invalid_request", &e.to_string()),
            Ok(req) => match save::handle(req) {
                Ok(resp) => resp,
                Err(e) => {
                    let (code, msg) = save::classify_error(&e);
                    SaveResponse::error(code, &msg)
                }
            },
        },
    }
}

/// Read one length-prefixed message from the native messaging stream.
/// Returns `UnexpectedEof` when the browser closes the pipe.
fn read_message(r: &mut impl Read) -> Result<Vec<u8>> {
    let mut len_buf = [0u8; 4];
    r.read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;

    let mut buf = vec![0u8; len];
    r.read_exact(&mut buf)?;
    Ok(buf)
}

/// Write one length-prefixed message to the native messaging stream.
fn write_message(w: &mut impl Write, msg: &[u8]) -> Result<()> {
    let len = (msg.len() as u32).to_le_bytes();
    w.write_all(&len)?;
    w.write_all(msg)?;
    w.flush()?;
    Ok(())
}

fn is_eof_error(e: &anyhow::Error) -> bool {
    e.downcast_ref::<std::io::Error>()
        .is_some_and(|e| e.kind() == std::io::ErrorKind::UnexpectedEof)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn framed(json: &str) -> Vec<u8> {
        let bytes = json.as_bytes();
        let mut buf = (bytes.len() as u32).to_le_bytes().to_vec();
        buf.extend_from_slice(bytes);
        buf
    }

    #[test]
    fn round_trip_framing() {
        let payload = r#"{"hello":"world"}"#;
        let mut cursor = Cursor::new(framed(payload));
        let out = read_message(&mut cursor).unwrap();
        assert_eq!(out, payload.as_bytes());
    }

    #[test]
    fn invalid_request_returns_error_response() {
        let resp = dispatch(b"not json at all");
        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("invalid_request"));
    }

    #[test]
    fn wrong_protocol_version_returns_error() {
        let msg = serde_json::json!({
            "protocol_version": 99,
            "action": "save",
            "metadata": {
                "url": "https://example.com",
                "canonical_url": "https://example.com",
                "title": "Test",
                "saved_at": "2026-06-13T15:00:00Z"
            },
            "markdown": "# Test",
            "images": []
        });
        let resp = dispatch(serde_json::to_vec(&msg).unwrap().as_slice());
        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("invalid_request"));
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    use base64::Engine;
    use std::sync::Mutex;
    use tempfile::TempDir;

    // Serialize all tests that touch CUTTINGS_LIBRARY to avoid races.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn save_message(url: &str) -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "protocol_version": 1,
            "action": "save",
            "metadata": {
                "url": url,
                "canonical_url": url,
                "title": "Test Article",
                "saved_at": "2026-06-13T15:00:00Z"
            },
            "markdown": "# Test Article\n\nSome content here.\n",
            "images": []
        }))
        .unwrap()
    }

    fn with_library<F, R>(f: F) -> R
    where
        F: FnOnce(&TempDir) -> R,
    {
        // Recover from a poisoned lock so a panic in one test doesn't cascade
        // into PoisonError failures in the others.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = TempDir::new().unwrap();
        std::env::set_var("CUTTINGS_LIBRARY", dir.path());
        let result = f(&dir);
        std::env::remove_var("CUTTINGS_LIBRARY");
        result
    }

    #[test]
    fn save_writes_article_to_disk() {
        with_library(|dir| {
            let resp = dispatch(&save_message("https://example.com/article-1"));
            assert!(resp.ok, "expected ok, got error: {:?}", resp.error);

            // Locate the file via the fan-out path the response reports.
            let rel = resp.path.as_deref().unwrap();
            let article_path = dir.path().join(rel);
            assert!(
                article_path.exists(),
                "article file was not written to disk"
            );

            let content = std::fs::read_to_string(&article_path).unwrap();
            assert!(
                content.contains("format_version: 1"),
                "missing format_version in frontmatter"
            );
            assert!(content.contains("Test Article"), "missing title in file");
            assert!(
                content.contains("Some content here."),
                "missing body in file"
            );
        });
    }

    #[test]
    fn success_response_shape() {
        with_library(|_dir| {
            let resp = dispatch(&save_message("https://example.com/resp-shape"));
            assert!(resp.ok);

            let id = resp
                .id
                .as_deref()
                .expect("id missing from success response");
            assert_eq!(id.len(), 64, "content-addressed id is 64-char SHA-256 hex");

            let path = resp
                .path
                .as_deref()
                .expect("path missing from success response");
            // Per-reading folder: articles/<first 2 hex chars>/<id>/article.md
            assert_eq!(path, format!("articles/{}/{id}/article.md", &id[..2]));
        });
    }

    #[test]
    fn duplicate_url_returns_duplicate_error() {
        with_library(|_dir| {
            let msg = save_message("https://example.com/dup");
            dispatch(&msg);
            let resp = dispatch(&msg);
            assert!(!resp.ok, "second save with same canonical_url should fail");
            assert_eq!(resp.error.as_deref(), Some("duplicate"));
            assert!(
                resp.message
                    .as_deref()
                    .unwrap_or("")
                    .contains("already exists"),
                "duplicate message should mention the conflict"
            );
        });
    }

    #[test]
    fn no_library_returns_library_not_configured() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());

        // Isolate BOTH library sources: the env var and the
        // `$HOME/.config/cuttings/library` fallback. Pointing HOME at an
        // empty temp dir ensures the host can't resolve a real library that a
        // developer machine happens to have configured.
        let home = TempDir::new().unwrap();
        let prev_home = std::env::var_os("HOME");
        std::env::set_var("HOME", home.path());
        std::env::remove_var("CUTTINGS_LIBRARY");

        let resp = dispatch(&save_message("https://example.com/no-lib"));

        // Restore HOME before asserting so an assertion failure can't leak the
        // overridden value into other tests.
        match prev_home {
            Some(h) => std::env::set_var("HOME", h),
            None => std::env::remove_var("HOME"),
        }

        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("library_not_configured"));
    }

    #[test]
    fn supplied_image_is_written_and_unsupplied_stays_remote() {
        with_library(|dir| {
            // One image comes with bytes; the other has none supplied.
            let bytes = b"\x89PNG\r\n\x1a\npixels";
            let data_b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
            let msg = serde_json::to_vec(&serde_json::json!({
                "protocol_version": 1,
                "action": "save",
                "metadata": {
                    "url": "https://example.com/img-test",
                    "canonical_url": "https://example.com/img-test",
                    "title": "Image Test",
                    "saved_at": "2026-06-13T15:00:00Z"
                },
                "markdown": "# Image Test\n\n![Got](https://cdn.example.com/got.png)\n![Missing](https://cdn.example.com/missing.png)\n",
                "images": [
                    {
                        "url": "https://cdn.example.com/got.png",
                        "content_type": "image/png",
                        "data_base64": data_b64
                    }
                ]
            }))
            .unwrap();

            let resp = dispatch(&msg);
            assert!(resp.ok, "save should succeed: {:?}", resp.error);

            let content =
                std::fs::read_to_string(dir.path().join(resp.path.as_deref().unwrap())).unwrap();
            let id = resp.id.as_deref().unwrap();
            // The supplied image is rewritten to a local asset, linked relative
            // to the article file that sits beside its assets/ folder.
            assert!(
                content.contains("![Got](assets/"),
                "supplied image should be rewritten to a local path:\n{content}"
            );
            assert!(
                !content.contains("cdn.example.com/got.png"),
                "supplied image's remote URL should be gone"
            );
            // ...and its bytes are on disk under the reading's own assets/ folder.
            let asset = dir
                .path()
                .join("articles")
                .join(&id[..2])
                .join(id)
                .join("assets")
                .join(format!("{}.png", cuttings_core::sha256_hex(bytes)));
            assert_eq!(std::fs::read(&asset).unwrap(), bytes);
            // The unsupplied image keeps its remote URL as a placeholder.
            assert!(
                content.contains("https://cdn.example.com/missing.png"),
                "an image with no supplied bytes keeps its remote URL"
            );
        });
    }

    #[test]
    fn check_returns_not_saved_for_empty_library() {
        // No articles saved yet: check scans an empty (or absent) articles/ dir
        // and reports saved: false.
        with_library(|_dir| {
            let msg = serde_json::to_vec(&serde_json::json!({
                "protocol_version": 1,
                "action": "check",
                "url": "https://example.com/not-there"
            }))
            .unwrap();
            let resp = dispatch(&msg);
            assert!(resp.ok);
            assert_eq!(resp.saved, Some(false));
        });
    }

    #[test]
    fn check_returns_not_saved_for_unknown_url() {
        with_library(|_dir| {
            // Save one article, then check a different URL.
            dispatch(&save_message("https://example.com/saved"));

            let msg = serde_json::to_vec(&serde_json::json!({
                "protocol_version": 1,
                "action": "check",
                "url": "https://example.com/not-there"
            }))
            .unwrap();
            let resp = dispatch(&msg);
            assert!(resp.ok);
            assert_eq!(resp.saved, Some(false));
        });
    }

    #[test]
    fn check_returns_saved_after_save() {
        with_library(|_dir| {
            // Saving writes the article file; check scans articles/ directly, so
            // it sees the save with no index or app involvement.
            dispatch(&save_message("https://example.com/for-check"));

            let msg = serde_json::to_vec(&serde_json::json!({
                "protocol_version": 1,
                "action": "check",
                "url": "https://example.com/for-check"
            }))
            .unwrap();
            let resp = dispatch(&msg);
            assert!(resp.ok);
            assert_eq!(resp.saved, Some(true));
            assert!(resp.id.is_some());
        });
    }

    #[test]
    fn missing_required_field_returns_invalid_request() {
        // canonical_url, title, and saved_at are all absent — serde must reject this.
        let msg = serde_json::to_vec(&serde_json::json!({
            "protocol_version": 1,
            "action": "save",
            "metadata": { "url": "https://example.com" },
            "markdown": "# Test",
            "images": []
        }))
        .unwrap();

        let resp = dispatch(&msg);
        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("invalid_request"));
    }
}
