// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Small, deterministic geometry helpers shared by the layout and its unit
/// tests. Cards are always assigned to the currently shortest column, preserving
/// source order while producing a true masonry silhouette.
enum MasonryGeometry {
    static func resolvedWidth(
        proposedWidth: CGFloat?, minimumColumnWidth: CGFloat
    ) -> CGFloat {
        let fallback = minimumColumnWidth.isFinite && minimumColumnWidth > 0
            ? minimumColumnWidth : 1
        guard let proposedWidth, proposedWidth.isFinite else { return fallback }
        return max(fallback, proposedWidth)
    }

    static func columnCount(
        width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat, maximum: Int
    ) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let divisor = minimumColumnWidth + spacing
        guard divisor.isFinite, divisor > 0 else { return 1 }
        let rawCount = (width + spacing) / divisor
        guard rawCount.isFinite else { return 1 }
        let count = Int(rawCount)
        return min(max(1, maximum), max(1, count))
    }

    static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(0, columns - 1)) * spacing
        return max(0, (width - gaps) / CGFloat(max(1, columns)))
    }

    static func shortestColumn(in heights: [CGFloat]) -> Int {
        heights.enumerated().min { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset < rhs.offset : lhs.element < rhs.element
        }?.offset ?? 0
    }
}

/// A virtualized bridge around AppKit's reusable collection-view items. SwiftUI
/// custom `Layout` containers must measure every child; `NSCollectionView`
/// instead asks for views only around the viewport and recycles them while the
/// lightweight masonry frame model can still span thousands of cards.
struct MasonryBoard<Element: Equatable, ID: Hashable>: NSViewRepresentable {
    private let elements: [Element]
    private let id: KeyPath<Element, ID>
    private let width: CGFloat
    private let minimumColumnWidth: CGFloat
    private let spacing: CGFloat
    private let contentInsets: NSEdgeInsets
    private let configurationID: AnyHashable
    private let hasMore: Bool
    private let isLoadingMore: Bool
    private let estimatedHeight: (Element, CGFloat) -> CGFloat
    private let onLoadMore: () -> Void
    private let content: (Element) -> AnyView

    init<Data>(
        _ data: Data,
        id: KeyPath<Element, ID>,
        width: CGFloat,
        minimumColumnWidth: CGFloat = 220,
        spacing: CGFloat = 18,
        contentInsets: NSEdgeInsets = .init(),
        configurationID: AnyHashable = 0,
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        estimatedHeight: @escaping (Element, CGFloat) -> CGFloat = { _, _ in 180 },
        onLoadMore: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Element) -> some View
    ) where Data: RandomAccessCollection, Data.Element == Element {
        elements = Array(data)
        self.id = id
        self.width = width
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.configurationID = configurationID
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.estimatedHeight = estimatedHeight
        self.onLoadMore = onLoadMore
        self.content = { AnyView(content($0)) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = MasonryCollectionViewLayout()
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            MasonryHostingItem.self,
            forItemWithIdentifier: MasonryHostingItem.reuseIdentifier
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = collectionView
        collectionView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        collectionView.autoresizingMask = [.width]

        context.coordinator.attach(
            collectionView: collectionView,
            layout: layout,
            scrollView: scrollView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(from: self, scrollView: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach(from: scrollView)
    }
}

extension MasonryBoard {
    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        private weak var collectionView: NSCollectionView?
        private weak var layout: MasonryCollectionViewLayout?
        private var elements: [Element] = []
        private var ids: [ID] = []
        private var indexByID: [ID: Int] = [:]
        private var measuredHeights: [ID: Measurement] = [:]
        private var pendingMeasurements: [ID: Measurement] = [:]
        private var isApplyingMeasurements = false
        private var content: ((Element) -> AnyView)?
        private var estimatedHeight: ((Element, CGFloat) -> CGFloat)?
        private var configurationID: AnyHashable?
        private var hasMore = false
        private var isLoadingMore = false
        private var lastRequestedCount: Int?
        private var onLoadMore: (() -> Void)?

        func attach(
            collectionView: NSCollectionView,
            layout: MasonryCollectionViewLayout,
            scrollView: NSScrollView
        ) {
            self.collectionView = collectionView
            self.layout = layout
            layout.heightProvider = { [weak self] index, width in
                self?.height(at: index, width: width) ?? 180
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func detach(from scrollView: NSScrollView) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            collectionView?.visibleItems().forEach {
                ($0 as? MasonryHostingItem)?.endDisplaying()
            }
        }

        func update(from board: MasonryBoard, scrollView: NSScrollView) {
            guard let collectionView, let layout else { return }

            let oldElements = elements
            let oldIDs = ids
            let newIDs = board.elements.map { $0[keyPath: board.id] }
            let configurationChanged = configurationID != board.configurationID
            let wasLoadingMore = isLoadingMore
            let appended = oldIDs.count < newIDs.count
                && Array(newIDs.prefix(oldIDs.count)) == oldIDs
            let sameIDs = oldIDs == newIDs

            applyConfiguration(
                from: board,
                collectionView: collectionView,
                layout: layout,
                scrollView: scrollView
            )
            install(board.elements, ids: newIDs)
            reconcileItems(
                oldElements: oldElements,
                oldIDs: oldIDs,
                appended: appended,
                sameIDs: sameIDs,
                configurationChanged: configurationChanged,
                collectionView: collectionView,
                layout: layout
            )

            if !sameIDs || newIDs.count != oldIDs.count
                || (wasLoadingMore && !board.isLoadingMore && board.hasMore)
            {
                lastRequestedCount = nil
            }
            updateVisibility()
        }

        private func applyConfiguration(
            from board: MasonryBoard,
            collectionView: NSCollectionView,
            layout: MasonryCollectionViewLayout,
            scrollView: NSScrollView
        ) {
            content = board.content
            estimatedHeight = board.estimatedHeight
            configurationID = board.configurationID
            hasMore = board.hasMore
            isLoadingMore = board.isLoadingMore
            onLoadMore = board.onLoadMore

            layout.minimumColumnWidth = board.minimumColumnWidth
            layout.spacing = board.spacing
            layout.contentInsets = board.contentInsets
            if scrollView.contentSize.width > 0 {
                collectionView.frame.size.width = scrollView.contentSize.width
            } else if board.width.isFinite, board.width > 0 {
                collectionView.frame.size.width = board.width
            }
        }

        private func install(_ newElements: [Element], ids newIDs: [ID]) {
            elements = newElements
            ids = newIDs
            indexByID = Dictionary(
                uniqueKeysWithValues: newIDs.enumerated().map { ($0.element, $0.offset) }
            )
            let newIDSet = Set(newIDs)
            measuredHeights = measuredHeights.filter { newIDSet.contains($0.key) }
        }

        private func reconcileItems(
            oldElements: [Element],
            oldIDs: [ID],
            appended: Bool,
            sameIDs: Bool,
            configurationChanged: Bool,
            collectionView: NSCollectionView,
            layout: MasonryCollectionViewLayout
        ) {
            if oldIDs.isEmpty {
                layout.resetAssignments()
                collectionView.reloadData()
            } else if appended {
                let inserted = Set((oldIDs.count ..< ids.count).map {
                    IndexPath(item: $0, section: 0)
                })
                layout.setNeedsUpdate()
                collectionView.insertItems(at: inserted)
            } else if !sameIDs {
                layout.resetAssignments()
                collectionView.reloadData()
            } else {
                reloadChangedItems(
                    oldElements: oldElements,
                    configurationChanged: configurationChanged,
                    collectionView: collectionView,
                    layout: layout
                )
            }
        }

        private func reloadChangedItems(
            oldElements: [Element],
            configurationChanged: Bool,
            collectionView: NSCollectionView,
            layout: MasonryCollectionViewLayout
        ) {
            var changed = Set(oldElements.indices.compactMap { index in
                oldElements[index] == elements[index]
                    ? nil : IndexPath(item: index, section: 0)
            })
            if configurationChanged {
                changed.formUnion(collectionView.visibleItems().compactMap {
                    collectionView.indexPath(for: $0)
                })
            }
            guard !changed.isEmpty else { return }

            let changedIndices = Set(changed.map(\.item))
            for index in changedIndices where ids.indices.contains(index) {
                measuredHeights.removeValue(forKey: ids[index])
                pendingMeasurements.removeValue(forKey: ids[index])
            }
            collectionView.reloadItems(at: changed)
            layout.invalidateHeights(at: changedIndices)
        }

        func numberOfSections(in _: NSCollectionView) -> Int {
            1
        }

        func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
            elements.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            guard elements.indices.contains(indexPath.item),
                  let content,
                  let layout,
                  let item = collectionView.makeItem(
                      withIdentifier: MasonryHostingItem.reuseIdentifier,
                      for: indexPath
                  ) as? MasonryHostingItem
            else { return NSCollectionViewItem() }

            let element = elements[indexPath.item]
            let id = ids[indexPath.item]
            item.configure(
                identity: AnyHashable(id),
                width: layout.itemWidth,
                content: AnyView(content(element).id(id))
            ) { [weak self] measuredWidth, measuredHeight in
                self?.record(
                    height: measuredHeight,
                    width: measuredWidth,
                    for: id
                )
            }
            return item
        }

        func collectionView(
            _: NSCollectionView,
            willDisplay item: NSCollectionViewItem,
            forRepresentedObjectAt indexPath: IndexPath
        ) {
            (item as? MasonryHostingItem)?.setVisible(
                isActuallyVisible(at: indexPath)
            )
            guard hasMore,
                  !isLoadingMore,
                  indexPath.item >= max(0, elements.count - 12),
                  lastRequestedCount != elements.count
            else { return }
            lastRequestedCount = elements.count
            onLoadMore?()
        }

        func collectionView(
            _: NSCollectionView,
            didEndDisplaying item: NSCollectionViewItem,
            forRepresentedObjectAt _: IndexPath
        ) {
            (item as? MasonryHostingItem)?.endDisplaying()
        }

        private func height(at index: Int, width: CGFloat) -> CGFloat {
            guard elements.indices.contains(index) else { return 180 }
            let id = ids[index]
            if let measurement = measuredHeights[id],
               abs(measurement.width - width) < 0.5
            {
                return measurement.height
            }
            let estimate = estimatedHeight?(elements[index], width) ?? 180
            return estimate.isFinite && estimate > 0 ? estimate : 180
        }

        private func record(height: CGFloat, width: CGFloat, for id: ID) {
            guard height.isFinite, height > 0, width.isFinite, width > 0 else { return }
            let measurement = Measurement(width: width, height: ceil(height))
            if let current = measuredHeights[id],
               abs(current.width - measurement.width) < 0.5,
               abs(current.height - measurement.height) < 0.5
            {
                return
            }
            pendingMeasurements[id] = measurement
            guard !isApplyingMeasurements else { return }
            isApplyingMeasurements = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let scrollAnchor = captureScrollAnchor()
                let applicable = pendingMeasurements.filter { indexByID[$0.key] != nil }
                let changedIndices = Set(applicable.keys.compactMap { indexByID[$0] })
                measuredHeights.merge(applicable) { _, new in new }
                pendingMeasurements.removeAll(keepingCapacity: true)
                isApplyingMeasurements = false
                layout?.invalidateHeights(at: changedIndices)
                layout?.prepare()
                restoreScrollAnchor(scrollAnchor)
                updateVisibility()
            }
        }

        @objc private func clipViewBoundsDidChange(_: Notification) {
            updateVisibility()
        }

        private func updateVisibility() {
            guard let collectionView else { return }
            for item in collectionView.visibleItems() {
                guard let indexPath = collectionView.indexPath(for: item) else { continue }
                (item as? MasonryHostingItem)?.setVisible(
                    isActuallyVisible(at: indexPath)
                )
            }
        }

        private func isActuallyVisible(at indexPath: IndexPath) -> Bool {
            guard let collectionView,
                  let frame = layout?.layoutAttributesForItem(at: indexPath)?.frame
            else { return false }
            return frame.intersects(collectionView.visibleRect)
        }

        private func captureScrollAnchor() -> ScrollAnchor? {
            guard let collectionView else { return nil }
            let visibleRect = collectionView.visibleRect
            let candidates = collectionView.visibleItems().compactMap { item -> ScrollAnchor? in
                guard let indexPath = collectionView.indexPath(for: item),
                      ids.indices.contains(indexPath.item),
                      let frame = layout?.layoutAttributesForItem(at: indexPath)?.frame,
                      frame.intersects(visibleRect)
                else { return nil }
                return ScrollAnchor(
                    id: ids[indexPath.item],
                    offsetFromViewportTop: frame.minY - visibleRect.minY
                )
            }
            return candidates.min {
                abs($0.offsetFromViewportTop) < abs($1.offsetFromViewportTop)
            }
        }

        private func restoreScrollAnchor(_ anchor: ScrollAnchor?) {
            guard let anchor,
                  let collectionView,
                  let scrollView = collectionView.enclosingScrollView,
                  let index = indexByID[anchor.id],
                  let frame = layout?.layoutAttributesForItem(
                      at: IndexPath(item: index, section: 0)
                  )?.frame
            else { return }

            let clipView = scrollView.contentView
            let maximumY = max(
                0,
                (layout?.collectionViewContentSize.height ?? 0) - clipView.bounds.height
            )
            let targetY = min(
                maximumY,
                max(0, frame.minY - anchor.offsetFromViewportTop)
            )
            guard abs(clipView.bounds.minY - targetY) >= 0.5 else { return }
            clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        private struct Measurement {
            let width: CGFloat
            let height: CGFloat
        }

        private struct ScrollAnchor {
            let id: ID
            let offsetFromViewportTop: CGFloat
        }
    }
}
