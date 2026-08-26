// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Menu bar commands that operate on the currently selected item.
struct ArticleCommands: Commands {
    var appState: AppState
    @FocusedValue(\.detailNavigationActions) private var detailNavigationActions
    @FocusedValue(\.boardActions) private var boardActions

    var body: some Commands {
        CommandMenu("Item") {
            if !selectedRows.isEmpty {
                Button("Open") {
                    boardActions?.openSelection()
                }
                .keyboardShortcut(ShortcutCatalog.open)
                .disabled(boardActions?.canOpenSelection != true || appState.isEditingText)

                Divider()

                Button("Edit Tags…") {
                    appState.showTagSheet = true
                }
                .keyboardShortcut(ShortcutCatalog.editTags)
                .disabled(selectedRows.count != 1 || appState.isDeleting)

                Button(appState.showHighlights ? "Hide Highlights" : "Show Highlights") {
                    appState.showHighlights.toggle()
                }
                .keyboardShortcut(ShortcutCatalog.toggleHighlights)
                .disabled(
                    selectedRow?.kind != .article
                        || detailNavigationActions == nil
                )

                Divider()

                Button(deleteTitle, role: .destructive) {
                    appState.requestDeleteSelection()
                }
                .keyboardShortcut(ShortcutCatalog.delete)
                .disabled(appState.isEditingText || appState.isDeleting)

                Divider()

                if let url = selectedRow?.sourceURL {
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

    private var selectedRows: [ReadingRow] {
        appState.selectedRows
    }

    private var selectedRow: ReadingRow? {
        selectedRows.count == 1 ? selectedRows.first : nil
    }

    private var deleteTitle: String {
        selectedRows.count == 1 ? "Delete" : "Delete \(selectedRows.count) Items"
    }
}
