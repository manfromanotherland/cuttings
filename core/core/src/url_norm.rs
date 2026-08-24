// SPDX-License-Identifier: MIT

use anyhow::Result;
use url::Url;

/// Tracking parameters stripped by name (exact match). utm_* is handled as a prefix.
const TRACKING_PARAMS: &[&str] = &[
    "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "source", "campaign",
];

/// Normalize a URL for deduplication per the library-format spec.
///
/// Since a page's id is `SHA256(normalize(url))`, normalization *is* identity:
/// trivially-equivalent URLs must collapse to one string.
///
/// Steps applied in order:
/// 1. Parse (scheme + host are lowercased by the `url` crate automatically).
/// 2. Strip the fragment.
/// 3. Strip a leading `www.` from the host.
/// 4. Remove the default port (`:80` http, `:443` https).
/// 5. Strip tracking query parameters (utm_*, fbclid, gclid, mc_cid, mc_eid, ref, source, campaign).
/// 6. Sort the remaining query parameters (by key, then value) for a stable order.
/// 7. Remove trailing slash from the path unless the path is just "/".
pub fn normalize_url(raw: &str) -> Result<String> {
    let mut url = Url::parse(raw)?;

    url.set_fragment(None);

    // Strip a leading `www.` label (only the literal `www.`, not `www2.` etc.).
    if let Some(host) = url.host_str() {
        if let Some(stripped) = host.strip_prefix("www.") {
            if !stripped.is_empty() {
                let stripped = stripped.to_owned();
                url.set_host(Some(&stripped))?;
            }
        }
    }

    // Drop the scheme's default port. The `url` crate already omits these in most
    // cases; this makes it explicit so it's guaranteed regardless of input form.
    if let Some(port) = url.port() {
        let default = match url.scheme() {
            "http" => Some(80),
            "https" => Some(443),
            _ => None,
        };
        if Some(port) == default {
            let _ = url.set_port(None);
        }
    }

    let mut filtered: Vec<(String, String)> = url
        .query_pairs()
        .filter(|(k, _)| {
            let k = k.as_ref();
            !k.starts_with("utm_") && !TRACKING_PARAMS.contains(&k)
        })
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    // Sort so query-param order can't produce two ids for one resource.
    filtered.sort();

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
        // Meaningful params are kept; they come back in sorted order.
        let normalized = normalize_url("https://example.com/search?q=rust&page=2").unwrap();
        assert_eq!(normalized, "https://example.com/search?page=2&q=rust");
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

    #[test]
    fn strips_leading_www() {
        let normalized = normalize_url("https://www.example.com/post").unwrap();
        assert_eq!(normalized, "https://example.com/post");
    }

    #[test]
    fn leaves_non_www_subdomains() {
        // Only the literal leading "www." is stripped.
        assert_eq!(
            normalize_url("https://www2.example.com/post").unwrap(),
            "https://www2.example.com/post"
        );
        assert_eq!(
            normalize_url("https://wwwfoo.example.com/post").unwrap(),
            "https://wwwfoo.example.com/post"
        );
        // A `www.` deeper in the host is not a leading label.
        assert_eq!(
            normalize_url("https://api.www.example.com/post").unwrap(),
            "https://api.www.example.com/post"
        );
    }

    #[test]
    fn removes_default_ports() {
        assert_eq!(
            normalize_url("http://example.com:80/post").unwrap(),
            "http://example.com/post"
        );
        assert_eq!(
            normalize_url("https://example.com:443/post").unwrap(),
            "https://example.com/post"
        );
    }

    #[test]
    fn preserves_non_default_port() {
        assert_eq!(
            normalize_url("https://example.com:8080/post").unwrap(),
            "https://example.com:8080/post"
        );
    }

    #[test]
    fn sorts_query_params() {
        // Different orderings of the same params must produce one string.
        let a = normalize_url("https://example.com/s?b=2&a=1").unwrap();
        let b = normalize_url("https://example.com/s?a=1&b=2").unwrap();
        assert_eq!(a, b);
        assert_eq!(a, "https://example.com/s?a=1&b=2");
    }

    #[test]
    fn www_and_tracking_combine() {
        // Full pipeline: www stripped, utm dropped, remaining params sorted.
        assert_eq!(
            normalize_url("https://www.example.com/s?utm_source=x&b=2&a=1#frag").unwrap(),
            "https://example.com/s?a=1&b=2"
        );
    }
}
