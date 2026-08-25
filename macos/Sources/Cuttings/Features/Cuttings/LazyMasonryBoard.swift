// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import SwiftUI

/// Cuttings' stable geometry contract for LazyLayoutKit. Every card receives a
/// deterministic height before its view is built, so scrolling never waits for
/// asset decoding or a SwiftUI measurement pass.
struct CuttingsMasonryLayout: LazyLayoutAlgorithm {
    typealias Item = ItemMetric

    let minimumColumnWidth: Double
    let spacing: Double
    let topInset: Double
    let leadingInset: Double
    let bottomInset: Double
    let trailingInset: Double

    func columnWidth(forContainerWidth containerWidth: Double) -> Double {
        let availableWidth = max(1, containerWidth - leadingInset - trailingInset)
        let gaps = spacing * Double(columnCount(forContainerWidth: containerWidth) - 1)
        return max(1, (availableWidth - gaps) / Double(columnCount(forContainerWidth: containerWidth)))
    }

    func layout(items: [ItemMetric], containerWidth: Double) -> LazyLayoutResult {
        let availableWidth = max(1, containerWidth - leadingInset - trailingInset)
        let masonry = LazyLayoutKit.MasonryLayout(
            columns: columnCount(forContainerWidth: containerWidth),
            spacing: spacing
        )
        let result = masonry.layout(items: items, containerWidth: availableWidth)
        let frames = result.frames.map { frame in
            LayoutRect(
                x: frame.x + leadingInset,
                y: frame.y + topInset,
                width: frame.width,
                height: frame.height
            )
        }
        return LazyLayoutResult(
            frames: frames,
            contentHeight: topInset + result.contentHeight + bottomInset
        )
    }

    func columnCount(forContainerWidth containerWidth: Double) -> Int {
        let availableWidth = max(1, containerWidth - leadingInset - trailingInset)
        let safeMinimum = minimumColumnWidth.isFinite && minimumColumnWidth > 0
            ? minimumColumnWidth : 1
        let divisor = safeMinimum + spacing
        guard divisor.isFinite, divisor > 0 else { return 1 }
        return max(1, Int((availableWidth + spacing) / divisor))
    }
}

/// A viewport-lazy masonry board backed by LazyLayoutKit. The complete reading
/// snapshot is cheap layout input; only cards in the materialized window become
/// SwiftUI views.
struct LazyMasonryBoard<Element: Equatable, ID: Hashable & Sendable>: View {
    private let elements: [Element]
    private let id: KeyPath<Element, ID>
    private let minimumColumnWidth: CGFloat
    private let spacing: CGFloat
    private let contentInsets: EdgeInsets
    private let configurationID: AnyHashable
    private let hasMore: Bool
    private let isLoadingMore: Bool
    private let loadMoreIDs: Set<ID>
    private let estimatedHeight: (Element, CGFloat) -> CGFloat
    private let onLoadMore: () -> Void
    private let content: (Element) -> AnyView

    init<Data>(
        _ data: Data,
        id: KeyPath<Element, ID>,
        minimumColumnWidth: CGFloat = 220,
        spacing: CGFloat = 18,
        contentInsets: EdgeInsets = .init(),
        configurationID: AnyHashable = 0,
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        estimatedHeight: @escaping (Element, CGFloat) -> CGFloat = { _, _ in 180 },
        onLoadMore: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Element) -> some View
    ) where Data: RandomAccessCollection, Data.Element == Element {
        let elements = Array(data)
        self.elements = elements
        self.id = id
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.configurationID = configurationID
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        loadMoreIDs = Set(elements.suffix(12).map { $0[keyPath: id] })
        self.estimatedHeight = estimatedHeight
        self.onLoadMore = onLoadMore
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        let layout = CuttingsMasonryLayout(
            minimumColumnWidth: Double(minimumColumnWidth),
            spacing: Double(spacing),
            topInset: Double(contentInsets.top),
            leadingInset: Double(contentInsets.leading),
            bottomInset: Double(contentInsets.bottom),
            trailingInset: Double(contentInsets.trailing)
        )

        LazyLayoutView(
            elements,
            id: id,
            layout: layout,
            overscan: .items(80),
            recomputeOn: configurationID
        ) { element, containerWidth in
            .fixedHeight(
                normalizedHeight(
                    estimatedHeight(
                        element,
                        CGFloat(layout.columnWidth(forContainerWidth: containerWidth))
                    )
                )
            )
        } content: { element in
            content(element)
                .onAppear {
                    guard hasMore,
                          !isLoadingMore,
                          loadMoreIDs.contains(element[keyPath: id])
                    else { return }
                    onLoadMore()
                }
        }
    }

    private func normalizedHeight(_ height: CGFloat) -> Double {
        guard height.isFinite, height > 0 else { return 180 }
        return Double(height)
    }
}
