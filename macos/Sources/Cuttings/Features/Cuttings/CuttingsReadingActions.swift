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
        Button(row.read ? "Mark as Unread" : "Mark as Read") {
            var updated = row
            updated.read.toggle()
            onOptimisticChange(updated)
            Task { await appState.toggleRead(row) }
        }
        .keyboardShortcut(ShortcutCatalog.toggleRead)

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

        ratingMenu

        Divider()

        if row.archived {
            Button("Move to Library") {
                var updated = row
                updated.archived = false
                onOptimisticChange(updated)
                Task { await appState.unarchive(row) }
            }
        } else {
            Button("Archive") {
                var updated = row
                updated.archived = true
                onOptimisticChange(updated)
                Task { await appState.archive(row) }
            }
            .keyboardShortcut(ShortcutCatalog.archive)
            .disabled(appState.isEditingText)
        }

        Button("Open Source") {
            if let url = URL(string: row.url) {
                ReadingLink.open(url)
            }
        }
        .keyboardShortcut(ShortcutCatalog.openInBrowser)

        Divider()

        Button("Delete", role: .destructive) {
            appState.pendingDelete = row
        }
        .keyboardShortcut(ShortcutCatalog.delete)
        .disabled(appState.isEditingText)
    }

    private var ratingMenu: some View {
        Menu("Rating") {
            Button("Unrated") { setRating(0) }
            Divider()
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    setRating(UInt8(value))
                } label: {
                    Label(
                        String(repeating: "★", count: value),
                        systemImage: Int(row.rating) == value ? "checkmark" : "star"
                    )
                }
            }
        }
    }

    private func setRating(_ rating: UInt8) {
        var updated = row
        updated.rating = rating
        onOptimisticChange(updated)
        Task { await appState.setRating(id: row.id, rating: rating) }
    }
}
