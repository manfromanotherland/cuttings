// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Validation rules for tag names, shared by the tag picker and its tests.
///
/// Mirrors cuttings-core's `MAX_TAG_LEN` so the client can reject an
/// over-long tag inline — before the core would reject it on write. The length
/// is measured in Unicode scalar values to match the core's `chars().count()`,
/// so both sides agree on exactly which names are too long.
enum TagRules {
    /// The longest a tag name may be, counted in Unicode scalar values.
    static let maxLength = 20

    /// Whether `name` is short enough to create. Callers pass the trimmed name,
    /// since the core measures length after trimming surrounding whitespace.
    static func isWithinLength(_ name: String) -> Bool {
        name.unicodeScalars.count <= maxLength
    }
}
