// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The reader's primary-action toolbar: read/favorite/archive, open in
/// browser, tags, highlight, delete. The parent resolves which row to build
/// it for (see `ArticleDetailView.currentRow`); actions write through
/// `appState`, whose refresh supplies the updated row on the next render.
struct ArticleToolbar: ToolbarContent {
    let row: ReadingRow
    let appState: AppState

    var body: some ToolbarContent {
        // Local binding for the hint popover; `appState` is a plain stored
        // reference here, not an `@Environment` value.
        @Bindable var appState = appState
        ToolbarItemGroup(placement: .primaryAction) {
            // A `Spacer` in a macOS toolbar is an expanding flexible space; it
            // pushes these actions to the trailing edge (far right).
            Spacer()

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
            .accessibilityIdentifier(A11y.Toolbar.markRead)

            Button {
                Task { await appState.toggleFavorite(row) }
            } label: {
                Label(
                    row.favorite ? "Unfavorite" : "Favorite",
                    systemImage: row.favorite ? "heart.fill" : "heart"
                )
            }
            .help(row.favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier(A11y.Toolbar.favorite)

            if row.archived {
                Button {
                    Task { await appState.unarchive(row) }
                } label: {
                    Label("Move to Library", systemImage: "tray.and.arrow.up")
                }
                .help("Move back to library")
                .accessibilityIdentifier(A11y.Toolbar.unarchive)
            } else {
                Button {
                    Task { await appState.archive(row) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive this article")
                .accessibilityIdentifier(A11y.Toolbar.archive)
            }

            Button {
                if let url = URL(string: row.url) {
                    ReadingLink.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .help("Open original URL")
            .accessibilityIdentifier(A11y.Toolbar.openInBrowser)

            Button {
                appState.showTagSheet = true
            } label: {
                Label("Tags", systemImage: "number")
            }
            .help("Edit tags")
            .accessibilityIdentifier(A11y.Toolbar.tags)

            Button {
                // Toggles, like the reader's context-menu command: pressing it
                // over an already-highlighted passage clears it. The inspector is
                // reached from the Article menu (⌘⇧H) instead.
                if !appState.highlightSelection() {
                    appState.showHighlightHint = true
                }
            } label: {
                Label("Highlight", systemImage: "highlighter")
            }
            .help("Highlight the selected text")
            .accessibilityIdentifier(A11y.Toolbar.highlight)
            .popover(isPresented: $appState.showHighlightHint, arrowEdge: .bottom) {
                Text("Select some text in the article to highlight it.")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier(A11y.Toolbar.highlightHint)
            }

            Button(role: .destructive) {
                appState.pendingDelete = row
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Permanently delete this reading")
            .accessibilityIdentifier(A11y.Toolbar.delete)

            Button {
                appState.isFocusMode.toggle()
            } label: {
                Label(
                    appState.isFocusMode ? "Exit Focus" : "Focus",
                    systemImage: appState.isFocusMode
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }
            .keyboardShortcut(ShortcutCatalog.toggleFocusMode)
            .help(appState.isFocusMode ? "Exit focus mode" : "Enter focus mode")
        }
    }
}
