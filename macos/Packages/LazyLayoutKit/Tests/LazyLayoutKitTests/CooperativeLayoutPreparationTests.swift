@testable import LazyLayoutKit
import XCTest

final class CooperativeLayoutPreparationTests: XCTestCase {
    @MainActor
    func testCancelledPreparationStopsBeforeMeasuringTheWholeCollection() async {
        var measured = 0
        let preparing = Task { @MainActor in
            try await CooperativeLayoutPreparation.items(Array(0 ..< 10_000)) { value in
                measured += 1
                return value
            }
        }
        await Task.yield()
        preparing.cancel()

        do {
            _ = try await preparing.value
            XCTFail("a cancelled layout must not publish an obsolete snapshot")
        } catch is CancellationError {
            XCTAssertLessThan(measured, 10_000)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testBatchesPreserveAllValuesAndStayBounded() async throws {
        var counts: [Int] = []
        let result = try await CooperativeLayoutPreparation.items(
            Array(0 ..< 100),
            make: { $0 },
            onBatch: { _, count in counts.append(count) }
        )
        XCTAssertEqual(result.items, Array(0 ..< 100))
        XCTAssertEqual(counts.reduce(0, +), 100)
        XCTAssertTrue(counts.allSatisfy { $0 > 0 && $0 <= 32 })
    }

    @MainActor
    func testLargeMeasurementAllowsQueuedMainActorWorkBeforeItCompletes() async throws {
        var measured = 0
        var measuredWhenServiced: Int?
        let prepared = try await CooperativeLayoutPreparation.items(Array(0 ..< 10_000)) { value in
            measured += 1
            if measured == 1 {
                Task { @MainActor in measuredWhenServiced = measured }
            }
            return value * 2
        }
        await Task.yield()

        XCTAssertEqual(prepared.items.count, 10_000)
        XCTAssertEqual(prepared.items.last, 19_998)
        let serviced = try XCTUnwrap(measuredWhenServiced)
        XCTAssertLessThan(serviced, 10_000, "preparation must not monopolize the main actor")
    }
}
