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
        .map_or(false, |e| e.kind() == std::io::ErrorKind::UnexpectedEof)
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
