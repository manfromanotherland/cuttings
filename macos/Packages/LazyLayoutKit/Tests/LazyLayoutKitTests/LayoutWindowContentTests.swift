@testable import LazyLayoutKit
import XCTest

final class LayoutWindowContentTests: XCTestCase {
    private struct Item: Equatable {
        let id: Int
        let title: String
    }

    func testOldScrollWindowRemainsSafeWhileReplacementCollectionShrinks() {
        let snapshotElements = (0 ..< 100).map { Item(id: $0, title: "Item \($0)") }
        // The replacement layout is still being measured. A scroll event asks
        // the old snapshot for a new window beyond the shortened input's end.
        let currentElements = Array(snapshotElements.prefix(2))
        let window = (90 ..< 100).map { position in
            LayoutWindowContent.element(
                at: position,
                matching: snapshotElements[position].id,
                currentElements: currentElements,
                currentIDs: currentElements.map(\.id),
                fallback: snapshotElements[position]
            )
        }
        XCTAssertEqual(window, Array(snapshotElements.suffix(10)))
    }

    func testInsertionDoesNotPairOldGeometryWithADifferentIdentity() {
        let previous = [Item(id: 1, title: "First"), Item(id: 2, title: "Second")]
        let current = [Item(id: 0, title: "Inserted")] + previous
        let element = LayoutWindowContent.element(
            at: 1, matching: previous[1].id,
            currentElements: current, currentIDs: current.map(\.id),
            fallback: previous[1]
        )
        XCTAssertEqual(element, previous[1])
    }

    func testMetadataChangeUsesLatestPayloadWithUnchangedGeometryIdentity() {
        let previous = Item(id: 1, title: "Previous title")
        let current = Item(id: 1, title: "Edited title")
        let element = LayoutWindowContent.element(
            at: 0, matching: previous.id,
            currentElements: [current], currentIDs: [current.id],
            fallback: previous
        )
        XCTAssertEqual(element, current)
    }
}
