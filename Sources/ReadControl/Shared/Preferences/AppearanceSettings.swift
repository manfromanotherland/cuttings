// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }

    /// The AppKit appearance to force on the whole application. `nil` means
    /// follow the OS. Driving `NSApplication.shared.appearance` (rather than
    /// only SwiftUI's `preferredColorScheme`) keeps the window chrome and the
    /// SwiftUI content in lockstep — otherwise switching back to System leaves
    /// the content light while the chrome stays on the previously-forced theme.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
