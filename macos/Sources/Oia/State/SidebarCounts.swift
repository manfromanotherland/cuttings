// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Lightweight filter metadata used by the board's tag picker. Counts remain in
/// the dormant FFI payload for compatibility, but the app only needs tag names.
struct LibraryFilters {
    var tags: [TagCount] = []
}
