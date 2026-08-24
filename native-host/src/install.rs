// SPDX-License-Identifier: MIT

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::json;

const HOST_NAME: &str = "is.edmundo.cuttings.host";

/// Chrome extension ID assigned by the Chrome Web Store for the published
/// extension. The store mints this on upload (the packaged manifest ships
/// without `key`), so it is the store's ID, not the one derived from the `key`
/// used for local unpacked development. Keep it in sync with the store listing.
const DEFAULT_EXTENSION_ID: &str = "cegehgdbbjjeondepcaejickdmkacbck";

/// Firefox identifies extensions by add-on ID, not the Chrome extension ID.
/// This is the `browser_specific_settings.gecko.id` in the extension's
/// manifest.json — keep the two in sync or Firefox rejects the native host.
const FIREFOX_DEFAULT_EXTENSION_ID: &str = "cuttings@edmundo.is";

/// Root under `$HOME` where macOS browsers keep their per-app data.
const APP_SUPPORT: &str = "Library/Application Support";

/// Subdirectory, relative to a browser's data dir, that holds native messaging
/// host manifests. Fixed by the browser — we can't relocate it.
const NMH_DIR: &str = "NativeMessagingHosts";

/// Which dialect of native-messaging manifest a browser expects.
#[derive(Clone, Copy)]
enum Flavor {
    /// Chromium and its forks: identifies the extension by `allowed_origins`.
    Chrome,
    /// Firefox and its forks: identifies the extension by `allowed_extensions`.
    Firefox,
}

/// A browser we know about, relative to `Library/Application Support`.
struct KnownBrowser {
    /// Directory whose presence means the browser is installed.
    detect_subdir: &'static str,
    /// Directory whose `NativeMessagingHosts` child is where this browser reads
    /// manifests. `None` means it's the same as `detect_subdir` (the common
    /// case). Firefox is the exception: it stores its profile under `Firefox/`
    /// but reads native-messaging manifests from `Mozilla/`, so the two differ.
    manifest_subdir: Option<&'static str>,
    /// Which manifest dialect it expects.
    flavor: Flavor,
}

/// Curated list of browsers whose manifest dialect we know for sure. This is
/// deliberately small: the discovery pass in [`install_manifest_in`] picks up
/// any other installed browser automatically. The list matters for two things
/// discovery can't do on its own — telling Firefox-style browsers apart from
/// Chrome-style ones, and registering with a known browser that's installed but
/// hasn't created its `NativeMessagingHosts` dir yet.
const KNOWN_BROWSERS: &[KnownBrowser] = &[
    KnownBrowser {
        detect_subdir: "Google/Chrome",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    KnownBrowser {
        detect_subdir: "Microsoft Edge",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    KnownBrowser {
        detect_subdir: "Chromium",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    KnownBrowser {
        detect_subdir: "BraveSoftware/Brave-Browser",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    KnownBrowser {
        detect_subdir: "Vivaldi",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    KnownBrowser {
        detect_subdir: "Arc",
        manifest_subdir: None,
        flavor: Flavor::Chrome,
    },
    // Firefox: installed under `Firefox/`, but reads manifests from `Mozilla/`.
    KnownBrowser {
        detect_subdir: "Firefox",
        manifest_subdir: Some("Mozilla"),
        flavor: Flavor::Firefox,
    },
    KnownBrowser {
        detect_subdir: "LibreWolf",
        manifest_subdir: None,
        flavor: Flavor::Firefox,
    },
    KnownBrowser {
        detect_subdir: "Waterfox",
        manifest_subdir: None,
        flavor: Flavor::Firefox,
    },
];

/// Write `is.edmundo.cuttings.host.json` into every browser that can use it.
///
/// `extension_id` is the Chrome extension ID (e.g. `abcdefghijklmnopqrstuvwxyz123456`).
/// Pass `None` to use `DEFAULT_EXTENSION_ID`, the ID pinned by the extension's
/// `key` field — which is what the macOS app relies on when it installs the
/// manifest without an explicit ID.
pub fn install_manifest(extension_id: Option<&str>) -> Result<()> {
    let binary_path = std::env::current_exe()
        .context("could not determine binary path")?
        .to_string_lossy()
        .into_owned();

    let home = std::env::var("HOME").context("HOME env var not set")?;

    install_manifest_in(Path::new(&home), &binary_path, extension_id)
}

/// The testable core of [`install_manifest`], parameterized on `$HOME` and the
/// binary path so it can run against a temp directory.
///
/// Targets come from two sources, deduped by path:
///  1. **Known browsers that are installed** — their data dir already exists, so
///     we register even if the `NativeMessagingHosts` subdir isn't there yet.
///  2. **Discovery** — any existing `NativeMessagingHosts` dir under Application
///     Support that the known list didn't already cover. This auto-covers new
///     Chromium forks the day the user has them, with no release. Discovered
///     browsers are assumed Chrome-style (the overwhelming majority); a
///     Firefox-style fork not in [`KNOWN_BROWSERS`] would get the wrong dialect,
///     so add those to the curated list.
fn install_manifest_in(home: &Path, binary_path: &str, extension_id: Option<&str>) -> Result<()> {
    let app_support = home.join(APP_SUPPORT);

    let mut targets: Vec<(PathBuf, Flavor)> = Vec::new();
    let mut seen: HashSet<PathBuf> = HashSet::new();

    // 1. Known browsers that are actually installed.
    for browser in KNOWN_BROWSERS {
        if app_support.join(browser.detect_subdir).is_dir() {
            let manifest_subdir = browser.manifest_subdir.unwrap_or(browser.detect_subdir);
            let nmh = app_support.join(manifest_subdir).join(NMH_DIR);
            if seen.insert(nmh.clone()) {
                targets.push((nmh, browser.flavor));
            }
        }
    }

    // 2. Any other browser that already has a NativeMessagingHosts dir.
    for nmh in discover_nmh_dirs(&app_support) {
        if seen.insert(nmh.clone()) {
            targets.push((nmh, Flavor::Chrome));
        }
    }

    if targets.is_empty() {
        eprintln!("warning: no browsers found under {}", app_support.display());
    }

    for (dir, flavor) in targets {
        let manifest = match flavor {
            Flavor::Chrome => chrome_manifest(binary_path, extension_id),
            Flavor::Firefox => firefox_manifest(binary_path, extension_id),
        };
        match write_manifest(&dir, &manifest) {
            Ok(path) => println!("installed: {}", path.display()),
            Err(e) => eprintln!("warning: could not write to {}: {e}", dir.display()),
        }
    }

    Ok(())
}

/// Find every existing `NativeMessagingHosts` directory under Application
/// Support. Browsers keep it either one level down (`Vivaldi/NativeMessagingHosts`)
/// or two (`Google/Chrome/NativeMessagingHosts`), so we scan both depths. Only
/// directories that already exist are returned — we never create one here, since
/// for an unknown vendor we can't tell whether it's really a browser.
fn discover_nmh_dirs(app_support: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();

    let Ok(entries) = fs::read_dir(app_support) else {
        return found;
    };

    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }

        // Depth 1: <vendor>/NativeMessagingHosts.
        let nmh = dir.join(NMH_DIR);
        if nmh.is_dir() {
            found.push(nmh);
        }

        // Depth 2: <vendor>/<product>/NativeMessagingHosts.
        if let Ok(subs) = fs::read_dir(&dir) {
            for sub in subs.flatten() {
                let sub_dir = sub.path();
                if !sub_dir.is_dir() {
                    continue;
                }
                let nmh = sub_dir.join(NMH_DIR);
                if nmh.is_dir() {
                    found.push(nmh);
                }
            }
        }
    }

    found
}

fn chrome_manifest(binary_path: &str, extension_id: Option<&str>) -> serde_json::Value {
    let origin = format!(
        "chrome-extension://{}/",
        extension_id.unwrap_or(DEFAULT_EXTENSION_ID)
    );
    json!({
        "name": HOST_NAME,
        "description": "Cuttings native messaging host",
        "path": binary_path,
        "type": "stdio",
        "allowed_origins": [origin]
    })
}

fn firefox_manifest(binary_path: &str, extension_id: Option<&str>) -> serde_json::Value {
    json!({
        "name": HOST_NAME,
        "description": "Cuttings native messaging host",
        "path": binary_path,
        "type": "stdio",
        "allowed_extensions": [extension_id.unwrap_or(FIREFOX_DEFAULT_EXTENSION_ID)]
    })
}

fn write_manifest(dir: &Path, manifest: &serde_json::Value) -> Result<PathBuf> {
    fs::create_dir_all(dir)?;
    let path = dir.join(format!("{HOST_NAME}.json"));
    let content = serde_json::to_string_pretty(manifest)?;
    fs::write(&path, content.as_bytes())?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    /// Read and parse the manifest a browser dir should now contain.
    fn read_manifest(nmh: &Path) -> serde_json::Value {
        let path = nmh.join(format!("{HOST_NAME}.json"));
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("expected manifest at {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap()
    }

    fn app_support(home: &Path) -> PathBuf {
        home.join(APP_SUPPORT)
    }

    #[test]
    fn registers_with_installed_known_browser() {
        let home = TempDir::new().unwrap();
        // Chrome is installed but has never created its NativeMessagingHosts dir.
        fs::create_dir_all(app_support(home.path()).join("Google/Chrome")).unwrap();

        install_manifest_in(home.path(), "/opt/cuttings/cuttings-native-host", None).unwrap();

        let nmh = app_support(home.path()).join("Google/Chrome").join(NMH_DIR);
        let manifest = read_manifest(&nmh);
        assert_eq!(manifest["name"], HOST_NAME);
        assert_eq!(manifest["path"], "/opt/cuttings/cuttings-native-host");
        assert_eq!(
            manifest["allowed_origins"][0],
            format!("chrome-extension://{DEFAULT_EXTENSION_ID}/")
        );
    }

    #[test]
    fn skips_absent_known_browser() {
        let home = TempDir::new().unwrap();
        fs::create_dir_all(app_support(home.path()).join("Google/Chrome")).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        // Vivaldi wasn't installed, so no directory should have been created for it.
        assert!(!app_support(home.path()).join("Vivaldi").exists());
    }

    #[test]
    fn firefox_detected_via_profile_writes_to_mozilla_dir() {
        let home = TempDir::new().unwrap();
        // Firefox is installed — its profile lives under `Firefox/` — but the
        // `Mozilla/` native-messaging dir doesn't exist yet. The installer must
        // detect Firefox via the profile and create the manifest under Mozilla.
        fs::create_dir_all(app_support(home.path()).join("Firefox")).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        let nmh = app_support(home.path()).join("Mozilla").join(NMH_DIR);
        let manifest = read_manifest(&nmh);
        assert_eq!(
            manifest["allowed_extensions"][0],
            FIREFOX_DEFAULT_EXTENSION_ID
        );
        assert!(manifest.get("allowed_origins").is_none());
    }

    #[test]
    fn mozilla_dir_alone_does_not_trigger_firefox_install() {
        let home = TempDir::new().unwrap();
        // A bare `Mozilla/` dir (no Firefox profile, no existing NMH dir) is not
        // proof Firefox is installed, so nothing should be written.
        fs::create_dir_all(app_support(home.path()).join("Mozilla")).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        let nmh = app_support(home.path()).join("Mozilla").join(NMH_DIR);
        assert!(!nmh.join(format!("{HOST_NAME}.json")).exists());
    }

    #[test]
    fn firefox_fork_gets_firefox_dialect_not_discovered_as_chrome() {
        let home = TempDir::new().unwrap();
        // LibreWolf already has its dir, so discovery would find it too — the
        // known pass must win and give it the Firefox dialect, not Chrome's.
        let nmh = app_support(home.path()).join("LibreWolf").join(NMH_DIR);
        fs::create_dir_all(&nmh).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        let manifest = read_manifest(&nmh);
        assert!(manifest.get("allowed_extensions").is_some());
        assert!(manifest.get("allowed_origins").is_none());
    }

    #[test]
    fn discovers_unknown_browser_with_existing_dir() {
        let home = TempDir::new().unwrap();
        // A browser we don't list, but it already has a NativeMessagingHosts dir.
        let nmh = app_support(home.path())
            .join("SomeNewBrowser")
            .join(NMH_DIR);
        fs::create_dir_all(&nmh).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        let manifest = read_manifest(&nmh);
        // Discovered browsers are treated as Chrome-style.
        assert!(manifest.get("allowed_origins").is_some());
    }

    #[test]
    fn discovers_nested_unknown_browser() {
        let home = TempDir::new().unwrap();
        let nmh = app_support(home.path())
            .join("NewVendor/NewProduct")
            .join(NMH_DIR);
        fs::create_dir_all(&nmh).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        assert!(nmh.join(format!("{HOST_NAME}.json")).exists());
    }

    #[test]
    fn does_not_create_dirs_for_uninstalled_browsers() {
        let home = TempDir::new().unwrap();
        fs::create_dir_all(app_support(home.path()).join("Google/Chrome")).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        // Only Chrome existed; the support dir should hold nothing else.
        let vendors: Vec<String> = fs::read_dir(app_support(home.path()))
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(vendors, vec!["Google".to_string()]);
    }

    #[test]
    fn known_browser_is_not_written_twice() {
        let home = TempDir::new().unwrap();
        // Chrome installed *with* its NativeMessagingHosts dir already present,
        // so both the known pass and discovery would find it.
        let nmh = app_support(home.path()).join("Google/Chrome").join(NMH_DIR);
        fs::create_dir_all(&nmh).unwrap();

        install_manifest_in(home.path(), "/bin/host", None).unwrap();

        // It stays Chrome-style (known pass wins) and the file is valid.
        let manifest = read_manifest(&nmh);
        assert!(manifest.get("allowed_origins").is_some());
    }
}
