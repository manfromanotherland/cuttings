// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

@MainActor
final class InteractionIdleGateTests: XCTestCase {
    func testScrollingDefersOptionalWorkUntilEveryBoardIsIdle() async throws {
        let gate = InteractionIdleGate(idleGrace: .zero)
        let first = UUID()
        let second = UUID()
        gate.setScrolling(true, sourceID: first)
        gate.setScrolling(true, sourceID: second)
        var resumed = false
        let work = Task {
            try await gate.waitUntilIdle()
            resumed = true
        }
        await settle()
        XCTAssertFalse(resumed)
        gate.setScrolling(false, sourceID: first)
        await settle()
        XCTAssertFalse(resumed, "One idle board must not release work while another is scrolling")
        gate.setScrolling(false, sourceID: second)
        try await work.value
        XCTAssertTrue(resumed)
    }

    func testCancellationReleasesAWaiterWhileTheBoardKeepsScrolling() async {
        let gate = InteractionIdleGate(idleGrace: .zero)
        let source = UUID()
        gate.setScrolling(true, sourceID: source)
        var finished = false
        var wasCancelled = false
        let work = Task {
            do {
                try await gate.waitUntilIdle()
            } catch is CancellationError {
                wasCancelled = true
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            finished = true
        }
        await settle()
        work.cancel()
        await settle()
        XCTAssertTrue(finished, "Cancellation must not wait for the board to stop scrolling")
        XCTAssertTrue(wasCancelled)
        gate.setScrolling(false, sourceID: source)
        await work.value
    }

    func testIdleGraceDefersWorkPastTheEndOfTheGesture() async throws {
        let gate = InteractionIdleGate(idleGrace: .milliseconds(80))
        let source = UUID()
        gate.setScrolling(true, sourceID: source)
        var resumed = false
        let work = Task {
            try await gate.waitUntilIdle()
            resumed = true
        }
        await settle()
        let stoppedAt = ContinuousClock.now
        gate.setScrolling(false, sourceID: source)
        await settle()
        XCTAssertFalse(resumed)
        try await work.value
        XCTAssertGreaterThanOrEqual(stoppedAt.duration(to: .now), .milliseconds(70))
    }

    func testNewGestureCancelsTheOldIdleRelease() async throws {
        let gate = InteractionIdleGate(idleGrace: .milliseconds(30))
        let source = UUID()
        gate.setScrolling(true, sourceID: source)
        var resumed = false
        let work = Task {
            try await gate.waitUntilIdle()
            resumed = true
        }
        await settle()
        gate.setScrolling(false, sourceID: source)
        gate.setScrolling(true, sourceID: source)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(resumed, "A previous idle timer must not release a new scrolling gesture")
        gate.setScrolling(false, sourceID: source)
        try await work.value
        XCTAssertTrue(resumed)
    }

    func testBoardPhaseChangesAndDisposalCannotStrandOptionalWork() async throws {
        let gate = InteractionIdleGate(idleGrace: .zero)
        var board: BoardScrollState? = BoardScrollState(interactionGate: gate)
        board?.setScrolling(true)
        var resumed = false
        let work = Task {
            try await gate.waitUntilIdle()
            resumed = true
        }
        await settle()
        XCTAssertFalse(resumed)
        board = nil
        try await work.value
        XCTAssertTrue(resumed)
    }

    func testAlreadyIdleWorkAndPrecancelledWorkDoNotWait() async throws {
        let gate = InteractionIdleGate()
        try await gate.waitUntilIdle()
        let work = Task {
            try await gate.waitUntilIdle()
        }
        work.cancel()
        do {
            try await work.value
            XCTFail("Precancelled work must throw cancellation")
        } catch is CancellationError {
            // Expected without needing a scroll transition.
        }
    }

    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }
}
