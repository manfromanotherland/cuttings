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
    let elements: [Element]
    let id: KeyPath<Element, ID>
    let width: CGFloat
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat
    let contentInsets: NSEdgeInsets
    let configurationID: AnyHashable
    let geometryID: AnyHashable
    let animatesLayoutChanges: Bool
    let hasMore: Bool
    let isLoadingMore: Bool
    let cardHeight: (Element, CGFloat) -> CGFloat
    let onLoadMore: () -> Void
    let onPrefetch: ([Element]) -> Void
    let onCancelPrefetch: ([Element]) -> Void
    let content: (Element) -> AnyView

    init<Data>(
        _ data: Data,
        id: KeyPath<Element, ID>,
        width: CGFloat,
        minimumColumnWidth: CGFloat = 220,
        spacing: CGFloat = 18,
        contentInsets: NSEdgeInsets = .init(),
        configurationID: AnyHashable = 0,
        geometryID: AnyHashable = 0,
        animatesLayoutChanges: Bool = true,
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        cardHeight: @escaping (Element, CGFloat) -> CGFloat = { _, _ in 180 },
        onLoadMore: @escaping () -> Void = {},
        onPrefetch: @escaping ([Element]) -> Void = { _ in },
        onCancelPrefetch: @escaping ([Element]) -> Void = { _ in },
        @ViewBuilder content: @escaping (Element) -> some View
    ) where Data: RandomAccessCollection, Data.Element == Element {
        elements = Array(data)
        self.id = id
        self.width = width
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.configurationID = configurationID
        self.geometryID = geometryID
        self.animatesLayoutChanges = animatesLayoutChanges
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.cardHeight = cardHeight
        self.onLoadMore = onLoadMore
        self.onPrefetch = onPrefetch
        self.onCancelPrefetch = onCancelPrefetch
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
        collectionView.prefetchDataSource = context.coordinator
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
