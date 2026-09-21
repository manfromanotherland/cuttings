// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Deterministic, 26-character Crockford Base32 ids for fixtures.
///
/// Real ULIDs encode a timestamp so that lexicographic order equals creation
/// order; the app relies on that (the reading id is the filename stem, and the
/// default list order sorts by id descending). The core never validates the
/// *shape* of an incoming id, so a test only needs ids that are 26 Crockford
/// Base32 chars **and** sort in the intended order. `make(_:)` encodes a
/// sequence number left-padded with `0` (the lowest symbol), so a larger
/// sequence always sorts after a smaller one.
enum TestULID {
    /// Crockford Base32 alphabet (excludes I, L, O, U).
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let length = 26

    /// A 26-char id whose lexicographic order matches `sequence` (0-based).
    static func make(_ sequence: Int) -> String {
        precondition(sequence >= 0, "sequence must be non-negative")
        var value = sequence
        var suffix: [Character] = []
        repeat {
            suffix.append(alphabet[value % 32])
            value /= 32
        } while value > 0
        precondition(suffix.count <= length, "sequence too large to encode in 26 chars")
        let padding = String(repeating: "0", count: length - suffix.count)
        return padding + String(suffix.reversed())
    }
}
