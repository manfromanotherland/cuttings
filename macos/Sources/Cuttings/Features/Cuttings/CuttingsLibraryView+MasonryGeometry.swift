// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct BoardDatasetID: Hashable {
    let libraryPath: String
    let items: [MasonryCardGeometryIdentity]
}

struct BoardGeometryRequestID: Hashable {
    let dataset: BoardDatasetID
    let columnWidthBuckets: [Int]

    var columnWidths: [CGFloat] {
        columnWidthBuckets.map(MasonryColumnWidthBucket.width(for:))
    }
}

extension CuttingsLibraryView {
    var boardDatasetID: BoardDatasetID {
        BoardDatasetID(
            libraryPath: appState.libraryURL?.path ?? "",
            items: appState.readings.map(MasonryCardGeometryIdentity.init(row:))
        )
    }

    func boardGeometryRequestID(for containerWidth: CGFloat) -> BoardGeometryRequestID {
        BoardGeometryRequestID(
            dataset: boardDatasetID,
            columnWidthBuckets: boardColumnWidths(containerWidth: containerWidth)
                .map(MasonryColumnWidthBucket.bucket(for:))
        )
    }

    func boardGeometryIsCurrent(for request: BoardGeometryRequestID) -> Bool {
        preparedLibraryPath == request.dataset.libraryPath
            && preparedColumnWidthBuckets == request.columnWidthBuckets
            && preparedBoardItems == request.dataset.items
    }

    func boardReadings(for request: BoardGeometryRequestID) -> [ReadingRow] {
        let rows = appState.readings
        guard preparedLibraryPath == request.dataset.libraryPath,
              preparedBoardItems.count <= rows.count,
              zip(preparedBoardItems, rows).allSatisfy({
                  $0.0 == MasonryCardGeometryIdentity(row: $0.1)
              })
        else { return [] }
        return Array(rows.prefix(preparedBoardItems.count))
    }

    @MainActor
    func prepareBoardGeometry(for request: BoardGeometryRequestID) async {
        let key = request.dataset
        let rows = appState.readings
        guard !rows.isEmpty else {
            clearPreparedBoardGeometry(for: request)
            return
        }

        let resizesPreparedDataset = preparedLibraryPath == key.libraryPath
            && preparedBoardItems == key.items
            && preparedColumnWidthBuckets != request.columnWidthBuckets
        if resizesPreparedDataset {
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }

        let appendsPreparedRows = preparedLibraryPath == key.libraryPath
            && preparedColumnWidthBuckets == request.columnWidthBuckets
            && key.items.starts(with: preparedBoardItems)
        let start = appendsPreparedRows ? preparedBoardItems.count : 0

        let rowsToPrepare = Array(rows.dropFirst(start))
        guard !rowsToPrepare.isEmpty else {
            finishPreparingBoardGeometry(
                for: request,
                heights: [:],
                ratios: boardAspectRatios,
                replacesHeights: false
            )
            return
        }

        let preparationID = UUID()
        activeBoardGeometryPreparation = preparationID
        isPreparingBoardGeometry = true
        defer {
            if activeBoardGeometryPreparation == preparationID {
                activeBoardGeometryPreparation = nil
                isPreparingBoardGeometry = false
            }
        }

        let reusesPreparedRatios = preparedLibraryPath == key.libraryPath
            && key.items.starts(with: preparedBoardItems)
        let baseRatios = reusesPreparedRatios ? boardAspectRatios : [:]
        let loadedRatios = await MasonryCardAspectRatioLoader.shared.aspectRatios(
            for: rowsToPrepare,
            libraryURL: appState.libraryURL
        )
        guard !Task.isCancelled else { return }
        let ratios = baseRatios.merging(loadedRatios) { _, new in new }
        let heights = await MasonryCardHeightLoader.shared.heights(
            for: rowsToPrepare,
            aspectRatios: ratios,
            widths: request.columnWidths
        )
        guard !Task.isCancelled, boardDatasetID == key else { return }
        finishPreparingBoardGeometry(
            for: request,
            heights: heights,
            ratios: ratios,
            replacesHeights: !appendsPreparedRows
        )
    }

    func stableCardHeight(_ row: ReadingRow, width: CGFloat) -> CGFloat {
        for delta in [0, -1, 1] {
            let key = MasonryCardHeightKey(
                readingID: row.id,
                width: width + CGFloat(delta)
            )
            if let height = boardCardHeights[key] {
                return height
            }
        }

        if let closestWidth = preparedCardWidths.min(by: {
            abs($0 - width) < abs($1 - width)
        }), let height = boardCardHeights[
            MasonryCardHeightKey(readingID: row.id, width: closestWidth)
        ] {
            return height
        }

        assertionFailure("Masonry card height was requested before geometry preparation")
        return 180
    }

    private func clearPreparedBoardGeometry(for request: BoardGeometryRequestID) {
        preparedBoardItems = []
        boardAspectRatios = [:]
        boardCardHeights = [:]
        preparedCardWidths = []
        preparedLibraryPath = request.dataset.libraryPath
        preparedColumnWidthBuckets = request.columnWidthBuckets
        activeBoardGeometryPreparation = nil
        isPreparingBoardGeometry = false
    }

    private func finishPreparingBoardGeometry(
        for request: BoardGeometryRequestID,
        heights: [MasonryCardHeightKey: CGFloat],
        ratios: [String: CGFloat],
        replacesHeights: Bool
    ) {
        boardAspectRatios = ratios
        if replacesHeights {
            boardCardHeights = heights
            boardGeometryGeneration &+= 1
        } else {
            boardCardHeights.merge(heights) { _, new in new }
        }
        preparedCardWidths = request.columnWidths
        preparedBoardItems = request.dataset.items
        preparedLibraryPath = request.dataset.libraryPath
        preparedColumnWidthBuckets = request.columnWidthBuckets
    }

    private func boardColumnWidths(containerWidth: CGFloat) -> [CGFloat] {
        let availableWidth = max(1, containerWidth - Self.boardSpacing * 2)
        return CardSize.allCases.map { size in
            let columns = MasonryGeometry.columnCount(
                width: availableWidth,
                minimumColumnWidth: size.minimumColumnWidth,
                spacing: Self.boardSpacing,
                maximum: .max
            )
            return MasonryGeometry.columnWidth(
                width: availableWidth,
                columns: columns,
                spacing: Self.boardSpacing
            )
        }
    }
}
