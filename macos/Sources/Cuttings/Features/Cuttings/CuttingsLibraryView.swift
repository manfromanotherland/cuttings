// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct CuttingsLibraryView: View {
    @Environment(AppState.self) var appState

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var presentedReading: ReadingRow?
    @State private var presentationOrder: [String] = []
    @State private var tagTargetID: String?
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            librarySurface

            if presentedReading != nil {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture(perform: closeOverlay)

                overlay
                    .padding(18)
                    .transition(.scale(scale: 0.985).combined(with: .opacity))
            }

            if isDropTargeted {
                dropPrompt
            }

            if let notice = appState.saveNotice {
                saveNotice(notice)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presentedReading?.id)
        .onDrop(of: supportedDropTypes, isTargeted: $isDropTargeted) { providers in
            guard !providers.isEmpty else { return false }
            save(providers)
            return true
        }
        .onPasteCommand(
            of: supportedPasteTypes,
            validator: { providers in
                appState.isEditingText || providers.isEmpty ? nil : providers
            },
            perform: save
        )
        .background { rowsProbe }
        .task { await appState.loadReadings() }
        .onChange(of: appState.isFocusMode, initial: true) { _, isFocusMode in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = isFocusMode ? .detailOnly : .all
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            if appState.isFocusMode, visibility != .detailOnly {
                appState.isFocusMode = false
            }
        }
        .onChange(of: appState.searchQuery) { _, _ in
            appState.searchDidChange()
        }
        .onChange(of: appState.sortField) { _, _ in
            Task { await appState.loadReadings() }
        }
        .onChange(of: appState.searchSort) { _, _ in
            Task { await appState.loadReadings() }
        }
        .onChange(of: appState.sortAscending) { _, _ in
            Task { await appState.loadReadings() }
        }
        .onChange(of: appState.readings) { _, rows in
            guard let id = presentedReading?.id,
                  let refreshed = rows.first(where: { $0.id == id }) else { return }
            presentedReading = refreshed
        }
        .sheet(isPresented: tagSheetPresented) {
            tagPicker
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: deleteDialogPresented,
            presenting: appState.pendingDelete
        ) { row in
            Button("Delete", role: .destructive) {
                delete(row)
            }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text("“\(row.displayTitle)” and its local files will be permanently deleted.")
        }
        .alert("Cuttings couldn’t complete that action", isPresented: errorAlertPresented) {
            Button("OK") { appState.error = nil }
        } message: {
            Text(appState.error ?? "An unknown error occurred.")
        }
    }
}

extension CuttingsLibraryView {
    private var librarySurface: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: activeViewSelection) {
                Section("Library") {
                    ForEach(SidebarItem.allCases) { item in
                        sidebarRow(item)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Cuttings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detailSurface
        }
    }

    @ViewBuilder
    private var detailSurface: some View {
        if appState.isFocusMode {
            board
        } else {
            board
                .searchable(
                    text: searchQuery,
                    placement: .toolbar,
                    prompt: "Search Cuttings"
                )
                .toolbar { boardToolbar }
        }
    }

    @ToolbarContentBuilder
    private var boardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu
            sortMenu
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Kind", selection: kindSelection) {
                Text("Everything").tag(nil as ReadingKind?)
                ForEach(ReadingKind.allCases, id: \.self) { kind in
                    Label(kind.label, systemImage: kind.symbol)
                        .tag(kind as ReadingKind?)
                }
            }

            Divider()

            Picker("Rating", selection: ratingSelection) {
                Text("Any Rating").tag(nil as UInt8?)
                ForEach(1 ... 5, id: \.self) { value in
                    Text("\(value) star\(value == 1 ? "" : "s")")
                        .tag(UInt8(value) as UInt8?)
                        .accessibilityIdentifier(A11y.Sidebar.ratingRow(UInt8(value)))
                }
            }

            if !appState.sidebar.tags.isEmpty {
                Divider()

                Picker("Tag", selection: tagSelection) {
                    Text("Any Tag").tag(nil as String?)
                    ForEach(appState.sidebar.tags, id: \.tag) { item in
                        Text("#\(item.tag)")
                            .tag(item.tag as String?)
                            .accessibilityIdentifier(A11y.Sidebar.tagTile(item.tag))
                    }
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter cuttings")
    }

    private var sortMenu: some View {
        let searching = !appState.searchQuery.isEmpty
        let effectiveSort = searching ? appState.searchSort : appState.sortField

        return Menu {
            Picker("Sort By", selection: searching ? searchSortSelection : sortFieldSelection) {
                ForEach(ReadingSort.options(searching: searching)) { field in
                    Text(field.label).tag(field)
                }
            }

            if effectiveSort != .relevance {
                Divider()
                Picker("Order", selection: sortAscendingSelection) {
                    Text(effectiveSort.directionLabel(ascending: false)).tag(false)
                    Text(effectiveSort.directionLabel(ascending: true)).tag(true)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort cuttings")
        .accessibilityIdentifier(A11y.List.sortMenu)
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let count = appState.sidebar.viewCounts[item] ?? 0

        return HStack {
            Label(item.label, systemImage: item.icon)
            Spacer()
            if count > 0 {
                Text(count > 999 ? "999+" : "\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier(A11y.Sidebar.viewCount(item.id))
            }
        }
        .accessibilityValue("\(count)")
        .accessibilityIdentifier(A11y.Sidebar.viewRow(item.id))
    }

    @ViewBuilder
    private var board: some View {
        if appState.isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.readings.isEmpty {
            emptyState
        } else {
            GeometryReader { proxy in
                let contentWidth = finiteBoardWidth(for: proxy.size.width)

                ScrollView {
                    LazyVStack(spacing: 22) {
                        MasonryLayout(minimumColumnWidth: 220, spacing: 18, maximumColumns: 6) {
                            ForEach(appState.readings) { row in
                                CuttingsCardView(
                                    row: row,
                                    onOpen: { open(row) },
                                    onEditTags: { tagTargetID = row.id },
                                    onOptimisticChange: updatePresentedReading
                                )
                                .accessibilityIdentifier(A11y.List.row(row.id))
                            }
                        }

                        if appState.hasMoreReadings {
                            ProgressView()
                                .padding(.vertical, 18)
                                .onAppear {
                                    Task { await appState.loadMoreReadings() }
                                }
                        }
                    }
                    .frame(width: contentWidth)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 42)
                }
                .accessibilityIdentifier(A11y.List.table)
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if let row = presentedReading {
            CuttingsReadingOverlay(
                row: Binding(
                    get: { presentedReading ?? row },
                    set: { presentedReading = $0 }
                ),
                onClose: closeOverlay,
                onMove: moveOverlay,
                onEditTags: { tagTargetID = row.id }
            )
        }
    }

    @ViewBuilder
    private var tagPicker: some View {
        if let row = tagTargetRow {
            TagPickerSheet(
                applied: row.tags,
                allTags: appState.sidebar.tags.map(\.tag),
                onToggle: { tag, shouldApply in
                    updateTag(tag, applies: shouldApply, to: row)
                }
            )
        } else {
            ContentUnavailableView("Item unavailable", systemImage: "exclamationmark.triangle")
                .frame(width: 380, height: 460)
        }
    }

    private var rowsProbe: some View {
        let ids = appState.readings.map(\.id)
        return Text(verbatim: "\(ids.count)")
            .foregroundStyle(.clear)
            .accessibilityIdentifier(A11y.List.rows)
            .accessibilityValue(ids.joined(separator: ","))
    }

    private var tagSheetPresented: Binding<Bool> {
        Binding(
            get: { tagTargetID != nil || appState.showTagSheet },
            set: { showing in
                if !showing {
                    tagTargetID = nil
                    appState.showTagSheet = false
                }
            }
        )
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { appState.pendingDelete != nil },
            set: {
                if !$0 {
                    appState.pendingDelete = nil
                }
            }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { appState.error != nil },
            set: { showing in
                if !showing {
                    appState.error = nil
                }
            }
        )
    }

    private var activeViewSelection: Binding<SidebarItem?> {
        Binding(
            get: { appState.activeView },
            set: { item in
                guard let item, item != appState.activeView else { return }
                appState.selectView(item)
            }
        )
    }

    private var searchQuery: Binding<String> {
        Binding(
            get: { appState.searchQuery },
            set: { appState.searchQuery = $0 }
        )
    }

    private var kindSelection: Binding<ReadingKind?> {
        Binding(
            get: { appState.selectedKind },
            set: { appState.selectKind($0) }
        )
    }

    private var ratingSelection: Binding<UInt8?> {
        Binding(
            get: { appState.selectedRating },
            set: { rating in
                guard rating != appState.selectedRating else { return }
                if let rating {
                    appState.toggleRating(rating)
                } else if let current = appState.selectedRating {
                    appState.toggleRating(current)
                }
            }
        )
    }

    private var tagSelection: Binding<String?> {
        Binding(
            get: { appState.selectedTag },
            set: { tag in
                guard tag != appState.selectedTag else { return }
                if let tag {
                    appState.toggleTag(tag)
                } else if let current = appState.selectedTag {
                    appState.toggleTag(current)
                }
            }
        )
    }

    private var sortFieldSelection: Binding<ReadingSort> {
        Binding(
            get: { appState.sortField },
            set: { appState.sortField = $0 }
        )
    }

    private var searchSortSelection: Binding<ReadingSort> {
        Binding(
            get: { appState.searchSort },
            set: { appState.searchSort = $0 }
        )
    }

    private var sortAscendingSelection: Binding<Bool> {
        Binding(
            get: { appState.sortAscending },
            set: { appState.sortAscending = $0 }
        )
    }

    private var hasActiveFilters: Bool {
        appState.selectedKind != nil || appState.selectedRating != nil || appState.selectedTag != nil
    }

    private var tagTargetRow: ReadingRow? {
        let id = tagTargetID ?? (appState.showTagSheet ? appState.selectedId : nil)
        guard let id else { return nil }
        return appState.readings.first(where: { $0.id == id })
            ?? (presentedReading?.id == id ? presentedReading : nil)
    }

    private func finiteBoardWidth(for proposedWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 60
        guard proposedWidth.isFinite, proposedWidth > horizontalPadding else { return 220 }
        return max(220, proposedWidth - horizontalPadding)
    }

    private func open(_ row: ReadingRow) {
        if presentedReading == nil {
            presentationOrder = appState.readings.map(\.id)
        }
        appState.selectedId = row.id
        presentedReading = row
    }

    private func closeOverlay() {
        presentedReading = nil
        presentationOrder = []
        appState.showHighlights = false
    }

    private func moveOverlay(_ direction: Int) {
        guard let id = presentedReading?.id,
              let index = presentationOrder.firstIndex(of: id) else { return }
        var next = index + direction
        while presentationOrder.indices.contains(next) {
            if let row = appState.readings.first(where: { $0.id == presentationOrder[next] }) {
                open(row)
                return
            }
            next += direction
        }
    }

    private func updatePresentedReading(_ updated: ReadingRow) {
        if presentedReading?.id == updated.id {
            presentedReading = updated
        }
    }

    private func updateTag(_ tag: String, applies: Bool, to row: ReadingRow) {
        if var presented = presentedReading, presented.id == row.id {
            if applies, !presented.tags.contains(tag) {
                presented.tags.append(tag)
            } else if !applies {
                presented.tags.removeAll { $0 == tag }
            }
            presentedReading = presented
        }
        Task {
            if applies {
                await appState.addTag(id: row.id, tag: tag)
            } else {
                await appState.removeTag(id: row.id, tag: tag)
            }
            if presentedReading?.id == row.id {
                presentedReading = await appState.reloadRow(id: row.id) ?? presentedReading
            }
        }
    }

    private func delete(_ row: ReadingRow) {
        appState.pendingDelete = nil
        if presentedReading?.id == row.id {
            closeOverlay()
        }
        Task { await appState.delete(row) }
    }
}
