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

    static func normalizedHeight(_ height: CGFloat) -> Double {
        guard height.isFinite, height > 0 else { return 180 }
        return Double(height)
    }
}

enum BoardNavigationDirection: Sendable {
    case upward
    case downward
    case leftward
    case rightward
}

/// Stable spatial navigation over the exact frames used by the masonry board.
/// Source order breaks ties so equal geometry never makes keyboard movement
/// nondeterministic.
struct MasonryNavigationIndex<ID: Hashable & Sendable>: Sendable {
    private struct Entry: Sendable {
        let id: ID
        let frame: LayoutRect
        let sourceIndex: Int
    }

    private let entries: [Entry]

    init(ids: [ID], frames: [LayoutRect]) {
        entries = zip(ids, frames).enumerated().compactMap { index, pair in
            let (id, frame) = pair
            guard Self.isValid(frame) else { return nil }
            return Entry(id: id, frame: frame, sourceIndex: index)
        }
    }

    func neighbor(of id: ID, toward direction: BoardNavigationDirection) -> ID? {
        guard let current = entries.first(where: { $0.id == id }) else { return nil }

        var best: (entry: Entry, score: [Double])?
        for candidate in entries where candidate.sourceIndex != current.sourceIndex {
            guard Self.isCandidate(candidate.frame, toward: direction, from: current.frame) else {
                continue
            }
            let score = Self.score(candidate, from: current, toward: direction)
            if best == nil || Self.precedes(score, best?.score ?? []) {
                best = (candidate, score)
            }
        }
        return best?.entry.id
    }

    private static func isValid(_ frame: LayoutRect) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private static func isCandidate(
        _ candidate: LayoutRect,
        toward direction: BoardNavigationDirection,
        from current: LayoutRect
    ) -> Bool {
        switch direction {
        case .upward:
            candidate.maxY <= current.minY
        case .downward:
            candidate.minY >= current.maxY
        case .leftward:
            candidate.maxX <= current.minX
        case .rightward:
            candidate.minX >= current.maxX
        }
    }

    private static func score(
        _ candidate: Entry,
        from current: Entry,
        toward direction: BoardNavigationDirection
    ) -> [Double] {
        let candidateFrame = candidate.frame
        let currentFrame = current.frame
        let horizontalGap = intervalGap(
            candidateFrame.minX, candidateFrame.maxX,
            currentFrame.minX, currentFrame.maxX
        )
        let verticalGap = intervalGap(
            candidateFrame.minY, candidateFrame.maxY,
            currentFrame.minY, currentFrame.maxY
        )
        let horizontalCenterDistance = abs(midX(candidateFrame) - midX(currentFrame))
        let verticalCenterDistance = abs(midY(candidateFrame) - midY(currentFrame))

        switch direction {
        case .upward, .downward:
            return [
                horizontalGap,
                verticalGap,
                horizontalCenterDistance,
                verticalCenterDistance,
                Double(candidate.sourceIndex)
            ]
        case .leftward, .rightward:
            return [
                horizontalGap,
                verticalGap,
                verticalCenterDistance,
                horizontalCenterDistance,
                Double(candidate.sourceIndex)
            ]
        }
    }

    private static func intervalGap(
        _ firstMin: Double,
        _ firstMax: Double,
        _ secondMin: Double,
        _ secondMax: Double
    ) -> Double {
        if firstMax < secondMin {
            return secondMin - firstMax
        }
        if secondMax < firstMin {
            return firstMin - secondMax
        }
        return 0
    }

    private static func midX(_ frame: LayoutRect) -> Double {
        frame.minX + frame.width / 2
    }

    private static func midY(_ frame: LayoutRect) -> Double {
        frame.minY + frame.height / 2
    }

    private static func precedes(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right
        }
        return lhs.count < rhs.count
    }
}

/// A non-observable cache updated only when the board's layout inputs change.
/// Selection changes can then query spatial neighbors without solving all
/// reading frames again for every key repeat.
struct MasonryNavigationConfiguration: Equatable {
    let layout: CuttingsMasonryLayout
    let containerWidth: Double
    let configurationID: AnyHashable
}

@MainActor
final class MasonryNavigationCoordinator<Element: Equatable, ID: Hashable & Sendable> {
    private var index = MasonryNavigationIndex<ID>(ids: [], frames: [])
    private var elements: [Element] = []
    private var ids: [ID] = []
    private var configuration: MasonryNavigationConfiguration?
    private var hasSnapshot = false

    func updateIfNeeded(
        elements: [Element],
        ids: [ID],
        configuration: MasonryNavigationConfiguration,
        estimatedHeight: (Element, CGFloat) -> CGFloat
    ) {
        guard !hasSnapshot
            || self.elements != elements
            || self.ids != ids
            || self.configuration != configuration
        else { return }

        let layout = configuration.layout
        let containerWidth = configuration.containerWidth
        let columnWidth = CGFloat(layout.columnWidth(forContainerWidth: containerWidth))
        let metrics = elements.map { element in
            ItemMetric.fixedHeight(
                CuttingsMasonryLayout.normalizedHeight(
                    estimatedHeight(element, columnWidth)
                )
            )
        }
        let result = layout.layout(items: metrics, containerWidth: containerWidth)
        index = MasonryNavigationIndex(ids: ids, frames: result.frames)
        self.elements = elements
        self.ids = ids
        self.configuration = configuration
        hasSnapshot = true
    }

    func neighbor(of id: ID, toward direction: BoardNavigationDirection) -> ID? {
        index.neighbor(of: id, toward: direction)
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
    private let position: Binding<LazyLayoutPosition<ID>>?
    private let navigationCoordinator: MasonryNavigationCoordinator<Element, ID>?
    private let estimatedHeight: (Element, CGFloat) -> CGFloat
    private let content: (Element) -> AnyView

    init<Data>(
        _ data: Data,
        id: KeyPath<Element, ID>,
        minimumColumnWidth: CGFloat = 220,
        spacing: CGFloat = 18,
        contentInsets: EdgeInsets = .init(),
        configurationID: AnyHashable = 0,
        position: Binding<LazyLayoutPosition<ID>>? = nil,
        navigationCoordinator: MasonryNavigationCoordinator<Element, ID>? = nil,
        estimatedHeight: @escaping (Element, CGFloat) -> CGFloat = { _, _ in 180 },
        @ViewBuilder content: @escaping (Element) -> some View
    ) where Data: RandomAccessCollection, Data.Element == Element {
        let elements = Array(data)
        self.elements = elements
        self.id = id
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.configurationID = configurationID
        self.position = position
        self.navigationCoordinator = navigationCoordinator
        self.estimatedHeight = estimatedHeight
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

        GeometryReader { proxy in
            let containerWidth = Double(proxy.size.width)
            // A declaration is required here because this is a ViewBuilder scope.
            // swiftlint:disable:next redundant_discardable_let
            let _ = navigationCoordinator?.updateIfNeeded(
                elements: elements,
                ids: elements.map { $0[keyPath: id] },
                configuration: MasonryNavigationConfiguration(
                    layout: layout,
                    containerWidth: containerWidth,
                    configurationID: configurationID
                ),
                estimatedHeight: estimatedHeight
            )

            LazyLayoutView(
                elements,
                id: id,
                layout: layout,
                overscan: .items(80),
                position: position,
                recomputeOn: configurationID
            ) { element, containerWidth in
                .fixedHeight(
                    CuttingsMasonryLayout.normalizedHeight(
                        estimatedHeight(
                            element,
                            CGFloat(layout.columnWidth(forContainerWidth: containerWidth))
                        )
                    )
                )
            } content: { element in
                content(element)
            }
        }
    }
}
