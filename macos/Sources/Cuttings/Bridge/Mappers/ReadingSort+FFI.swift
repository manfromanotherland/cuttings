// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps the `ReadingSort` field to the core's `FfiSortField` query enum. Lives in
/// the bridge so the `Ffi*` boundary type stays out of the State layer (ADR 0001);
/// only `CoreBridge` reads this when building a query. Note `timeToRead` maps to
/// the core's `wordCount` (reading time is derived from the word count).
extension ReadingSort {
    var ffiSort: FfiSortField {
        switch self {
        case .relevance: .relevance
        case .savedAt: .savedAt
        case .timeToRead: .wordCount
        }
    }
}
