// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Lightweight filter metadata used by the board's tag picker. Counts remain in
/// the dormant FFI payload for compatibility, but the app only needs tag names.
struct LibraryFilters {
    let tags: [TagCount]
    let searchTagCandidates: [BoardSearchTagCandidate]

    init(tags: [TagCount] = []) {
        self.tags = tags

        var seen = Set<BoardSearchToken.Identifier>()
        searchTagCandidates = tags.compactMap { tag in
            guard let candidate = BoardSearchTagCandidate(value: tag.tag),
                  seen.insert(candidate.id).inserted else { return nil }
            return candidate
        }
    }
}
