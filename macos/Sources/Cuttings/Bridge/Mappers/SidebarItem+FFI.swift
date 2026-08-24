// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps the `SidebarItem` smart view to the core's `FfiView` query enum. Lives in
/// the bridge so the `Ffi*` boundary type stays out of the State layer (ADR 0001);
/// only `CoreBridge` reads this when building a query.
extension SidebarItem {
    var ffiView: FfiView {
        switch self {
        case .all: .all
        case .unread: .unread
        case .read: .read
        case .archive: .archive
        case .favorites: .favorites
        }
    }
}
