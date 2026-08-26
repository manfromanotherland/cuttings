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

    /// Device-pixel ceiling for board previews. Cards do not benefit from the
    /// reader's much larger decode: matching the column width to the display
    /// scale keeps raster memory proportional to what can actually be shown.
    func previewMaxPixel(displayScale: CGFloat) -> CGFloat {
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        return min(1_024, max(512, minimumColumnWidth * scale))
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

    /// Convert a trackpad pinch into the same discrete density levels used by
    /// the toolbar and keyboard commands. Each 20% scale step advances one
    /// level; large gestures may cross several levels but always clamp to the
    /// existing range.
    func zoomed(by magnification: CGFloat) -> Self {
        guard magnification.isFinite, magnification > 0,
              let startingIndex = Self.allCases.firstIndex(of: self)
        else { return self }

        let scalePerStep: CGFloat = 1.2
        var remainingScale = magnification
        var targetIndex = startingIndex

        while remainingScale >= scalePerStep, targetIndex < Self.allCases.count - 1 {
            targetIndex += 1
            remainingScale /= scalePerStep
        }
        while remainingScale <= 1 / scalePerStep, targetIndex > 0 {
            targetIndex -= 1
            remainingScale *= scalePerStep
        }

        return Self.allCases[targetIndex]
    }
}
