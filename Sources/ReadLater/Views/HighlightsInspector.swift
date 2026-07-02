// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The right-side inspector column listing the open reading's highlights.
/// Highlights are created by selecting text in the reader and choosing
/// "Highlight" from the context menu; this panel lists them and lets the user
/// remove individual ones.
struct HighlightsInspector: View {
    @Environment(AppState.self) private var appState

    /// The reading whose highlights are shown. Highlights are scoped per
    /// reading, so deletions target this id.
    let readingId: String?

    var body: some View {
        Group {
            if appState.highlights.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Highlights")
    }

    private var list: some View {
        List {
            ForEach(appState.highlights, id: \.id) { highlight in
                HighlightRow(text: highlight.text) {
                    delete(highlight.id)
                }
                .listRowSeparator(.visible)
                .contextMenu {
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(highlight.text, forType: .string)
                    }
                    Button("Delete", role: .destructive) {
                        delete(highlight.id)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    delete(appState.highlights[index].id)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No highlights yet",
            systemImage: "highlighter",
            description: Text("Select text in the article and right-click to add one.")
        )
    }

    private func delete(_ highlightId: String) {
        guard let readingId else { return }
        Task { await appState.deleteHighlight(id: readingId, highlightId: highlightId) }
    }
}

private struct HighlightRow: View {
    let text: String
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.yellow.opacity(0.6))
                .frame(width: 3)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete highlight")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
