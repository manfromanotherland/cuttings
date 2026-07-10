// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The reader's primary-action toolbar: read/favorite/archive, open in
/// browser, tags, highlights, delete. The parent resolves which row to build
/// it for (see `ArticleDetailView.currentRow`); actions write through
/// `appState`, whose refresh supplies the updated row on the next render.
struct ArticleToolbar: ToolbarContent {
    let row: FfiReadingRow
    let appState: AppState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                // Optimistic via the parent's `currentRow`; on a selection
                // advance `onChange(selectedId)` reloads the detail — so no
                // row reload here, which would fight that advance.
                Task { await appState.toggleRead(row) }
            } label: {
                Label(
                    row.read ? "Mark Unread" : "Mark Read",
                    systemImage: row.read ? "circle" : "checkmark.circle"
                )
            }
            .help(row.read ? "Mark as unread" : "Mark as read")

            Button {
                Task { await appState.toggleFavorite(row) }
            } label: {
                Label(
                    row.favorite ? "Unfavorite" : "Favorite",
                    systemImage: row.favorite ? "heart.fill" : "heart"
                )
            }
            .help(row.favorite ? "Remove from favorites" : "Add to favorites")

            if row.archived {
                Button {
                    Task { await appState.unarchive(row) }
                } label: {
                    Label("Move to Library", systemImage: "tray.and.arrow.up")
                }
                .help("Move back to library")
            } else {
                Button {
                    Task { await appState.archive(row) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive this article")
            }

            Button {
                if let url = URL(string: row.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .help("Open original URL")

            Button {
                appState.showTagSheet = true
            } label: {
                Label("Tags", systemImage: "number")
            }
            .help("Edit tags")

            Button {
                appState.showHighlights.toggle()
            } label: {
                Label("Highlights", systemImage: "highlighter")
            }
            .help("Show highlights")

            Button(role: .destructive) {
                appState.pendingDelete = row
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Permanently delete this reading")
        }
    }
}
