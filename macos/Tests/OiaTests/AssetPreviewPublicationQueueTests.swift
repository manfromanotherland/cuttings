// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class AssetPreviewPublicationQueueTests: XCTestCase {
    func testRefinementsAreReleasedInBoundedBatches() async {
        let clock = PublicationTestClock()
        let queue = AssetPreviewPublicationQueue(maximumPerBatch: 2) { await clock.wait() }
        let requests = (0 ..< 5).map { _ in Task { await queue.waitForTurn() } }
        await assertWaiting(queue, count: 5)
        await clock.advance()
        await assertWaiting(queue, count: 3)
        await clock.advance()
        await assertWaiting(queue, count: 1)
        await clock.advance()
        for request in requests {
            let admitted = await request.value
            XCTAssertTrue(admitted)
        }
        await assertWaiting(queue, count: 0)
    }

    func testCancelledRequestsLeaveNoBacklogAndFreshRequestCanPublish() async {
        let clock = PublicationTestClock()
        let queue = AssetPreviewPublicationQueue(maximumPerBatch: 2) { await clock.wait() }
        let stale = (0 ..< 100).map { _ in Task { await queue.waitForTurn() } }
        await assertWaiting(queue, count: 100)
        stale.forEach { $0.cancel() }
        for request in stale {
            let admitted = await request.value
            XCTAssertFalse(admitted)
        }
        await assertWaiting(queue, count: 0)
        let fresh = Task { await queue.waitForTurn() }
        await assertWaiting(queue, count: 1)
        await clock.advance()
        let admitted = await fresh.value
        XCTAssertTrue(admitted)
    }

    private func assertWaiting(
        _ queue: AssetPreviewPublicationQueue, count: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0 ..< 1000 {
            if await queue.waitingCount() == count {
                return
            }
            await Task.yield()
        }
        XCTFail("Unexpected publication backlog", file: file, line: line)
    }
}

private actor PublicationTestClock {
    private var ticks = 0
    private var pending: CheckedContinuation<Void, Never>?

    func wait() async {
        if ticks > 0 {
            ticks -= 1
            return
        }
        await withCheckedContinuation { pending = $0 }
    }

    func advance() {
        if let pending {
            self.pending = nil
            pending.resume()
        } else {
            ticks += 1
        }
    }
}
