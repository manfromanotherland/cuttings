// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// One action vocabulary used by both a card's context menu and its restrained
/// hover ellipsis. Mutations still flow through `AppState`; `onOptimisticChange`
/// lets an open overlay mirror the same next-frame change in its local snapshot.
struct CuttingsReadingActions: View {
    @Environment(AppState.self) private var appState

    let row: ReadingRow
    var onEditTags: () -> Void
    var onOptimisticChange: (ReadingRow) -> Void = { _ in }

    var body: some View {
        Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
            var updated = row
            updated.favorite.toggle()
            onOptimisticChange(updated)
            Task { await appState.toggleFavorite(row) }
        }
        .keyboardShortcut(ShortcutCatalog.toggleFavorite)

        Divider()

        Button("Edit Tags…") { onEditTags() }
            .keyboardShortcut(ShortcutCatalog.editTags)

        if let url = row.sourceURL {
            Button("Open Source") {
                ReadingLink.open(url)
            }
            .keyboardShortcut(ShortcutCatalog.openInBrowser)
        }

        Divider()

        Button("Delete", role: .destructive) {
            appState.pendingDelete = row
        }
        .keyboardShortcut(ShortcutCatalog.delete)
        .disabled(appState.isEditingText)
    }
}
