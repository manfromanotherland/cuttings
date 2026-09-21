// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension ReadingRow {
    /// Estimated length as a short label (e.g. "5 min", or
    /// "1 hr 20 min" for longer articles), derived from the article's word
    /// count at an average adult silent reading speed of 200 wpm. Rounds up to a
    /// 1-minute minimum so any non-empty article has a length of at least "1 min".
    /// Returns `nil` when the word count is missing or zero.
    var readingTimeLabel: String? {
        guard let words = wordCount, words > 0 else { return nil }
        let wordsPerMinute = 200.0
        let minutes = max(1, Int((Double(words) / wordsPerMinute).rounded()))

        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remaining) min"
    }
}
