// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ReadingListView: View {
    @EnvironmentObject private var appState: AppState

    /// Shared with the sidebar so ← can hand focus back across to it.
    @FocusState.Binding var focusedColumn: FocusColumn?

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
        .onChange(of: appState.sortField) { _, _ in
            Task { await appState.loadReadings() }
        }
        .onChange(of: appState.sortAscending) { _, _ in
            Task { await appState.loadReadings() }
        }
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

    /// List selection that refuses to clear when the user clicks empty space.
    /// Keeping a row selected keeps the selection-dependent toolbar (sort +
    /// actions) stable. The selection is still cleared for an empty list — that
    /// path goes through `loadReadings()`, not this binding.
    private var listSelection: Binding<String?> {
        Binding(
            get: { appState.selectedId },
            set: { newValue in
                if newValue != nil { appState.selectedId = newValue }
            }
        )
    }

    private var list: some View {
        List(appState.readings, id: \.id, selection: listSelection) { row in
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
        .focused($focusedColumn, equals: .list)
        // ← hands focus back to the sidebar; ↑/↓ keep moving through the
        // readings. (→ into the reader isn't part of the arrow cycle.)
        .onKeyPress(.leftArrow) {
            focusedColumn = .sidebar
            return .handled
        }
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
        if !appState.readings.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $appState.sortField) {
                        ForEach(ReadingSort.allCases) { field in
                            Text(field.label).tag(field)
                        }
                    }
                    Divider()
                    Picker("Order", selection: $appState.sortAscending) {
                        Text(appState.sortField.directionLabel(ascending: false)).tag(false)
                        Text(appState.sortField.directionLabel(ascending: true)).tag(true)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort readings")
            }
        }
    }

    // ── Context menu ──────────────────────────────────────────────────────

    @ViewBuilder
    private func contextMenu(for row: FfiReadingRow) -> some View {
        Button(row.read ? "Mark as Unread" : "Mark as Read") {
            Task { await appState.toggleRead(row) }
        }
        .keyboardShortcut(ShortcutCatalog.toggleRead)

        Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
            Task { await appState.toggleFavorite(row) }
        }
        .keyboardShortcut(ShortcutCatalog.toggleFavorite)

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
            // ⌘⌫ is "delete to start of line" in a text field; yield to it while
            // editing so typing isn't hijacked into archiving.
            .disabled(appState.isEditingText)
        }

        Divider()

        Button("Delete", role: .destructive) {
            appState.pendingDelete = row
        }
        .keyboardShortcut(ShortcutCatalog.delete)
        .disabled(appState.isEditingText)
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private var navigationTitle: String {
        if !appState.searchQuery.isEmpty {
            let n = appState.readings.count
            return "\(n) result\(n == 1 ? "" : "s")"
        }
        if let tag = appState.selectedTag { return "#\(tag)" }
        if let r = appState.selectedRating { return String(repeating: "★", count: Int(r)) }
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
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Site + reading time
            HStack(spacing: 6) {
                if let site = row.site, !site.isEmpty {
                    Text(site)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let readingTime = row.readingTimeLabel {
                    Text(readingTime)
                }
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
