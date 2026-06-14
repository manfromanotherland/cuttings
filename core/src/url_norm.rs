// SPDX-License-Identifier: MIT

use anyhow::Result;
use url::Url;

/// Tracking parameters stripped by name (exact match). utm_* is handled as a prefix.
const TRACKING_PARAMS: &[&str] = &[
    "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "source", "campaign",
];

/// Normalize a URL for deduplication per the library-format spec.
///
/// Steps applied in order:
/// 1. Parse (scheme + host are lowercased by the `url` crate automatically).
/// 2. Strip tracking query parameters (utm_*, fbclid, gclid, mc_cid, mc_eid, ref, source, campaign).
/// 3. Strip the fragment.
/// 4. Remove trailing slash from the path unless the path is just "/".
pub fn normalize_url(raw: &str) -> Result<String> {
    let mut url = Url::parse(raw)?;

    url.set_fragment(None);

    let filtered: Vec<(String, String)> = url
        .query_pairs()
        .filter(|(k, _)| {
            let k = k.as_ref();
            !k.starts_with("utm_") && !TRACKING_PARAMS.contains(&k)
        })
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();

    if filtered.is_empty() {
        url.set_query(None);
    } else {
        let mut qs = url.query_pairs_mut();
        qs.clear();
        for (k, v) in &filtered {
            qs.append_pair(k, v);
        }
    }

    let path = url.path().to_owned();
    if path.len() > 1 && path.ends_with('/') {
        url.set_path(path.trim_end_matches('/'));
    }

    Ok(url.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_utm_params() {
        let normalized =
            normalize_url("https://blog.example.com/post?utm_source=hn&utm_medium=link").unwrap();
        assert_eq!(normalized, "https://blog.example.com/post");
    }

    #[test]
    fn strips_fragment() {
        let normalized = normalize_url("https://example.com/page#section").unwrap();
        assert_eq!(normalized, "https://example.com/page");
    }

    #[test]
    fn strips_trailing_slash() {
        let normalized = normalize_url("https://example.com/post/").unwrap();
        assert_eq!(normalized, "https://example.com/post");
    }

    #[test]
    fn preserves_root_slash() {
        let normalized = normalize_url("https://example.com/").unwrap();
        assert_eq!(normalized, "https://example.com/");
    }

    #[test]
    fn preserves_meaningful_params() {
        let normalized = normalize_url("https://example.com/search?q=rust&page=2").unwrap();
        assert_eq!(normalized, "https://example.com/search?q=rust&page=2");
    }

    #[test]
    fn strips_exact_tracking_params() {
        let normalized = normalize_url("https://example.com/post?ref=twitter&page=3").unwrap();
        assert_eq!(normalized, "https://example.com/post?page=3");
    }

    #[test]
    fn lowercases_host() {
        let normalized = normalize_url("HTTPS://EXAMPLE.COM/post").unwrap();
        assert_eq!(normalized, "https://example.com/post");
    }
}
