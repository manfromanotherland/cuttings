// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Numeric masonry layout for the virtualized board. Every card arrives with
/// final geometry, and column membership stays stable until the data or card
/// density explicitly changes. Per-column indices keep viewport queries
/// independent of the total library size.
@MainActor
final class MasonryCollectionViewLayout: NSCollectionViewLayout {
    var minimumColumnWidth: CGFloat = 220 {
        didSet {
            if oldValue != minimumColumnWidth {
                resetAssignments()
            }
        }
    }

    var spacing: CGFloat = 18 {
        didSet {
            if oldValue != spacing {
                resetAssignments()
            }
        }
    }

    var contentInsets = NSEdgeInsets() {
        didSet {
            if oldValue.top != contentInsets.top
                || oldValue.left != contentInsets.left
                || oldValue.bottom != contentInsets.bottom
                || oldValue.right != contentInsets.right
            {
                resetAssignments()
            }
        }
    }

    var heightProvider: ((Int, CGFloat) -> CGFloat)?
    private(set) var itemWidth: CGFloat = 220
    private(set) var lastPreparedItemCount = 0
    private(set) var lastQueryInspectionCount = 0

    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var columnAssignments: [Int] = []
    private var itemIndicesByColumn: [[Int]] = []
    private var dirtyStartByColumn: [Int: Int] = [:]
    private var contentSize = CGSize.zero
    private var preparedWidth: CGFloat?
    private var preparedColumnCount = 0
    private var needsUpdate = true
    private var requiresFullRebuild = true

    func setNeedsUpdate() {
        needsUpdate = true
        invalidateLayout()
    }

    func invalidateHeights(at indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        for index in indices {
            guard columnAssignments.indices.contains(index) else {
                requiresFullRebuild = true
                continue
            }
            let column = columnAssignments[index]
            dirtyStartByColumn[column] = min(
                dirtyStartByColumn[column] ?? index,
                index
            )
        }
        setNeedsUpdate()
    }

    func resetAssignments() {
        attributes.removeAll(keepingCapacity: true)
        columnAssignments.removeAll(keepingCapacity: true)
        itemIndicesByColumn.removeAll(keepingCapacity: true)
        dirtyStartByColumn.removeAll(keepingCapacity: true)
        preparedWidth = nil
        preparedColumnCount = 0
        requiresFullRebuild = true
        setNeedsUpdate()
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        let width = collectionView.enclosingScrollView?.contentSize.width
            ?? collectionView.bounds.width
        prepareItems(
            count: collectionView.numberOfItems(inSection: 0),
            width: width
        )
    }

    func prepareSnapshot(itemCount: Int, containerWidth: CGFloat) {
        prepareItems(count: itemCount, width: containerWidth)
    }

    private func prepareItems(count: Int, width: CGFloat) {
        let availableWidth = max(
            1,
            width - contentInsets.left - contentInsets.right
        )
        let columnCount = MasonryGeometry.columnCount(
            width: availableWidth,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing,
            maximum: Int.max
        )
        let widthChanged = preparedWidth.map { abs($0 - width) >= 0.5 } ?? true
        let columnsChanged = preparedColumnCount != columnCount
        let countChanged = attributes.count != count
        guard needsUpdate || widthChanged || columnsChanged || countChanged else { return }

        itemWidth = MasonryGeometry.columnWidth(
            width: availableWidth,
            columns: columnCount,
            spacing: spacing
        )
        lastPreparedItemCount = 0

        let shouldRebuildAll = requiresFullRebuild
            || widthChanged
            || columnsChanged
            || attributes.count > count
            || columnAssignments.count != attributes.count
        if shouldRebuildAll {
            rebuildAll(count: count, columnCount: columnCount)
        } else {
            updateDirtyColumns()
            appendItems(from: attributes.count, to: count, columnCount: columnCount)
        }

        updateContentSize(width: width)
        preparedWidth = width
        preparedColumnCount = columnCount
        dirtyStartByColumn.removeAll(keepingCapacity: true)
        requiresFullRebuild = false
        needsUpdate = false
    }

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        lastQueryInspectionCount = 0
        var matches: [NSCollectionViewLayoutAttributes] = []

        for itemIndices in itemIndicesByColumn where !itemIndices.isEmpty {
            var lower = 0
            var upper = itemIndices.count
            while lower < upper {
                lastQueryInspectionCount += 1
                let middle = lower + (upper - lower) / 2
                let frame = attributes[itemIndices[middle]].frame
                if frame.maxY < rect.minY {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }

            var position = lower
            while position < itemIndices.count {
                lastQueryInspectionCount += 1
                let itemAttributes = attributes[itemIndices[position]]
                guard itemAttributes.frame.minY <= rect.maxY else { break }
                if itemAttributes.frame.intersects(rect) {
                    matches.append(itemAttributes)
                }
                position += 1
            }
        }

        return matches.sorted {
            ($0.indexPath?.item ?? .max) < ($1.indexPath?.item ?? .max)
        }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        guard attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) >= 0.5
    }

    private func rebuildAll(count: Int, columnCount: Int) {
        attributes.removeAll(keepingCapacity: true)
        attributes.reserveCapacity(count)
        columnAssignments.removeAll(keepingCapacity: true)
        columnAssignments.reserveCapacity(count)
        itemIndicesByColumn = Array(repeating: [], count: columnCount)
        var columnHeights = Array(repeating: contentInsets.top, count: columnCount)

        for index in 0 ..< count {
            let column = MasonryGeometry.shortestColumn(in: columnHeights)
            appendAttributes(
                for: index,
                column: column,
                originY: columnHeights[column]
            )
            columnHeights[column] = attributes[index].frame.maxY + spacing
        }
    }

    private func appendItems(from start: Int, to end: Int, columnCount: Int) {
        guard start < end else { return }
        if itemIndicesByColumn.count != columnCount {
            requiresFullRebuild = true
            rebuildAll(count: end, columnCount: columnCount)
            return
        }

        var columnHeights = currentColumnHeights()
        for index in start ..< end {
            let column = MasonryGeometry.shortestColumn(in: columnHeights)
            appendAttributes(
                for: index,
                column: column,
                originY: columnHeights[column]
            )
            columnHeights[column] = attributes[index].frame.maxY + spacing
        }
    }

    private func appendAttributes(for index: Int, column: Int, originY: CGFloat) {
        let itemAttributes = NSCollectionViewLayoutAttributes(
            forItemWith: IndexPath(item: index, section: 0)
        )
        itemAttributes.frame = CGRect(
            x: contentInsets.left + CGFloat(column) * (itemWidth + spacing),
            y: originY,
            width: itemWidth,
            height: height(at: index)
        )
        attributes.append(itemAttributes)
        columnAssignments.append(column)
        itemIndicesByColumn[column].append(index)
    }

    private func updateDirtyColumns() {
        for (column, dirtyItemIndex) in dirtyStartByColumn {
            guard itemIndicesByColumn.indices.contains(column) else { continue }
            let itemIndices = itemIndicesByColumn[column]
            let startPosition = lowerBound(of: dirtyItemIndex, in: itemIndices)
            guard startPosition < itemIndices.count else { continue }

            var originY = startPosition == 0
                ? contentInsets.top
                : attributes[itemIndices[startPosition - 1]].frame.maxY + spacing
            for position in startPosition ..< itemIndices.count {
                let index = itemIndices[position]
                attributes[index].frame = CGRect(
                    x: contentInsets.left + CGFloat(column) * (itemWidth + spacing),
                    y: originY,
                    width: itemWidth,
                    height: height(at: index)
                )
                originY = attributes[index].frame.maxY + spacing
            }
        }
    }

    private func currentColumnHeights() -> [CGFloat] {
        itemIndicesByColumn.map { itemIndices in
            guard let last = itemIndices.last else { return contentInsets.top }
            return attributes[last].frame.maxY + spacing
        }
    }

    private func updateContentSize(width: CGFloat) {
        let maximumBottom = itemIndicesByColumn.compactMap { itemIndices in
            itemIndices.last.map { attributes[$0].frame.maxY }
        }.max() ?? contentInsets.top
        contentSize = CGSize(
            width: width,
            height: max(
                contentInsets.top + contentInsets.bottom,
                maximumBottom + contentInsets.bottom
            )
        )
    }

    private func height(at index: Int) -> CGFloat {
        lastPreparedItemCount += 1
        let requestedHeight = heightProvider?(index, itemWidth) ?? 180
        return requestedHeight.isFinite && requestedHeight > 0 ? requestedHeight : 180
    }

    private func lowerBound(of target: Int, in values: [Int]) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
