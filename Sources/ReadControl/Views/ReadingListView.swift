// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ReadingListView: View {
    @Environment(AppState.self) private var appState

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
        .navigationTitle(appState.isFocusMode ? "" : navigationTitle)
        .task { await appState.loadReadings() }
        .onChange(of: appState.sortField) { _, _ in
            Task { await appState.loadReadings() }
        }
        .onChange(of: appState.searchSort) { _, _ in
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
            Text("“\(row.title.isEmpty ? row.url : row.title)” will be permanently removed "
                + "from your library, including its files. This cannot be undone.")
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
            ReadingRowView(row: row)
                .tag(row.id)
                .accessibilityIdentifier(A11y.List.row(row.id))
                .contextMenu { contextMenu(for: row) }
                .onAppear {
                    if row.id == appState.readings.last?.id {
                        Task { await appState.loadMoreReadings() }
                    }
                }
        }
        .listStyle(.inset)
        .accessibilityIdentifier(A11y.List.table)
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

    // ── Empty state ───────────────────────────────────────────────────────

    @ViewBuilder
    private var emptyState: some View {
        if !appState.searchQuery.isEmpty {
            // System-provided, auto-localized "No Results for …" state.
            ContentUnavailableView.search(text: appState.searchQuery)
                .accessibilityIdentifier(A11y.List.searchEmptyState)
        } else if appState.selectedTag != nil {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "tray")
            } actions: {
                Button("Clear tag filter") {
                    Task { await appState.clearTag() }
                }
                .accessibilityIdentifier(A11y.List.clearTagFilter)
            }
            .accessibilityIdentifier(A11y.List.tagEmptyState)
        } else {
            ContentUnavailableView("Nothing here yet", systemImage: "tray")
                .accessibilityIdentifier(A11y.List.emptyState)
        }
    }

    // ── Toolbar ───────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        @Bindable var appState = appState
        if !appState.readings.isEmpty && !appState.isFocusMode {
            let searching = !appState.searchQuery.isEmpty
            let effectiveSort = searching ? appState.searchSort : appState.sortField
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // While searching, bind to `searchSort` (which offers
                    // Relevance) so the search order stays independent of the
                    // list's persisted sort field.
                    Picker("Sort By", selection: searching ? $appState.searchSort : $appState.sortField) {
                        ForEach(ReadingSort.options(searching: searching)) { field in
                            Text(field.label).tag(field)
                        }
                    }
                    // Relevance has no ascending/descending — hide the order picker.
                    if effectiveSort != .relevance {
                        Divider()
                        Picker("Order", selection: $appState.sortAscending) {
                            Text(effectiveSort.directionLabel(ascending: false)).tag(false)
                            Text(effectiveSort.directionLabel(ascending: true)).tag(true)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort readings")
                .accessibilityIdentifier(A11y.List.sortMenu)
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
            let count = appState.readings.count
            return "\(count) result\(count == 1 ? "" : "s")"
        }
        if let tag = appState.selectedTag { return "#\(tag)" }
        if let rating = appState.selectedRating {
            return String(repeating: "★", count: Int(rating))
        }
        return appState.activeView.label
    }
}

// ── Row ───────────────────────────────────────────────────────────────────────

struct ReadingRowView: View {
    let row: FfiReadingRow

    var body: some View {
        // The unread dot lives in its own fixed-width leading column so the
        // title, author and excerpt all share the same text column, aligned
        // whether or not the dot is present.
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.blue)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
                .opacity(row.read ? 0 : 1)
                .accessibilityLabel(row.read ? "" : "Unread")

            VStack(alignment: .leading, spacing: 4) {
                // Title + indicators
                HStack(alignment: .top, spacing: 6) {
                    Text(row.title.isEmpty ? row.url : row.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if row.favorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Favorite")
                    }
                }

                // Site + reading time
                HStack(spacing: 10) {
                    if let site = row.site, !site.isEmpty {
                        Text(site)
                            .lineLimit(1)
                    }
                    if let readingTime = row.readingTimeLabel {
                        Text(readingTime)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Excerpt
                if let excerpt = row.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
