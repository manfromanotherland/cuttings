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
        .navigationTitle(navigationTitle)
        .task { await appState.loadReadings() }
        .toolbar { toolbarItems }
        .confirmationDialog(
            "Delete this reading?",
            isPresented: Binding(
                get: { appState.pendingDelete != nil },
                set: { if !$0 { appState.pendingDelete = nil } }
            ),
            presenting: appState.pendingDelete
        ) { row in
            Button("Delete", role: .destructive) {
                Task { await appState.delete(row) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text("“\(row.title.isEmpty ? row.url : row.title)” will be permanently removed from your library, including its files. This cannot be undone.")
        }
    }

    // ── List ──────────────────────────────────────────────────────────────

    private var list: some View {
        List(appState.readings, id: \.id, selection: $appState.selectedId) { row in
            ReadingRowView(row: row, snippet: snippet(for: row.id))
                .tag(row.id)
                .contextMenu { contextMenu(for: row) }
                .onAppear {
                    if row.id == appState.readings.last?.id {
                        Task { await appState.loadMoreReadings() }
                    }
                }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appState.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.background)
            }
        }
    }

    private func snippet(for id: String) -> String? {
        guard !appState.searchQuery.isEmpty else { return nil }
        return appState.searchResults.first(where: { $0.id == id })?.snippet
    }

    // ── Empty state ───────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .foregroundStyle(.secondary)
            if appState.selectedTag != nil {
                Button("Clear tag filter") {
                    Task { await appState.clearTag() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Toolbar ───────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.sortNewestFirst.toggle()
                Task { await appState.loadReadings() }
            } label: {
                Label(
                    appState.sortNewestFirst ? "Newest first" : "Oldest first",
                    systemImage: appState.sortNewestFirst ? "arrow.down" : "arrow.up"
                )
            }
            .help(appState.sortNewestFirst ? "Sort: newest first" : "Sort: oldest first")
        }
    }

    // ── Context menu ──────────────────────────────────────────────────────

    @ViewBuilder
    private func contextMenu(for row: FfiReadingRow) -> some View {
        Button(row.read ? "Mark as Unread" : "Mark as Read") {
            Task { await appState.toggleRead(row) }
        }
        .keyboardShortcut("u", modifiers: .command)

        Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
            Task { await appState.toggleFavorite(row) }
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])

        Divider()

        if row.archived {
            Button("Move to Library") {
                Task { await appState.unarchive(row) }
            }
        } else {
            Button("Archive") {
                Task { await appState.archive(row) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        Divider()

        Button("Delete…", role: .destructive) {
            appState.pendingDelete = row
        }
        .keyboardShortcut(.delete, modifiers: [.command, .option])
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private var navigationTitle: String {
        if !appState.searchQuery.isEmpty {
            let n = appState.readings.count
            return "\(n) result\(n == 1 ? "" : "s")"
        }
        if let tag = appState.selectedTag { return "#\(tag)" }
        return appState.activeView.label
    }
}

// ── Row ───────────────────────────────────────────────────────────────────────

struct ReadingRowView: View {
    let row: FfiReadingRow
    var snippet: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title + indicators
            HStack(alignment: .top, spacing: 6) {
                if !row.read {
                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                }
                Text(row.title.isEmpty ? row.url : row.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if row.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            // Site + date
            HStack(spacing: 6) {
                if let site = row.site, !site.isEmpty {
                    Text(site)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(relativeDate(row.savedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Snippet (search) or excerpt (browse)
            if let snippet {
                Text(snippet.strippingMarkTags())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            } else if let excerpt = row.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            // Tags
            if !row.tags.isEmpty {
                Text(row.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: .now)
    }
}

// ── String helper ─────────────────────────────────────────────────────────────

private extension String {
    /// Remove `<mark>` and `</mark>` tags produced by FTS5 snippet().
    func strippingMarkTags() -> String {
        replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
    }
}
