// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Per-device card density for the masonry board. The existing 220-point card
/// width is `small`; larger options widen cards and naturally reduce the number
/// of columns that fit in the window.
enum CardSize: String, CaseIterable, Identifiable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .extraLarge: "Extra Large"
        case .extraSmall: "Extra Small"
        case .large: "Large"
        case .medium: "Medium"
        case .small: "Small"
        }
    }

    var minimumColumnWidth: CGFloat {
        switch self {
        case .extraLarge: 540
        case .extraSmall: 180
        case .large: 400
        case .medium: 300
        case .small: 220
        }
    }

    var smaller: Self? {
        switch self {
        case .extraLarge: .large
        case .extraSmall: nil
        case .large: .medium
        case .medium: .small
        case .small: .extraSmall
        }
    }

    var larger: Self? {
        switch self {
        case .extraLarge: nil
        case .extraSmall: .small
        case .large: .extraLarge
        case .medium: .large
        case .small: .medium
        }
    }
}
