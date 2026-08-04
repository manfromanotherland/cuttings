// SPDX-License-Identifier: MIT

use std::sync::{Mutex, OnceLock};

use ulid::{Generator, Ulid};

/// Generate a new ULID string (26-char Crockford Base32).
///
/// IDs are **monotonically increasing**: a process-wide generator increments
/// the random component for IDs created within the same millisecond, so IDs
/// produced in sequence always sort in creation order. (Plain `Ulid::new()`
/// only sorts across milliseconds — within one, its random suffix is
/// unordered, which would let two saves in the same millisecond sort out of
/// insertion order.)
pub fn new_id() -> String {
    static GENERATOR: OnceLock<Mutex<Generator>> = OnceLock::new();
    let generator = GENERATOR.get_or_init(|| Mutex::new(Generator::new()));
    let mut guard = generator.lock().unwrap_or_else(|e| e.into_inner());
    // `generate` only errors on monotonic overflow within a single millisecond
    // (practically impossible) or if the system clock moves backwards; fall
    // back to a fresh random ULID so we always return a valid 26-char id.
    guard.generate().unwrap_or_else(|_| Ulid::new()).to_string()
}

/// Content-addressed id for a page: the SHA-256 (hex) of its normalized URL.
///
/// Deterministic — the same page always yields the same id, so it doubles as the
/// dedup key and the article's filename stem. Errors only if the URL can't be
/// parsed (e.g. a non-http scheme), in which case the caller decides what to do.
pub fn url_id(url: &str) -> anyhow::Result<String> {
    Ok(crate::writer::sha256_hex(
        crate::normalize_url(url)?.as_bytes(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_is_26_chars() {
        let id = new_id();
        assert_eq!(id.len(), 26);
    }

    #[test]
    fn ids_are_sorted_by_creation_order() {
        // The monotonic generator must keep ids strictly increasing even when
        // many are produced within the same millisecond — a tight loop is the
        // worst case for the old random-suffix behaviour.
        let mut prev = new_id();
        for _ in 0..1000 {
            let next = new_id();
            assert!(prev < next, "{prev} should sort before {next}");
            prev = next;
        }
    }

    #[test]
    fn ids_are_unique() {
        let a = new_id();
        let b = new_id();
        assert_ne!(a, b);
    }

    #[test]
    fn url_id_is_deterministic() {
        let u = "https://example.com/post";
        assert_eq!(url_id(u).unwrap(), url_id(u).unwrap());
    }

    #[test]
    fn url_id_is_64_char_lowercase_hex() {
        let id = url_id("https://example.com/post").unwrap();
        assert_eq!(id.len(), 64);
        assert!(id
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn url_id_ignores_tracking_params() {
        assert_eq!(
            url_id("https://example.com/post").unwrap(),
            url_id("https://example.com/post?utm_source=x").unwrap(),
        );
    }

    #[test]
    fn url_id_differs_for_distinct_pages() {
        assert_ne!(
            url_id("https://example.com/a").unwrap(),
            url_id("https://example.com/b").unwrap(),
        );
    }

    #[test]
    fn url_id_errors_on_unparseable_url() {
        assert!(url_id("not a url").is_err());
    }
}
