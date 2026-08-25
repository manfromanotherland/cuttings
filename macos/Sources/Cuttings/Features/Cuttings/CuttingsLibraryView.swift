// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct CuttingsLibraryView: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("cardSize", store: AppDefaults.store) private var cardSize: CardSize = .small

    @State private var presentedReading: ReadingRow?
    @State private var presentationOrder: [String] = []
    @State private var tagTargetID: String?
    @State private var isDropTargeted = false

    var body: some View {
        NavigationStack {
            deletionSurface
                .navigationDestination(isPresented: detailPresented) {
                    overlay
                }
        }
        .alert("Cuttings couldn’t complete that action", isPresented: errorAlertPresented) {
            Button("OK") { appState.error = nil }
        } message: {
            Text(appState.error ?? "An unknown error occurred.")
        }
    }
}

extension CuttingsLibraryView {
    private var layeredSurface: some View {
        ZStack {
            librarySurface

            if isDropTargeted {
                dropPrompt
            }

            if let notice = appState.saveNotice {
                saveNotice(notice)
            }
        }
    }

    private var ingestibleSurface: some View {
        layeredSurface
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
    }

    private var reactiveSurface: some View {
        ingestibleSurface
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
    }

    private var presentedSurface: some View {
        reactiveSurface
            .sheet(isPresented: tagSheetPresented) {
                tagPicker
            }
    }

    private var deletionSurface: some View {
        presentedSurface
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
    }
}

extension CuttingsLibraryView {
    private var librarySurface: some View {
        detailSurface
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
        if presentedReading == nil {
            ToolbarItemGroup(placement: .primaryAction) {
                favoritesToggle
                filterMenu
                cardSizeControl
                sortMenu
            }
        }
    }

    private var favoritesToggle: some View {
        let showingFavorites = appState.activeScope == .favorites

        return Button {
            appState.selectScope(showingFavorites ? .all : .favorites)
        } label: {
            Label(
                showingFavorites ? "Show all" : "Favorites",
                systemImage: showingFavorites ? "heart.fill" : "heart"
            )
        }
        .accessibilityLabel(showingFavorites ? "Show all cuttings" : "Show favorites")
        .accessibilityValue(showingFavorites ? "On" : "Off")
        .accessibilityIdentifier(A11y.Filter.favorites)
        .help(showingFavorites ? "Show all cuttings" : "Show favorites")
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

            if !appState.filters.tags.isEmpty {
                Divider()

                Picker("Tag", selection: tagSelection) {
                    Text("Any Tag").tag(nil as String?)
                    ForEach(appState.filters.tags, id: \.tag) { item in
                        Text("#\(item.tag)")
                            .tag(item.tag as String?)
                            .accessibilityIdentifier(A11y.Filter.tag(item.tag))
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
        .accessibilityIdentifier(A11y.Filter.menu)
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

    private var cardSizeControl: some View {
        ControlGroup("Card Size") {
            Button {
                if let smaller = cardSize.smaller {
                    cardSize = smaller
                }
            } label: {
                Label("Decrease Card Size", systemImage: "minus")
            }
            .disabled(cardSize.smaller == nil)
            .help("Decrease card size (\(ShortcutCatalog.decreaseCardSize.display))")

            Button {
                if let larger = cardSize.larger {
                    cardSize = larger
                }
            } label: {
                Label("Increase Card Size", systemImage: "plus")
            }
            .disabled(cardSize.larger == nil)
            .help("Increase card size (\(ShortcutCatalog.increaseCardSize.display))")
        }
        .controlGroupStyle(.navigation)
        .labelStyle(.iconOnly)
        .accessibilityValue(cardSize.label)
        .accessibilityIdentifier(A11y.List.cardSizeControl)
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
                    LazyVStack(spacing: Self.boardSpacing) {
                        MasonryLayout(
                            minimumColumnWidth: cardSize.minimumColumnWidth,
                            spacing: Self.boardSpacing,
                            maximumColumns: 6
                        ) {
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
                                .padding(.vertical, Self.boardSpacing)
                                .onAppear {
                                    Task { await appState.loadMoreReadings() }
                                }
                        }
                    }
                    .frame(width: contentWidth)
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : .smooth(duration: 0.3, extraBounce: 0),
                        value: cardSize
                    )
                    .padding(.horizontal, Self.boardSpacing)
                    .padding(.bottom, Self.boardSpacing)
                    .padding(.top, Self.boardTopSpacing)
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
                rows: presentationRows,
                onClose: closeOverlay,
                onMove: moveOverlay,
                onSelect: open,
                canMovePrevious: canMoveOverlay(-1),
                canMoveNext: canMoveOverlay(1),
                onEditTags: { tagTargetID = row.id }
            )
        }
    }

    @ViewBuilder
    private var tagPicker: some View {
        if let row = tagTargetRow {
            TagPickerSheet(
                applied: row.tags,
                allTags: appState.filters.tags.map(\.tag),
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

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { presentedReading != nil },
            set: { isPresented in
                if !isPresented {
                    closeOverlay()
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
        appState.selectedKind != nil || appState.selectedTag != nil
    }

    private static let boardSpacing: CGFloat = 18
    private static let boardTopSpacing: CGFloat = 12

    private var tagTargetRow: ReadingRow? {
        let id = tagTargetID ?? (appState.showTagSheet ? appState.selectedId : nil)
        guard let id else { return nil }
        return appState.readings.first(where: { $0.id == id })
            ?? (presentedReading?.id == id ? presentedReading : nil)
    }

    private var presentationRows: [ReadingRow] {
        let rowsByID = appState.readings.reduce(into: [String: ReadingRow]()) { result, row in
            result[row.id] = row
        }
        return presentationOrder.compactMap { id in
            if presentedReading?.id == id {
                return presentedReading
            }
            return rowsByID[id]
        }
    }

    private func finiteBoardWidth(for proposedWidth: CGFloat) -> CGFloat {
        let horizontalPadding = Self.boardSpacing * 2
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

    private func canMoveOverlay(_ direction: Int) -> Bool {
        guard let id = presentedReading?.id,
              let index = presentationOrder.firstIndex(of: id) else { return false }
        var next = index + direction
        while presentationOrder.indices.contains(next) {
            if appState.readings.contains(where: { $0.id == presentationOrder[next] }) {
                return true
            }
            next += direction
        }
        return false
    }

    private func updatePresentedReading(_ updated: ReadingRow) {
        if presentedReading?.id == updated.id {
            presentedReading = updated
        }
    }

    private func updateTag(_ tag: String, applies: Bool, to row: ReadingRow) {
        let removesPresentedRowFromActiveTag = !applies
            && appState.selectedTag == tag
            && presentedReading?.id == row.id

        if removesPresentedRowFromActiveTag {
            tagTargetID = nil
            appState.showTagSheet = false
            advanceOverlayPastCurrent()
        } else if var presented = presentedReading, presented.id == row.id {
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

    private func advanceOverlayPastCurrent() {
        if canMoveOverlay(1) {
            moveOverlay(1)
        } else if canMoveOverlay(-1) {
            moveOverlay(-1)
        } else {
            closeOverlay()
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
