// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Per-device card density for the masonry board. The existing 220-point card
/// width is `small`; larger options widen cards and naturally reduce the number
/// of columns that fit in the window.
enum CardSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .large: "Large"
        case .medium: "Medium"
        case .small: "Small"
        }
    }

    var minimumColumnWidth: CGFloat {
        switch self {
        case .large: 400
        case .medium: 300
        case .small: 220
        }
    }

    var smaller: Self? {
        switch self {
        case .large: .medium
        case .medium: .small
        case .small: nil
        }
    }

    var larger: Self? {
        switch self {
        case .large: nil
        case .medium: .large
        case .small: .medium
        }
    }
}
