// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI
import XCTest

final class MasonryGeometryTests: XCTestCase {
    @MainActor private static var retainedPerformanceWindow: NSWindow?

    @MainActor
    func testLargeBoardMaterializesABoundedNumberOfCards() {
        guard let context = makePerformanceContext() else { return }
        XCTAssertGreaterThan(context.counter.live.count, 0)
        XCTAssertLessThanOrEqual(context.counter.live.count, 120)

        traverseEveryPage(context)
        assertBoundedWork(context)
    }

    @MainActor
    func testRedundantVisibilityUpdatesDoNotInvalidateHostedCard() {
        let item = MasonryHostingItem()
        _ = item.view
        MasonryHostingItem.resetVisibilityMutationCount()

        item.setVisible(true)
        let mutationsAfterFirstUpdate = MasonryHostingItem.visibilityMutationCount
        for _ in 0 ..< 120 {
            item.setVisible(true)
        }

        XCTAssertEqual(
            MasonryHostingItem.visibilityMutationCount,
            mutationsAfterFirstUpdate
        )
        item.setVisible(false)
        XCTAssertEqual(
            MasonryHostingItem.visibilityMutationCount,
            mutationsAfterFirstUpdate + 1
        )
    }

    @MainActor
    func testScrollingDoesNotRelayoutCardsAsTheyEnterViewport() throws {
        let corpus = MasonryTestCorpus()
        corpus.count = 90
        let board = MasonryFrameStabilityHarness(corpus: corpus)
        let host = NSHostingView(rootView: AnyView(board))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        Self.retainedPerformanceWindow = window

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(firstScrollView(in: host))
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        )
        let target = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 45, section: 0))
        )

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: target.frame.minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        collectionView.layoutSubtreeIfNeeded()
        let framesAtScroll = masonryFrames(layout: layout, count: corpus.count)

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        collectionView.layoutSubtreeIfNeeded()
        let framesAfterMaterializing = masonryFrames(layout: layout, count: corpus.count)
        let moved = framesAtScroll.indices.filter {
            framesAtScroll[$0] != framesAfterMaterializing[$0]
        }

        XCTAssertTrue(
            moved.isEmpty,
            "Entering the viewport must not change masonry geometry; moved cards: \(moved.prefix(12))"
        )
    }

    @MainActor
    func testCardSizeChangePreservesViewportAnchorAndSettlesOnce() throws {
        guard let context = makePerformanceContext() else { return }
        context.corpus.count = 180
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        context.host.layoutSubtreeIfNeeded()

        let anchorIndex = 90
        let beforeLayout = try XCTUnwrap(
            context.collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        )
        let beforeFrame = try XCTUnwrap(
            beforeLayout.layoutAttributesForItem(
                at: IndexPath(item: anchorIndex, section: 0)
            )?.frame
        )
        context.scrollView.contentView.scroll(
            to: NSPoint(x: 0, y: beforeFrame.minY - 24)
        )
        context.scrollView.reflectScrolledClipView(context.scrollView.contentView)
        let beforeOffset = beforeFrame.minY - context.collectionView.visibleRect.minY

        context.corpus.minimumColumnWidth = 300
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        context.host.layoutSubtreeIfNeeded()

        let afterLayout = try XCTUnwrap(
            context.collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        )
        let afterFrame = try XCTUnwrap(
            afterLayout.layoutAttributesForItem(
                at: IndexPath(item: anchorIndex, section: 0)
            )?.frame
        )
        let afterOffset = afterFrame.minY - context.collectionView.visibleRect.minY
        XCTAssertEqual(afterOffset, beforeOffset, accuracy: 1)

        let settledFrames = masonryFrames(layout: afterLayout, count: context.corpus.count)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let laterFrames = masonryFrames(layout: afterLayout, count: context.corpus.count)
        XCTAssertEqual(settledFrames, laterFrames)
    }

    @MainActor
    func testHeightGenerationRebuildsFramesWithIdenticalItems() throws {
        guard let context = makePerformanceContext() else { return }
        let indexPath = IndexPath(item: 12, section: 0)
        let beforeLayout = try XCTUnwrap(
            context.collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        )
        XCTAssertEqual(
            beforeLayout.layoutAttributesForItem(at: indexPath)?.frame.height,
            180
        )

        context.corpus.cardHeight = 240
        context.corpus.heightGeometryGeneration += 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        context.host.layoutSubtreeIfNeeded()

        let afterLayout = try XCTUnwrap(
            context.collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        )
        XCTAssertFalse(afterLayout === beforeLayout)
        XCTAssertEqual(
            afterLayout.layoutAttributesForItem(at: indexPath)?.frame.height,
            240
        )
    }

    @MainActor
    private func makePerformanceContext() -> MasonryPerformanceContext? {
        MasonryHostingItem.resetAllocationCount()
        let corpus = MasonryTestCorpus()
        let counter = MasonryCardLifetimeCounter()
        let board = MasonryPerformanceHarness(corpus: corpus, counter: counter)

        let host = NSHostingView(rootView: AnyView(board))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        Self.retainedPerformanceWindow = window

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()

        guard let scrollView = firstScrollView(in: host),
              let collectionView = scrollView.documentView as? NSCollectionView,
              let layout = collectionView.collectionViewLayout as? MasonryCollectionViewLayout
        else {
            XCTFail("The virtualized board did not install its collection scroll view")
            return nil
        }
        return MasonryPerformanceContext(
            corpus: corpus,
            counter: counter,
            host: host,
            scrollView: scrollView,
            collectionView: collectionView,
            layout: layout
        )
    }

    @MainActor
    private func traverseEveryPage(_ context: MasonryPerformanceContext) {
        for page in 2 ... 84 {
            context.corpus.count = page * 60
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            context.host.layoutSubtreeIfNeeded()

            let bottom = max(
                0,
                (context.scrollView.documentView?.bounds.height ?? 0)
                    - context.scrollView.contentView.bounds.height
            )
            context.scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            context.scrollView.reflectScrolledClipView(context.scrollView.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))

            XCTAssertTrue(
                context.counter.appeared.contains(context.corpus.count - 1),
                "Every appended page must actually reach its final card"
            )
            XCTAssertLessThanOrEqual(
                context.counter.live.count,
                120,
                "Appending and scrolling must not retain the accumulated card prefix"
            )
        }
    }

    @MainActor
    private func assertBoundedWork(_ context: MasonryPerformanceContext) {
        XCTAssertGreaterThan(
            context.counter.appeared.count,
            500,
            "The test must traverse enough distinct cards to exercise reuse"
        )
        XCTAssertLessThanOrEqual(
            context.counter.peakLiveCount,
            120,
            "A viewport should not materialize an ever-growing prefix of the board"
        )
        XCTAssertLessThanOrEqual(
            MasonryHostingItem.allocationCount,
            120,
            "The collection view must reuse hosting items instead of accumulating them"
        )

        _ = context.layout.layoutAttributesForElements(in: context.collectionView.visibleRect)
        XCTAssertLessThanOrEqual(
            context.layout.lastQueryInspectionCount,
            120,
            "Viewport lookup must not scan every loaded card"
        )

        context.layout.invalidateHeights(at: [context.corpus.count - 1])
        context.layout.prepare()
        XCTAssertLessThanOrEqual(
            context.layout.lastPreparedItemCount,
            1,
            "An explicit item-height change must not rebuild the entire board"
        )
    }

    @MainActor
    private func masonryFrames(
        layout: MasonryCollectionViewLayout,
        count: Int
    ) -> [CGRect] {
        (0 ..< count).compactMap {
            layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
        }
    }

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

    func testFiveCardSizesProduceDistinctDefaultWindowDensities() {
        let columnCounts = CardSize.allCases.map { size in
            MasonryGeometry.columnCount(
                width: 1064,
                minimumColumnWidth: size.minimumColumnWidth,
                spacing: 18,
                maximum: 6
            )
        }

        XCTAssertEqual(columnCounts, [5, 4, 3, 2, 1])
    }

    func testFiveCardSizesRemainDistinctOnWideBoard() {
        let width: CGFloat = 2524
        let renderedWidths = CardSize.allCases.map { size in
            let columns = MasonryGeometry.columnCount(
                width: width,
                minimumColumnWidth: size.minimumColumnWidth,
                spacing: 18,
                maximum: Int.max
            )
            return MasonryGeometry.columnWidth(
                width: width,
                columns: columns,
                spacing: 18
            )
        }

        for (smaller, larger) in zip(renderedWidths, renderedWidths.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
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

    func testPreviewAssetParticipatesInCardGeometryIdentity() {
        var row = makeReadingRow()
        let withoutPreview = MasonryCardGeometryIdentity(row: row)
        row.previewAsset = "assets/social.jpg"
        let withPreview = MasonryCardGeometryIdentity(row: row)

        XCTAssertNotEqual(withoutPreview, withPreview)
        XCTAssertEqual(withPreview, MasonryCardGeometryIdentity(row: row))
    }

    func testResolvedWidthFallsBackForUnboundedProposals() {
        for proposedWidth: CGFloat? in [nil, .infinity, -.infinity, .nan] {
            XCTAssertEqual(
                MasonryGeometry.resolvedWidth(
                    proposedWidth: proposedWidth, minimumColumnWidth: 220
                ),
                220
            )
        }
    }

    func testColumnCountRespectsAvailableWidthAndMaximum() {
        XCTAssertEqual(
            MasonryGeometry.columnCount(
                width: 900, minimumColumnWidth: 220, spacing: 18, maximum: 6
            ),
            3
        )
        XCTAssertEqual(
            MasonryGeometry.columnCount(
                width: 2000, minimumColumnWidth: 220, spacing: 18, maximum: 6
            ),
            6
        )
    }

    func testColumnCountRejectsNonFiniteWidth() {
        for width: CGFloat in [.infinity, -.infinity, .nan] {
            XCTAssertEqual(
                MasonryGeometry.columnCount(
                    width: width, minimumColumnWidth: 220, spacing: 18, maximum: 6
                ),
                1
            )
        }
    }

    func testColumnWidthAccountsForGaps() {
        XCTAssertEqual(
            MasonryGeometry.columnWidth(width: 696, columns: 3, spacing: 18),
            220,
            accuracy: 0.001
        )
    }

    func testShortestColumnPrefersFirstOnTie() {
        XCTAssertEqual(MasonryGeometry.shortestColumn(in: [120, 80, 80]), 1)
        XCTAssertEqual(MasonryGeometry.shortestColumn(in: []), 0)
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
}

@MainActor
private struct MasonryPerformanceContext {
    let corpus: MasonryTestCorpus
    let counter: MasonryCardLifetimeCounter
    let host: NSHostingView<AnyView>
    let scrollView: NSScrollView
    let collectionView: NSCollectionView
    let layout: MasonryCollectionViewLayout
}

@MainActor
@Observable
private final class MasonryTestCorpus {
    var count = 60
    var minimumColumnWidth: CGFloat = 220
    var cardHeight: CGFloat = 180
    var heightGeometryGeneration = 0
}

@MainActor
private final class MasonryCardLifetimeCounter {
    private(set) var appeared: Set<Int> = []
    private(set) var live: Set<Int> = []
    private(set) var peakLiveCount = 0

    func appear(_ id: Int) {
        appeared.insert(id)
        live.insert(id)
        peakLiveCount = max(peakLiveCount, live.count)
    }

    func disappear(_ id: Int) {
        live.remove(id)
    }
}

private struct MasonryPerformanceHarness: View {
    @Bindable var corpus: MasonryTestCorpus
    let counter: MasonryCardLifetimeCounter

    var body: some View {
        MasonryBoard(
            Array(0 ..< corpus.count),
            id: \.self,
            width: 900,
            minimumColumnWidth: corpus.minimumColumnWidth,
            spacing: 18,
            geometryID: corpus.heightGeometryGeneration,
            cardHeight: { _, _ in corpus.cardHeight }
        ) { id in
            Color.clear
                .frame(height: 180)
                .onAppear { counter.appear(id) }
                .onDisappear { counter.disappear(id) }
        }
        .frame(width: 900, height: 700)
    }
}

private struct MasonryFrameStabilityHarness: View {
    @Bindable var corpus: MasonryTestCorpus

    var body: some View {
        MasonryBoard(
            Array(0 ..< corpus.count),
            id: \.self,
            width: 900,
            minimumColumnWidth: 220,
            spacing: 18,
            cardHeight: { _, _ in 180 }
        ) { id in
            Color.clear
                .frame(height: id.isMultiple(of: 2) ? 320 : 120)
        }
        .frame(width: 900, height: 700)
    }
}

@MainActor
private func firstScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView {
        return scrollView
    }
    for subview in view.subviews {
        if let match = firstScrollView(in: subview) {
            return match
        }
    }
    return nil
}
