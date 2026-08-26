// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct CuttingsLibraryView: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("cardSize", store: AppDefaults.store) var cardSize: CardSize = .small

    @State var presentedReading: ReadingRow?
    @State private var presentationOrder: [String] = []
    @State private var tagTargetID: String?
    @State private var isDropTargeted = false
    @State private var cardTextMetrics = CuttingsCardTextMetrics()
    @State private var videoPlaybackPositions = VideoPlaybackPositionStore()
    @State var boardPosition = LazyLayoutPosition<String>()
    @State var boardNavigation = MasonryNavigationCoordinator<ReadingRow, String>()
    @State var boardModifierKeys: EventModifiers = []
    @State var pinchStartCardSize: CardSize?
    @State var quickLookURL: URL?
    @FocusState var boardFocused: Bool
    @FocusState var searchFocused: Bool

    var body: some View {
        NavigationStack {
            deletionSurface
                .navigationDestination(isPresented: detailPresented) {
                    overlay
                }
        }
        .focusedSceneValue(\.boardActions, focusedBoardActions)
        .quickLookPreview($quickLookURL)
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
            .background {
                if TestHooks.isUITesting {
                    rowsProbe
                }
            }
    }

    private var reactiveSurface: some View {
        ingestibleSurface
            .onChange(of: appState.searchQuery) { _, _ in
                appState.searchDidChange()
            }
            .onChange(of: appState.readings) { _, rows in
                guard let id = presentedReading?.id else { return }
                if let refreshed = rows.first(where: { $0.id == id }) {
                    presentedReading = refreshed
                } else {
                    advanceOverlayPastCurrent()
                }
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
                deleteDialogTitle,
                isPresented: deleteDialogPresented,
                presenting: appState.pendingDelete
            ) { rows in
                Button(deleteButtonTitle(for: rows), role: .destructive) {
                    delete(rows)
                }
                Button("Cancel", role: .cancel) {}
            } message: { rows in
                deleteDialogMessage(for: rows)
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
                .searchFocused($searchFocused)
                .toolbar { boardToolbar }
        }
    }

    @ToolbarContentBuilder
    private var boardToolbar: some ToolbarContent {
        if presentedReading == nil {
            ToolbarItem(placement: .navigation) {
                cardSizeControl
            }

            ToolbarItem(placement: .principal) {
                boardFilterPicker
            }
        }
    }

    private var boardFilterPicker: some View {
        Picker("Filter", selection: scopeSelection) {
            ForEach(LibraryScope.allCases) { scope in
                Label(scope.label, systemImage: scope.icon)
                    .labelStyle(.iconOnly)
                    .help(scope.label)
                    .accessibilityLabel(scope.label)
                    .tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Filter")
        .accessibilityValue(appState.activeScope.label)
        .accessibilityIdentifier(A11y.Filter.group)
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
        .onAppear {
            TestHooks.recordStartupEvent("toolbar")
        }
    }

    @ViewBuilder
    private var board: some View {
        if appState.isLoading || appState.isRestoringLibrary {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.readings.isEmpty {
            emptyState
        } else {
            GeometryReader { proxy in
                let previewMaxPixel = cardSize.previewMaxPixel(displayScale: displayScale)
                let configurationID = [
                    appState.libraryURL?.path ?? "",
                    String(Int(previewMaxPixel)),
                    String(presentedReading == nil),
                    String(accessibilityReduceMotion),
                    String(describing: scenePhase)
                ].joined(separator: ":")
                LazyMasonryBoard(
                    appState.readings,
                    id: \.id,
                    minimumColumnWidth: cardSize.minimumColumnWidth,
                    spacing: Self.boardSpacing,
                    contentInsets: EdgeInsets(
                        top: Self.boardTopSpacing,
                        leading: Self.boardSpacing,
                        bottom: Self.boardSpacing,
                        trailing: Self.boardSpacing
                    ),
                    configurationID: configurationID,
                    position: $boardPosition,
                    navigationCoordinator: boardNavigation,
                    estimatedHeight: estimatedCardHeight,
                    content: { row in
                        CuttingsCardView(
                            row: row,
                            isSelected: appState.selectedIDs.contains(row.id),
                            playbackPositions: videoPlaybackPositions,
                            viewportSize: proxy.size,
                            previewMaxPixel: previewMaxPixel,
                            autoplayEnabled: presentedReading == nil,
                            reduceMotion: accessibilityReduceMotion,
                            scenePhase: scenePhase,
                            onSelect: {
                                select(
                                    row,
                                    extending: boardModifierKeys.contains(.shift)
                                )
                            },
                            onOpen: { open(row) },
                            onEditTags: { tagTargetID = row.id }
                        )
                        .environment(appState)
                        .accessibilityIdentifier(A11y.List.row(row.id))
                    }
                )
                .focusable()
                .focused($boardFocused)
                .focusEffectDisabled()
                .onKeyPress(
                    keys: [.upArrow, .downArrow, .leftArrow, .rightArrow],
                    phases: [.down, .repeat],
                    action: moveSelection
                )
                .onKeyPress(
                    keys: [
                        ShortcutCatalog.openWithReturn.key,
                        ShortcutCatalog.focusSearchWithSlash.key,
                        ShortcutCatalog.quickLook.primary.key
                    ],
                    phases: [.down],
                    action: performBoardShortcut
                )
                .onModifierKeysChanged(mask: .shift) { _, modifiers in
                    boardModifierKeys = modifiers
                }
                .simultaneousGesture(boardMagnifyGesture)
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

    private func estimatedCardHeight(_ row: ReadingRow, width: CGFloat) -> CGFloat {
        switch row.kind {
        case .image, .video:
            return row.standaloneMediaHeight(for: width) ?? width
        case .quote:
            let text = row.excerpt.flatMap { $0.isEmpty ? nil : $0 } ?? row.displayTitle
            return cardTextMetrics.quoteCardHeight(for: text, width: width)
        case .article:
            if row.previewAsset != nil {
                let previewHeight = row.articlePreviewHeight(for: width)
                    ?? width / ReadingRow.socialPreviewAspectRatio
                return previewHeight + cardTextMetrics.articleFooterHeight(
                    for: row.displayTitle,
                    width: width
                )
            }
            let titleLines = min(5, max(1, Int(ceil(Double(row.displayTitle.count) / 24))))
            let excerptLines = min(6, max(0, Int(ceil(Double(row.excerpt?.count ?? 0) / 34))))
            return 32 + CGFloat(titleLines * 29 + excerptLines * 20) + 32
        }
    }

    func open(_ row: ReadingRow) {
        appState.selectReading(id: row.id, extending: false)

        if LibraryScope.links.contains(row) {
            if let url = row.sourceURL {
                ReadingLink.open(url)
            }
            return
        }

        if presentedReading == nil {
            presentationOrder = appState.readings
                .filter { !LibraryScope.links.contains($0) }
                .map(\.id)
        }
        boardFocused = false
        presentedReading = row
    }

    func closeOverlay() {
        presentedReading = nil
        presentationOrder = []
        appState.showHighlights = false
        if let id = appState.selectedId {
            boardPosition.scrollTo(id: id, anchor: .nearest)
        }
        boardFocused = true
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

    private func advanceOverlayPastCurrent() {
        if canMoveOverlay(1) {
            moveOverlay(1)
        } else if canMoveOverlay(-1) {
            moveOverlay(-1)
        } else {
            closeOverlay()
        }
    }
}
