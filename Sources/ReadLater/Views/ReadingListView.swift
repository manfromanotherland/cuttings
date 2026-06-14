// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ReadingListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.readings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(appState.activeView.label)
        .task { await appState.loadReadings() }
    }

    private var list: some View {
        List(appState.readings, id: \.id, selection: $appState.selectedId) { row in
            ReadingRowView(row: row)
                .tag(row.id)
                .contextMenu { contextMenu(for: row) }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for row: FfiReadingRow) -> some View {
        Button(row.read ? "Mark as Unread" : "Mark as Read") {
            Task { await appState.toggleRead(row) }
        }
        Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
            Task { await appState.toggleFavorite(row) }
        }
        Divider()
        Button("Archive") {
            Task { await appState.archive(row) }
        }
    }
}

// ── Row ───────────────────────────────────────────────────────────────────────

private struct ReadingRowView: View {
    let row: FfiReadingRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.title.isEmpty ? row.url : row.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if row.favorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                if !row.read {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
            if let site = row.site, !site.isEmpty {
                Text(site)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !row.tags.isEmpty {
                Text(row.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
