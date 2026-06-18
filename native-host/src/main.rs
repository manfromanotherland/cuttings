// SPDX-License-Identifier: MIT

mod install;
mod protocol;
mod save;

use std::io::{Read, Write};

use anyhow::Result;
use protocol::{SaveRequest, SaveResponse};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--version") {
        println!("native-host v{}", read_later_core::version());
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

fn dispatch(raw: &[u8]) -> SaveResponse {
    match serde_json::from_slice::<SaveRequest>(raw) {
        Err(e) => SaveResponse::error("invalid_request", &e.to_string()),
        Ok(req) => match save::handle(req) {
            Ok(resp) => resp,
            Err(e) => {
                let (code, msg) = save::classify_error(&e);
                SaveResponse::error(code, &msg)
            }
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
            "image_urls": []
        });
        let resp = dispatch(serde_json::to_vec(&msg).unwrap().as_slice());
        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("invalid_request"));
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    use std::sync::Mutex;
    use tempfile::TempDir;

    // Serialize all tests that touch READ_LATER_LIBRARY to avoid races.
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
            "image_urls": []
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
        std::env::set_var("READ_LATER_LIBRARY", dir.path());
        let result = f(&dir);
        std::env::remove_var("READ_LATER_LIBRARY");
        result
    }

    #[test]
    fn save_writes_article_to_disk() {
        with_library(|dir| {
            let resp = dispatch(&save_message("https://example.com/article-1"));
            assert!(resp.ok, "expected ok, got error: {:?}", resp.error);

            let id = resp.id.as_deref().unwrap();
            let article_path = dir.path().join("articles").join(format!("{id}.md"));
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
            assert_eq!(id.len(), 26, "ULID must be 26 chars");

            let path = resp
                .path
                .as_deref()
                .expect("path missing from success response");
            assert_eq!(path, format!("articles/{id}.md"));
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
        // `$HOME/.config/read-later/library` fallback. Pointing HOME at an
        // empty temp dir ensures the host can't resolve a real library that a
        // developer machine happens to have configured.
        let home = TempDir::new().unwrap();
        let prev_home = std::env::var_os("HOME");
        std::env::set_var("HOME", home.path());
        std::env::remove_var("READ_LATER_LIBRARY");

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
    fn failed_image_download_leaves_comment_in_markdown() {
        with_library(|dir| {
            let msg = serde_json::to_vec(&serde_json::json!({
                "protocol_version": 1,
                "action": "save",
                "metadata": {
                    "url": "https://example.com/img-test",
                    "canonical_url": "https://example.com/img-test",
                    "title": "Image Fail Test",
                    "saved_at": "2026-06-13T15:00:00Z"
                },
                "markdown": "# Image Fail Test\n\n![Photo](http://127.0.0.1:1/photo.jpg)\n",
                "image_urls": ["http://127.0.0.1:1/photo.jpg"]
            }))
            .unwrap();

            let resp = dispatch(&msg);
            assert!(
                resp.ok,
                "save should succeed even when image download fails"
            );

            let id = resp.id.as_deref().unwrap();
            let content =
                std::fs::read_to_string(dir.path().join("articles").join(format!("{id}.md")))
                    .unwrap();
            assert!(
                content.contains("asset-fetch-failed"),
                "expected <!-- asset-fetch-failed --> comment for unreachable image"
            );
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
            "image_urls": []
        }))
        .unwrap();

        let resp = dispatch(&msg);
        assert!(!resp.ok);
        assert_eq!(resp.error.as_deref(), Some("invalid_request"));
    }
}
