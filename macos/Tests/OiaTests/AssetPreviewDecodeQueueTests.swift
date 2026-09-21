// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

final class AssetImageLoaderTests: XCTestCase {
    func testRasterAssetsDownsampleToRequestedPixelBounds() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemPink.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))

        let sourceImage = try XCTUnwrap(context.makeImage())
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: sourceImage).representation(using: .png, properties: [:])
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oia-raster-asset-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(
            AssetImageLoader.downsampledImage(at: url, maxPixel: 80)?.image
        )
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let downsampled = try XCTUnwrap(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )

        XCTAssertLessThanOrEqual(max(downsampled.width, downsampled.height), 80)
        XCTAssertEqual(Double(downsampled.width) / Double(downsampled.height), 2, accuracy: 0.01)
    }

    func testSVGAssetsDecodeThroughAssetLoader() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oia-svg-asset-\(UUID().uuidString).svg")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="64" height="32" viewBox="0 0 64 32">
          <rect width="64" height="32" fill="#ff00aa"/>
        </svg>
        """
        try svg.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNotNil(NSImage(contentsOf: url), "The SVG fixture must be valid to AppKit")

        let decoded = AssetImageLoader.downsampledImage(at: url, maxPixel: 80)
        guard let image = decoded?.image else {
            XCTFail("A valid local SVG must produce a board preview")
            return
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        let rasterized = try XCTUnwrap(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )
        XCTAssertLessThanOrEqual(max(rasterized.width, rasterized.height), 80)
    }
}

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

    func testReplacementRequestSharesActiveDecodeAfterCancellation() async {
        let queue = AssetPreviewDecodeQueue(limit: 3)
        let gate = AsyncGate()
        let counter = AsyncCounter()
        let url = URL(fileURLWithPath: "/tmp/oia-coalesced-preview.png")
        let key = AssetPreviewDecodeKey(kind: .image, url: url, maxPixel: 800)
        let decoded = AssetImageLoader.Decoded(image: NSImage(size: NSSize(width: 800, height: 500)))

        let original = Task {
            await queue.decode(key: key) {
                await counter.increment()
                await gate.wait()
                return decoded
            }
        }
        let originalStarted = await waitForState(queue) { $0.active == 1 }
        XCTAssertTrue(originalStarted)

        let replacement = Task {
            await queue.decode(key: key) {
                await counter.increment()
                return decoded
            }
        }
        let replacementCoalesced = await waitForState(queue) {
            $0.active == 1 && $0.coalescedWaiters == 1
        }
        XCTAssertTrue(replacementCoalesced)
        original.cancel()

        await gate.open()
        let originalResult = await original.value
        let replacementResult = await replacement.value
        let invocationCount = await counter.value()
        XCTAssertNotNil(originalResult)
        XCTAssertNotNil(replacementResult)
        XCTAssertEqual(invocationCount, 1)
    }

    func testCancelledSoleSubscriberDropsQueuedDecode() async {
        let queue = AssetPreviewDecodeQueue(limit: 1)
        let permitGate = AsyncGate()
        let counter = AsyncCounter()
        let holder = Task {
            await queue.withPermit {
                await permitGate.wait()
                return true
            }
        }
        let holderStarted = await waitForState(queue) { $0.active == 1 }
        XCTAssertTrue(holderStarted)

        let url = URL(fileURLWithPath: "/tmp/oia-cancelled-preview.png")
        let key = AssetPreviewDecodeKey(kind: .image, url: url, maxPixel: 160)
        let request = Task {
            await queue.decode(key: key) {
                await counter.increment()
                return nil
            }
        }
        let requestQueued = await waitForState(queue) {
            $0.waiting == 1 && $0.inFlightDecodes == 1
        }
        XCTAssertTrue(requestQueued)

        request.cancel()
        let requestDrained = await waitForState(queue) {
            $0.waiting == 0 && $0.inFlightDecodes == 0
        }
        XCTAssertTrue(requestDrained)
        await permitGate.open()

        _ = await holder.value
        let requestResult = await request.value
        let invocationCount = await counter.value()
        XCTAssertNil(requestResult)
        XCTAssertEqual(invocationCount, 0)
    }

    func testCompletedDecodeIsCachedBeforeTheInFlightJobEnds() async throws {
        let url = try makeTemporaryRasterURL()
        let key = AssetPreviewDecodeKey(kind: .image, url: url, maxPixel: 80)
        let queue = AssetPreviewDecodeQueue(limit: 3)

        let first = await queue.image(at: url, maxPixel: 80)
        XCTAssertNotNil(first)
        XCTAssertNotNil(AssetPreviewImageCache.shared.entry(for: key))

        try FileManager.default.removeItem(at: url)
        let reused = await AssetPreviewDecodeQueue(limit: 3).image(at: url, maxPixel: 80)
        let differentSize = await AssetPreviewDecodeQueue(limit: 3).image(at: url, maxPixel: 81)

        XCTAssertNotNil(reused, "A replacement request must reuse the completed exact-size decode")
        XCTAssertNil(differentSize, "A detail or board size must not contaminate another cache key")
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

private func makeTemporaryRasterURL() throws -> URL {
    let context = try XCTUnwrap(CGContext(
        data: nil,
        width: 80,
        height: 40,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.systemPink.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    let sourceImage = try XCTUnwrap(context.makeImage())
    let data = try XCTUnwrap(
        NSBitmapImageRep(cgImage: sourceImage).representation(using: .png, properties: [:])
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("oia-cached-preview-\(UUID().uuidString).png")
    try data.write(to: url, options: .atomic)
    return url
}

private actor AsyncCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
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
