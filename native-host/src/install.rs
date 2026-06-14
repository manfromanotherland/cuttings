// SPDX-License-Identifier: MIT

use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde_json::json;

const HOST_NAME: &str = "com.readlater.host";

/// Paths where Chrome-style native messaging manifests live on macOS.
const CHROME_PATHS: &[&str] = &[
    "Library/Application Support/Google/Chrome/NativeMessagingHosts",
    "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
    "Library/Application Support/Chromium/NativeMessagingHosts",
];

/// Path for Firefox-style manifests on macOS.
const FIREFOX_PATH: &str = "Library/Application Support/Mozilla/NativeMessagingHosts";

/// Write `com.readlater.host.json` to all per-browser manifest directories.
///
/// `extension_id` is the Chrome extension ID (e.g. `abcdefghijklmnopqrstuvwxyz123456`).
/// Pass `None` to use a placeholder — update it once the extension is published.
pub fn install_manifest(extension_id: Option<&str>) -> Result<()> {
    let binary_path = std::env::current_exe()
        .context("could not determine binary path")?
        .to_string_lossy()
        .into_owned();

    let home = std::env::var("HOME").context("HOME env var not set")?;
    let home = PathBuf::from(home);

    let origin = extension_id
        .map(|id| format!("chrome-extension://{id}/"))
        .unwrap_or_else(|| "chrome-extension://PLACEHOLDER_EXTENSION_ID/".to_string());

    let chrome_manifest = json!({
        "name": HOST_NAME,
        "description": "read-later native messaging host",
        "path": binary_path,
        "type": "stdio",
        "allowed_origins": [origin]
    });

    let firefox_manifest = json!({
        "name": HOST_NAME,
        "description": "read-later native messaging host",
        "path": binary_path,
        "type": "stdio",
        "allowed_extensions": [
            extension_id.unwrap_or("readlater@localhost")
        ]
    });

    let filename = format!("{HOST_NAME}.json");

    for rel in CHROME_PATHS {
        let dir = home.join(rel);
        if let Err(e) = write_manifest(&dir, &filename, &chrome_manifest) {
            eprintln!("warning: could not write to {}: {e}", dir.display());
        } else {
            println!("installed: {}", dir.join(&filename).display());
        }
    }

    let firefox_dir = home.join(FIREFOX_PATH);
    if let Err(e) = write_manifest(&firefox_dir, &filename, &firefox_manifest) {
        eprintln!("warning: could not write Firefox manifest: {e}");
    } else {
        println!("installed: {}", firefox_dir.join(&filename).display());
    }

    Ok(())
}

fn write_manifest(dir: &PathBuf, filename: &str, manifest: &serde_json::Value) -> Result<()> {
    fs::create_dir_all(dir)?;
    let path = dir.join(filename);
    let content = serde_json::to_string_pretty(manifest)?;
    fs::write(&path, content.as_bytes())?;
    Ok(())
}
