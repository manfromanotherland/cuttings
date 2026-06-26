// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The standard spacing, in points, between an icon and its text in any
/// icon+label pairing across the app. See DESIGN.md → "Icon–label spacing".
let iconLabelSpacing: CGFloat = 4

/// A label style that tightens the gap between the icon and its text to the
/// app-standard `iconLabelSpacing`. SwiftUI's default `Label` spacing is too
/// loose for the compact inline rows we use (header metadata, sidebar items,
/// tag rows), so apply `.labelStyle(.tightIcon)` to keep them consistent.
struct TightIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: iconLabelSpacing) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TightIconLabelStyle {
    static var tightIcon: TightIconLabelStyle { TightIconLabelStyle() }
}
