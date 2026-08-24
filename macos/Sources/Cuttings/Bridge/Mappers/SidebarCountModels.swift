// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Presentation snapshot of the tag data used by the app's filter menu. The
// compatible FFI payload still includes legacy view and rating counts, which the
// app deliberately ignores.

/// One library tag with its usage count under the active search/facet scope.
struct TagCount: Identifiable, Equatable, Sendable {
    var tag: String
    var count: UInt64
    var id: String {
        tag
    }
}

extension TagCount {
    init(_ ffi: FfiTagCount) {
        tag = ffi.tag
        count = ffi.count
    }
}
