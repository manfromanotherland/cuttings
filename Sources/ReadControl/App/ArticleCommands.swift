// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Menu bar commands that operate on the currently selected article.
struct ArticleCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("Article") {
            if let row = selectedRow {
                Button(row.read ? "Mark as Unread" : "Mark as Read") {
                    Task { await appState.toggleRead(row) }
                }
                .keyboardShortcut(ShortcutCatalog.toggleRead)

                Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
                    Task { await appState.toggleFavorite(row) }
                }
                .keyboardShortcut(ShortcutCatalog.toggleFavorite)

                Divider()

                Button("Edit Tags…") {
                    appState.showTagSheet = true
                }
                .keyboardShortcut(ShortcutCatalog.editTags)

                Button(appState.showHighlights ? "Hide Highlights" : "Show Highlights") {
                    appState.showHighlights.toggle()
                }
                .keyboardShortcut(ShortcutCatalog.toggleHighlights)

                Divider()

                if row.archived {
                    Button("Move to Library") {
                        Task { await appState.unarchive(row) }
                    }
                } else {
                    Button("Archive") {
                        Task { await appState.archive(row) }
                    }
                    .keyboardShortcut(ShortcutCatalog.archive)
                    // ⌘⌫ is "delete to start of line" in a text field; yield to it
                    // while editing so typing isn't hijacked into archiving.
                    .disabled(appState.isEditingText)
                }

                Button("Delete", role: .destructive) {
                    appState.pendingDelete = row
                }
                .keyboardShortcut(ShortcutCatalog.delete)
                .disabled(appState.isEditingText)

                Divider()

                Button("Open in Browser") {
                    if let url = URL(string: row.url) {
                        ReadingLink.open(url)
                    }
                }
                .keyboardShortcut(ShortcutCatalog.openInBrowser)
            } else {
                Text("No article selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedRow: FfiReadingRow? {
        guard let id = appState.selectedId else { return nil }
        return appState.readings.first(where: { $0.id == id })
    }
}
