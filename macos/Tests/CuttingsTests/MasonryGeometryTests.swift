// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import LazyLayoutKit
import SwiftUI
import XCTest

final class MasonryGeometryTests: XCTestCase {
    private struct Item: Identifiable, Equatable, Sendable {
        let id: Int
        let ratio: Double
    }

    @MainActor
    private final class PositionModel: ObservableObject {
        @Published var position = LazyLayoutPosition<Int>()
    }

    private struct PositionedBoard: View {
        @ObservedObject var model: PositionModel
        let items: [Item]
        let built: Box<Set<Int>>

        var body: some View {
            LazyMasonryBoard(
                items,
                id: \.id,
                minimumColumnWidth: CardSize.small.minimumColumnWidth,
                spacing: 18,
                contentInsets: EdgeInsets(top: 12, leading: 18, bottom: 18, trailing: 18),
                position: $model.position,
                estimatedHeight: { item, width in width / item.ratio },
                content: { item in
                    Color.gray
                        .onAppear { built.value.insert(item.id) }
                }
            )
        }
    }

    func testFiveCardSizesProduceDistinctDefaultWindowDensities() {
        let columnCounts = CardSize.allCases.map { size in
            layout(for: size).columnCount(forContainerWidth: 1064)
        }
        XCTAssertEqual(columnCounts, [5, 4, 3, 2, 1])
    }

    func testFiveCardSizesRemainDistinctOnWideBoard() {
        let renderedWidths = CardSize.allCases.map { size in
            layout(for: size).columnWidth(forContainerWidth: 2524)
        }

        for (smaller, larger) in zip(renderedWidths, renderedWidths.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
    }

    func testInsetsArePartOfTheScrollableGeometry() throws {
        let layout = layout(for: .small)
        let result = layout.layout(items: [.fixedHeight(100)], containerWidth: 900)
        let frame = try XCTUnwrap(result.frames.first)

        XCTAssertEqual(frame.x, 18)
        XCTAssertEqual(frame.y, 12)
        XCTAssertEqual(frame.height, 100)
        XCTAssertEqual(result.contentHeight, 130)
    }

    func testColumnAssignmentsAreDeterministic() {
        let metrics = makeItems(5000).map { ItemMetric.aspectRatio($0.ratio) }
        let layout = layout(for: .small)

        let first = layout.layout(items: metrics, containerWidth: 1064)
        let second = layout.layout(items: metrics, containerWidth: 1064)

        XCTAssertEqual(first, second)
    }

    func testStableIDsResolveTheirOwnFramesAfterEveryZoomLevel() {
        let items = makeItems(5000)
        let ids = items.map(\.id)
        let metrics = items.map { ItemMetric.aspectRatio($0.ratio) }

        for size in CardSize.allCases {
            let layout = layout(for: size)
            let result = layout.layout(items: metrics, containerWidth: 1064)
            let snapshot = LayoutSnapshot(ids: ids, result: result, containerWidth: 1064)

            for index in [0, 1, 117, 2048, 4999] {
                XCTAssertEqual(snapshot.position(of: ids[index]), index)
                XCTAssertEqual(snapshot.frame(of: ids[index]), result.frames[index])
            }
        }
    }

    func testLargeBoardVisibilityLookupStaysViewportBounded() {
        let items = makeItems(10000)
        let layout = layout(for: .small)
        let result = layout.layout(
            items: items.map { .aspectRatio($0.ratio) },
            containerWidth: 1064
        )
        let snapshot = LayoutSnapshot(
            ids: items.map(\.id),
            result: result,
            containerWidth: 1064
        )
        let viewport = LayoutRect(
            x: 0,
            y: result.contentHeight / 2,
            width: 1064,
            height: 800
        )

        XCTAssertLessThan(snapshot.visibleItems(in: viewport).count, 100)
    }

    func testVerticalNavigationStaysInTheSameMasonryColumn() {
        let index = navigationIndex()

        XCTAssertEqual(index.neighbor(of: 0, toward: .downward), 3)
        XCTAssertEqual(index.neighbor(of: 3, toward: .upward), 0)
    }

    func testHorizontalNavigationChoosesTheAdjacentAlignedCard() {
        let index = navigationIndex()

        XCTAssertEqual(index.neighbor(of: 3, toward: .rightward), 4)
        XCTAssertEqual(index.neighbor(of: 4, toward: .leftward), 3)
    }

    func testHorizontalNavigationUsesTheTallCardsMidpoint() {
        let index = MasonryNavigationIndex(
            ids: [0, 1, 2],
            frames: [
                LayoutRect(x: 0, y: 0, width: 100, height: 300),
                LayoutRect(x: 118, y: 0, width: 100, height: 100),
                LayoutRect(x: 118, y: 118, width: 100, height: 100)
            ]
        )

        XCTAssertEqual(index.neighbor(of: 0, toward: .rightward), 2)
    }

    func testNavigationStopsAtEveryOuterEdge() {
        let index = navigationIndex()

        XCTAssertNil(index.neighbor(of: 0, toward: .upward))
        XCTAssertNil(index.neighbor(of: 0, toward: .leftward))
        XCTAssertNil(index.neighbor(of: 2, toward: .rightward))
        XCTAssertNil(index.neighbor(of: 5, toward: .downward))
        XCTAssertNil(index.neighbor(of: 999, toward: .downward))
    }

    @MainActor
    func testLargeBoardMaterializesOnlyAViewportWindow() {
        let items = makeItems(5000)
        let built = Box<Set<Int>>([])
        let board = LazyMasonryBoard(
            items,
            id: \.id,
            minimumColumnWidth: CardSize.small.minimumColumnWidth,
            spacing: 18,
            contentInsets: EdgeInsets(top: 12, leading: 18, bottom: 18, trailing: 18),
            estimatedHeight: { item, width in width / item.ratio },
            content: { item in
                Color.gray
                    .onAppear { built.value.insert(item.id) }
            }
        )

        let (window, materialized) = host(board) { !built.value.isEmpty }
        defer { window.close() }

        XCTAssertTrue(materialized, "the board never materialized its initial viewport")
        XCTAssertLessThan(built.value.count, 120)
        XCTAssertTrue(built.value.contains(0))
        XCTAssertFalse(built.value.contains(items.count - 1))
    }

    @MainActor
    func testPositionBindingScrollsToAnUnmaterializedCard() {
        let items = makeItems(5000)
        let built = Box<Set<Int>>([])
        let model = PositionModel()
        let board = PositionedBoard(model: model, items: items, built: built)

        let (window, materialized) = host(board) { !built.value.isEmpty }
        defer { window.close() }
        XCTAssertTrue(materialized)
        XCTAssertFalse(built.value.contains(items.count - 1))

        model.position.scrollTo(id: items.count - 1, anchor: .nearest)
        let deadline = Date().addingTimeInterval(5)
        while !built.value.contains(items.count - 1), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(built.value.contains(items.count - 1))
    }
}

extension MasonryGeometryTests {
    func testSmallCardSizePreservesExistingColumnWidth() {
        XCTAssertEqual(CardSize.small.minimumColumnWidth, 220)
    }

    func testCardSizesProduceIncreasingColumnWidths() {
        XCTAssertLessThan(
            CardSize.extraSmall.minimumColumnWidth, CardSize.small.minimumColumnWidth
        )
        XCTAssertLessThan(CardSize.small.minimumColumnWidth, CardSize.medium.minimumColumnWidth)
        XCTAssertLessThan(CardSize.medium.minimumColumnWidth, CardSize.large.minimumColumnWidth)
        XCTAssertLessThan(
            CardSize.large.minimumColumnWidth, CardSize.extraLarge.minimumColumnWidth
        )
    }

    func testCardPreviewDecodeTracksRenderedBackingSize() {
        XCTAssertEqual(CardSize.small.previewMaxPixel(displayScale: 2), 512)
        XCTAssertEqual(CardSize.medium.previewMaxPixel(displayScale: 2), 600)
        XCTAssertEqual(CardSize.large.previewMaxPixel(displayScale: 2), 800)
    }

    func testCardPreviewDecodeHasSafeBounds() {
        XCTAssertEqual(CardSize.small.previewMaxPixel(displayScale: .nan), 512)
        XCTAssertEqual(CardSize.large.previewMaxPixel(displayScale: 4), 1024)
    }

    func testCardSizesStepInPersistedSizeOrder() {
        XCTAssertEqual(
            CardSize.allCases,
            [.extraSmall, .small, .medium, .large, .extraLarge]
        )
        XCTAssertEqual(
            CardSize.allCases.map(\.rawValue),
            ["extraSmall", "small", "medium", "large", "extraLarge"]
        )
        XCTAssertNil(CardSize.extraSmall.smaller)
        XCTAssertEqual(CardSize.extraSmall.larger, .small)
        XCTAssertEqual(CardSize.small.smaller, .extraSmall)
        XCTAssertEqual(CardSize.small.larger, .medium)
        XCTAssertEqual(CardSize.medium.smaller, .small)
        XCTAssertEqual(CardSize.medium.larger, .large)
        XCTAssertEqual(CardSize.large.smaller, .medium)
        XCTAssertEqual(CardSize.large.larger, .extraLarge)
        XCTAssertEqual(CardSize.extraLarge.smaller, .large)
        XCTAssertNil(CardSize.extraLarge.larger)
    }

    private func layout(for size: CardSize) -> CuttingsMasonryLayout {
        CuttingsMasonryLayout(
            minimumColumnWidth: Double(size.minimumColumnWidth),
            spacing: 18,
            topInset: 12,
            leadingInset: 18,
            bottomInset: 18,
            trailingInset: 18
        )
    }

    private func makeItems(_ count: Int) -> [Item] {
        (0 ..< count).map { index in
            Item(id: index, ratio: 0.6 + Double(index % 15) * 0.1)
        }
    }

    private func navigationIndex() -> MasonryNavigationIndex<Int> {
        MasonryNavigationIndex(
            ids: Array(0 ... 5),
            frames: [
                LayoutRect(x: 0, y: 0, width: 100, height: 100),
                LayoutRect(x: 118, y: 0, width: 100, height: 140),
                LayoutRect(x: 236, y: 0, width: 100, height: 80),
                LayoutRect(x: 0, y: 118, width: 100, height: 120),
                LayoutRect(x: 118, y: 158, width: 100, height: 80),
                LayoutRect(x: 236, y: 98, width: 100, height: 140)
            ]
        )
    }

    @MainActor
    private func host(
        _ view: some View,
        until condition: () -> Bool
    ) -> (window: NSWindow, satisfied: Bool) {
        let size = NSSize(width: 900, height: 700)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFront(nil)
        window.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return (window, condition())
    }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
