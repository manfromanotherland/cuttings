// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension CuttingsLibraryView {
    @ViewBuilder
    var emptyState: some View {
        if !appState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: appState.searchQuery)
                .accessibilityIdentifier(A11y.List.searchEmptyState)
        } else if appState.selectedTag != nil {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "sparkles.rectangle.stack")
            } actions: {
                Button("Clear tag filter") { Task { await appState.clearTag() } }
                    .accessibilityIdentifier(A11y.List.clearTagFilter)
            }
            .accessibilityIdentifier(A11y.List.tagEmptyState)
        } else if let kind = appState.selectedKind {
            ContentUnavailableView(
                "No \(kind.label.lowercased()) here yet", systemImage: kind.symbol
            )
            .accessibilityIdentifier(A11y.List.emptyState)
        } else {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("Drop a link, text, or image here, or paste with ⌘V.")
            }
            .accessibilityIdentifier(A11y.List.emptyState)
        }
    }
}
