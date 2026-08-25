// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps the `ReadingSort` field to the core's `FfiSortField` query enum. Lives in
/// the bridge so the `Ffi*` boundary type stays out of the State layer (ADR 0001);
/// only `CoreBridge` reads this when building a query.
extension ReadingSort {
    var ffiSort: FfiSortField {
        switch self {
        case .relevance: .relevance
        case .savedAt: .savedAt
        }
    }
}
