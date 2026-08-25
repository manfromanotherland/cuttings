// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore
import SwiftUI

extension MasonryBoard {
    @MainActor
    // swiftlint:disable:next type_body_length
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate,
        NSCollectionViewPrefetching
    {
        private weak var collectionView: NSCollectionView?
        private weak var layout: MasonryCollectionViewLayout?
        private var elements: [Element] = []
        private var ids: [ID] = []
        private var content: ((Element) -> AnyView)?
        private var cardHeight: ((Element, CGFloat) -> CGFloat)?
        private var configurationID: AnyHashable?
        private var geometryID: AnyHashable?
        private var hasMore = false
        private var isLoadingMore = false
        private var lastRequestedCount: Int?
        private var onLoadMore: (() -> Void)?
        private var onPrefetch: (([Element]) -> Void)?
        private var onCancelPrefetch: (([Element]) -> Void)?
        private var layoutAnimationGeneration = 0
        private var isAnimatingLayoutChange = false
        private var hasDeferredConfigurationReload = false

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
            guard let collectionView, let currentLayout = layout else { return }

            let oldElements = elements
            let oldIDs = ids
            let newIDs = board.elements.map { $0[keyPath: board.id] }
            let configurationChanged = configurationID != board.configurationID
            let heightGeometryChanged = geometryID != board.geometryID
            let wasLoadingMore = isLoadingMore
            let appended = oldIDs.count < newIDs.count
                && Array(newIDs.prefix(oldIDs.count)) == oldIDs
            let sameIDs = oldIDs == newIDs

            let activeLayout = applyConfiguration(
                from: board,
                collectionView: collectionView,
                layout: currentLayout,
                scrollView: scrollView,
                heightGeometryChanged: heightGeometryChanged
            )
            install(board.elements, ids: newIDs)
            reconcileItems(
                oldElements: oldElements,
                oldIDs: oldIDs,
                appended: appended,
                sameIDs: sameIDs,
                configurationChanged: configurationChanged,
                collectionView: collectionView,
                layout: activeLayout
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
            scrollView: NSScrollView,
            heightGeometryChanged: Bool
        ) -> MasonryCollectionViewLayout {
            applyContentConfiguration(from: board)
            let geometryChanged = heightGeometryChanged
                || layoutGeometryDiffers(layout, from: board)
            let viewportAnchor = geometryChanged ? captureViewportAnchor(using: layout) : nil
            let activeLayout: MasonryCollectionViewLayout
            if geometryChanged, !elements.isEmpty {
                let replacement = MasonryCollectionViewLayout()
                replacement.heightProvider = { [weak self] index, width in
                    self?.height(at: index, width: width) ?? 180
                }
                configure(
                    replacement,
                    minimumColumnWidth: board.minimumColumnWidth,
                    spacing: board.spacing,
                    contentInsets: board.contentInsets
                )
                let containerWidth = scrollView.contentSize.width > 0
                    ? scrollView.contentSize.width : board.width
                replacement.prepareSnapshot(
                    itemCount: elements.count,
                    containerWidth: containerWidth
                )
                self.layout = replacement
                activeLayout = replacement

                if board.animatesLayoutChanges {
                    animateLayoutChange(
                        collectionView: collectionView,
                        scrollView: scrollView,
                        replacement: replacement,
                        anchor: viewportAnchor
                    )
                } else {
                    cancelPendingLayoutAnimation()
                    collectionView.collectionViewLayout = replacement
                    restoreViewportAnchor(
                        viewportAnchor,
                        using: replacement,
                        in: scrollView
                    )
                }
            } else {
                configure(
                    layout,
                    minimumColumnWidth: board.minimumColumnWidth,
                    spacing: board.spacing,
                    contentInsets: board.contentInsets
                )
                activeLayout = layout
            }

            updateCollectionWidth(collectionView, from: board, in: scrollView)
            return activeLayout
        }

        private func applyContentConfiguration(from board: MasonryBoard) {
            content = board.content
            cardHeight = board.cardHeight
            configurationID = board.configurationID
            geometryID = board.geometryID
            hasMore = board.hasMore
            isLoadingMore = board.isLoadingMore
            onLoadMore = board.onLoadMore
            onPrefetch = board.onPrefetch
            onCancelPrefetch = board.onCancelPrefetch
        }

        private func layoutGeometryDiffers(
            _ layout: MasonryCollectionViewLayout,
            from board: MasonryBoard
        ) -> Bool {
            layout.minimumColumnWidth != board.minimumColumnWidth
                || layout.spacing != board.spacing
                || !sameInsets(layout.contentInsets, board.contentInsets)
        }

        private func updateCollectionWidth(
            _ collectionView: NSCollectionView,
            from board: MasonryBoard,
            in scrollView: NSScrollView
        ) {
            if scrollView.contentSize.width > 0 {
                collectionView.frame.size.width = scrollView.contentSize.width
            } else if board.width.isFinite, board.width > 0 {
                collectionView.frame.size.width = board.width
            }
        }

        private func configure(
            _ layout: MasonryCollectionViewLayout,
            minimumColumnWidth: CGFloat,
            spacing: CGFloat,
            contentInsets: NSEdgeInsets
        ) {
            layout.minimumColumnWidth = minimumColumnWidth
            layout.spacing = spacing
            layout.contentInsets = contentInsets
        }

        private func sameInsets(_ lhs: NSEdgeInsets, _ rhs: NSEdgeInsets) -> Bool {
            lhs.top == rhs.top
                && lhs.left == rhs.left
                && lhs.bottom == rhs.bottom
                && lhs.right == rhs.right
        }

        private func animateLayoutChange(
            collectionView: NSCollectionView,
            scrollView: NSScrollView,
            replacement: MasonryCollectionViewLayout,
            anchor: ViewportAnchor?
        ) {
            layoutAnimationGeneration += 1
            let generation = layoutAnimationGeneration
            isAnimatingLayoutChange = true
            let targetOrigin = scrollOrigin(
                preserving: anchor,
                using: replacement,
                in: scrollView
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                collectionView.animator().collectionViewLayout = replacement
                if let targetOrigin {
                    scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, layoutAnimationGeneration == generation else { return }
                isAnimatingLayoutChange = false
                reloadDeferredConfigurationIfNeeded()
            }
        }

        private func cancelPendingLayoutAnimation() {
            layoutAnimationGeneration += 1
            isAnimatingLayoutChange = false
            hasDeferredConfigurationReload = false
        }

        private func reloadDeferredConfigurationIfNeeded() {
            guard hasDeferredConfigurationReload, let collectionView else { return }
            hasDeferredConfigurationReload = false
            let visible = Set(collectionView.visibleItems().compactMap {
                collectionView.indexPath(for: $0)
            })
            guard !visible.isEmpty else { return }
            collectionView.reloadItems(at: visible)
        }

        private func captureViewportAnchor(
            using layout: MasonryCollectionViewLayout
        ) -> ViewportAnchor? {
            guard let collectionView else { return nil }
            let visibleRect = collectionView.visibleRect
            return layout.layoutAttributesForElements(in: visibleRect)
                .compactMap { attributes -> ViewportAnchor? in
                    guard let index = attributes.indexPath?.item,
                          ids.indices.contains(index)
                    else { return nil }
                    return ViewportAnchor(
                        id: ids[index],
                        offsetFromViewportTop: attributes.frame.minY - visibleRect.minY
                    )
                }
                .min {
                    abs($0.offsetFromViewportTop) < abs($1.offsetFromViewportTop)
                }
        }

        private func restoreViewportAnchor(
            _ anchor: ViewportAnchor?,
            using layout: MasonryCollectionViewLayout,
            in scrollView: NSScrollView
        ) {
            guard let origin = scrollOrigin(
                preserving: anchor,
                using: layout,
                in: scrollView
            ) else { return }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scrollOrigin(
            preserving anchor: ViewportAnchor?,
            using layout: MasonryCollectionViewLayout,
            in scrollView: NSScrollView
        ) -> NSPoint? {
            guard let anchor,
                  let index = ids.firstIndex(of: anchor.id),
                  let frame = layout.layoutAttributesForItem(
                      at: IndexPath(item: index, section: 0)
                  )?.frame
            else { return nil }
            let clipView = scrollView.contentView
            let maximumY = max(
                0,
                layout.collectionViewContentSize.height - clipView.bounds.height
            )
            return NSPoint(
                x: clipView.bounds.minX,
                y: min(maximumY, max(0, frame.minY - anchor.offsetFromViewportTop))
            )
        }

        private struct ViewportAnchor {
            let id: ID
            let offsetFromViewportTop: CGFloat
        }

        private func install(_ newElements: [Element], ids newIDs: [ID]) {
            elements = newElements
            ids = newIDs
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
            let contentChanged = Set(oldElements.indices.compactMap { index in
                oldElements[index] == elements[index]
                    ? nil : IndexPath(item: index, section: 0)
            })
            var changed = contentChanged
            if configurationChanged {
                if isAnimatingLayoutChange {
                    hasDeferredConfigurationReload = true
                } else {
                    changed.formUnion(collectionView.visibleItems().compactMap {
                        collectionView.indexPath(for: $0)
                    })
                }
            }
            guard !changed.isEmpty else { return }

            collectionView.reloadItems(at: changed)
            layout.invalidateHeights(at: Set(contentChanged.map(\.item)))
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
            let height = layout.layoutAttributesForItem(at: indexPath)?.size.height
                ?? height(at: indexPath.item, width: layout.itemWidth)
            item.configure(
                identity: AnyHashable(id),
                width: layout.itemWidth,
                height: height,
                content: AnyView(content(element).id(id))
            )
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

        func collectionView(
            _: NSCollectionView,
            prefetchItemsAt indexPaths: [IndexPath]
        ) {
            onPrefetch?(indexPaths.compactMap { indexPath in
                elements.indices.contains(indexPath.item) ? elements[indexPath.item] : nil
            })
        }

        func collectionView(
            _: NSCollectionView,
            cancelPrefetchingForItemsAt indexPaths: [IndexPath]
        ) {
            onCancelPrefetch?(indexPaths.compactMap { indexPath in
                elements.indices.contains(indexPath.item) ? elements[indexPath.item] : nil
            })
        }

        private func height(at index: Int, width: CGFloat) -> CGFloat {
            guard elements.indices.contains(index) else { return 180 }
            let height = cardHeight?(elements[index], width) ?? 180
            return height.isFinite && height > 0 ? height : 180
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
    }
}
