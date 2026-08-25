// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class AssetPreviewDecodeQueueTests: XCTestCase {
    func testCancelledWaitersLeaveTheQueueImmediately() async {
        let queue = AssetPreviewDecodeQueue(limit: 1)
        let gate = AsyncGate()
        let holder = Task {
            await queue.withPermit {
                await gate.wait()
                return true
            }
        }
        let holderStarted = await waitForState(queue) { $0.active == 1 }
        XCTAssertTrue(holderStarted)

        let cancelled = (0 ..< 250).map { _ in
            Task { await queue.withPermit { true } }
        }
        let allQueued = await waitForState(queue) { $0.waiting == cancelled.count }
        XCTAssertTrue(allQueued)

        cancelled.forEach { $0.cancel() }
        let cancellationsDrained = await waitForState(queue) { $0.waiting == 0 }
        XCTAssertTrue(cancellationsDrained)
        let compactedState = await queue.state()
        XCTAssertEqual(compactedState.queuedSlots, 0)

        let fresh = Task { await queue.withPermit { true } }
        let freshQueued = await waitForState(queue) { $0.waiting == 1 }
        XCTAssertTrue(freshQueued)
        await gate.open()

        let holderResult = await holder.value
        let freshResult = await fresh.value
        XCTAssertEqual(holderResult, true)
        XCTAssertEqual(freshResult, true)
        for task in cancelled {
            _ = await task.value
        }

        let finalState = await queue.state()
        XCTAssertEqual(finalState.active, 0)
        XCTAssertEqual(finalState.waiting, 0)
        XCTAssertEqual(finalState.queuedSlots, 0)
    }

    func testCancellationRacingPermitReleaseDoesNotLeak() async {
        for _ in 0 ..< 20 {
            let queue = AssetPreviewDecodeQueue(limit: 1)
            let gate = AsyncGate()
            let holder = Task {
                await queue.withPermit {
                    await gate.wait()
                    return true
                }
            }
            let holderStarted = await waitForState(queue) { $0.active == 1 }
            XCTAssertTrue(holderStarted)

            let contenders = (0 ..< 32).map { _ in
                Task { await queue.withPermit { true } }
            }
            let allQueued = await waitForState(queue) { $0.waiting == contenders.count }
            XCTAssertTrue(allQueued)

            await withTaskGroup(of: Void.self) { group in
                group.addTask { contenders.forEach { $0.cancel() } }
                group.addTask { await gate.open() }
            }

            let drained = await waitForState(queue) {
                $0.active == 0 && $0.waiting == 0 && $0.queuedSlots == 0
            }
            XCTAssertTrue(drained, "Cancellation/release races must return every permit")
            guard drained else {
                holder.cancel()
                contenders.forEach { $0.cancel() }
                return
            }

            _ = await holder.value
            for contender in contenders {
                _ = await contender.value
            }
        }
    }

    private func waitForState(
        _ queue: AssetPreviewDecodeQueue,
        predicate: @escaping @Sendable (AssetPreviewDecodeQueue.State) -> Bool
    ) async -> Bool {
        for _ in 0 ..< 200 {
            if await predicate(queue.state()) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters.removeAll()
        waiting.forEach { $0.resume() }
    }
}
