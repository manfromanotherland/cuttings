// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, mono
    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .mono: "Monospace"
        }
    }

    /// SwiftUI font design used by the native reader.
    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum ReaderFontSize: Int, CaseIterable, Identifiable {
    case small = 15, medium = 17, large = 19, xlarge = 21, huge = 23, giant = 25
    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xlarge: "Extra Large"
        case .huge: "Huge"
        case .giant: "Giant"
        }
    }

    /// Base body point size for the native reader.
    var points: CGFloat {
        CGFloat(rawValue)
    }
}
