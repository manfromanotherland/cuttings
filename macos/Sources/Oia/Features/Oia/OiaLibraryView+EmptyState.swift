// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension OiaLibraryView {
    @ViewBuilder
    var emptyState: some View {
        if appState.activeSearchInput.isActive {
            ContentUnavailableView.search(text: activeSearchDescription)
                .accessibilityIdentifier(A11y.List.searchEmptyState)
        } else if appState.activeScope != .all {
            ContentUnavailableView(
                "No \(appState.activeScope.label.lowercased()) here yet",
                systemImage: appState.activeScope.icon
            )
            .accessibilityIdentifier(A11y.List.emptyState)
        } else {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("Drop a link, text, image, or video here, or paste with ⌘V.")
            }
            .accessibilityIdentifier(A11y.List.emptyState)
        }
    }

    private var activeSearchDescription: String {
        let tokenValues = appState.activeSearchInput.criteria.tokens.map(\.value)
        return (tokenValues + [appState.activeSearchInput.text].compactMap(\.self))
            .joined(separator: " ")
    }
}
