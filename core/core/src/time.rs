// SPDX-License-Identifier: MIT

//! Minimal UTC timestamp formatting, with no external date/time dependency.
//!
//! The whole system stores timestamps as UTC ISO-8601 strings with a `Z`
//! suffix and millisecond precision — the format produced by JavaScript's
//! `Date.prototype.toISOString()`, which is how the browser extension stamps
//! `saved_at`. `read_at` follows the same convention so the two sort and
//! display identically. The user's local timezone is applied only at the UI
//! layer (the macOS app), never on disk.

use std::time::{SystemTime, UNIX_EPOCH};

/// Current time as a UTC ISO-8601 string, e.g. `2026-06-24T15:30:00.123Z`.
pub fn now_utc_iso() -> String {
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    iso_from_unix_millis(dur.as_secs(), dur.subsec_millis())
}

/// Format a UNIX timestamp (whole seconds + milliseconds) as UTC ISO-8601.
fn iso_from_unix_millis(secs: u64, millis: u32) -> String {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (hh, mm, ss) = (rem / 3_600, (rem % 3_600) / 60, rem % 60);
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}.{millis:03}Z")
}

/// Convert a count of days since the UNIX epoch (1970-01-01) into a
/// proleptic-Gregorian `(year, month, day)`.
///
/// This is Howard Hinnant's well-known `civil_from_days` algorithm, valid for
/// the full range of dates we will ever see.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_formats_as_zero() {
        assert_eq!(iso_from_unix_millis(0, 0), "1970-01-01T00:00:00.000Z");
    }

    #[test]
    fn known_timestamp_formats_correctly() {
        // 1_700_000_000 == 2023-11-14T22:13:20Z (a widely-tabulated value).
        assert_eq!(
            iso_from_unix_millis(1_700_000_000, 123),
            "2023-11-14T22:13:20.123Z"
        );
    }

    #[test]
    fn leap_day_is_handled() {
        // 2024-02-29 00:00:00 UTC == 1_709_164_800.
        assert_eq!(
            iso_from_unix_millis(1_709_164_800, 0),
            "2024-02-29T00:00:00.000Z"
        );
    }

    #[test]
    fn now_has_expected_shape() {
        let s = now_utc_iso();
        // YYYY-MM-DDTHH:MM:SS.sssZ — 24 chars, ends in Z.
        assert_eq!(s.len(), 24, "unexpected length: {s}");
        assert!(s.ends_with('Z'));
        assert_eq!(&s[4..5], "-");
        assert_eq!(&s[10..11], "T");
    }
}
