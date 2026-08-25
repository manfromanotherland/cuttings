// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Menu bar commands that operate on the currently selected item.
struct ArticleCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("Item") {
            if let row = selectedRow {
                Button("Edit Tags…") {
                    appState.showTagSheet = true
                }
                .keyboardShortcut(ShortcutCatalog.editTags)

                Button(appState.showHighlights ? "Hide Highlights" : "Show Highlights") {
                    appState.showHighlights.toggle()
                }
                .keyboardShortcut(ShortcutCatalog.toggleHighlights)

                Divider()

                Button("Delete", role: .destructive) {
                    appState.pendingDelete = row
                }
                .keyboardShortcut(ShortcutCatalog.delete)
                .disabled(appState.isEditingText)

                Divider()

                if let url = row.sourceURL {
                    Button("Open in Browser") {
                        ReadingLink.open(url)
                    }
                    .keyboardShortcut(ShortcutCatalog.openInBrowser)
                }
            } else {
                Text("No item selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedRow: ReadingRow? {
        guard let id = appState.selectedId else { return nil }
        return appState.readings.first(where: { $0.id == id })
    }
}
