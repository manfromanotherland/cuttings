// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, mono
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .mono: "Monospace"
        }
    }

    var cssFamily: String {
        switch self {
        case .system: "system-ui, -apple-system, sans-serif"
        case .serif: "Georgia, 'New York', ui-serif, serif"
        case .mono: "'SF Mono', ui-monospace, 'Menlo', monospace"
        }
    }
}

enum ReaderFontSize: Int, CaseIterable, Identifiable {
    case small = 15, medium = 17, large = 19, xlarge = 21
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xlarge: "Extra Large"
        }
    }
}
