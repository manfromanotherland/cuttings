// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps the app's library scopes onto the compatible core view enum. Legacy
/// core view cases stay exported so older clients and libraries remain readable.
extension LibraryScope {
    var ffiView: FfiView {
        switch self {
        case .all: .all
        case .media: .media
        case .articles: .articles
        case .links: .links
        case .quotes: .quotes
        }
    }
}
