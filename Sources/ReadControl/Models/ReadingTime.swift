// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension FfiReadingRow {
    /// Estimated reading time as a short label (e.g. "5 min read"), derived
    /// from the article's word count at an average adult silent reading speed
    /// of 200 wpm. Rounds up to a 1-minute minimum so any non-empty article
    /// reads as at least "1 min read". Returns `nil` when the word count is
    /// missing or zero.
    var readingTimeLabel: String? {
        guard let words = wordCount, words > 0 else { return nil }
        let wordsPerMinute = 200.0
        let minutes = max(1, Int((Double(words) / wordsPerMinute).rounded()))
        return "\(minutes) min read"
    }
}
