// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

final class AssetPreviewRevisionTests: XCTestCase {
    func testWarmPreviewResolvesWhileTheSourceLaneIsOccupied() async throws {
        let fixture = try ReplacementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.preloadPreview()
        let queue = AssetPreviewDecodeQueue(limit: 1)
        let probe = RevisionDecodeProbe()
        let occupied = Task {
            await queue.withPermit {
                await probe.decode(at: fixture.source, maxPixel: 80, kind: .image)
            }
        }
        let started = await probe.waitForInvocations(1)
        XCTAssertTrue(started)
        let completion = CacheLookupCompletion()
        let lookup = Task {
            let cached = await queue.cachedPreview(at: fixture.source, maxPixel: 80, kind: .image)
            await completion.finish(found: cached != nil)
        }
        let foundBeforeRelease = await completion.waitForResult()
        let occupiedState = await queue.state()
        await probe.releaseFirst()
        _ = await occupied.value
        _ = await lookup.value
        XCTAssertEqual(occupiedState.active, 1)
        XCTAssertEqual(foundBeforeRelease, true, "Cached cards must not wait for occupied source decode lanes")
    }

    func testReplacementSourceDoesNotJoinAnActiveDecodeOfItsPreviousRevision() async throws {
        let fixture = try ReplacementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = RevisionDecodeProbe()
        let queue = AssetPreviewDecodeQueue(
            limit: 3,
            diskCache: AssetPreviewDiskCache(rootURL: fixture.root.appendingPathComponent("cache"), byteLimit: 0),
            sourceDecoder: { await probe.decode(at: $0, maxPixel: $1, kind: $2) }
        )
        let original = Task { await queue.image(at: fixture.source, maxPixel: 80) }
        let firstStarted = await probe.waitForInvocations(1)
        XCTAssertTrue(firstStarted)
        try fixture.replaceSource()
        let newest = Task { await queue.image(at: fixture.source, maxPixel: 80) }
        let replacementStarted = await probe.waitForInvocations(2)
        await probe.releaseFirst()
        let originalResult = await original.value
        let newestResult = await newest.value
        XCTAssertNil(originalResult, "A source changed during decode must not publish its obsolete image")
        XCTAssertTrue(replacementStarted, "The newest request must get its own source revision")
        let image = try XCTUnwrap(newestResult?.image)
        XCTAssertEqual(image.size.width / image.size.height, 0.5, accuracy: 0.01)
    }
}

private struct ReplacementFixture {
    let root: URL
    var source: URL { root.appendingPathComponent("source.png") }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("oia-revision-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeImage(width: 80, height: 40)
    }

    func replaceSource() throws {
        try writeImage(width: 40, height: 80)
    }

    func preloadPreview() throws {
        let decoded = try XCTUnwrap(AssetImageLoader.downsampledImage(at: source, maxPixel: 80))
        let fingerprint = try XCTUnwrap(AssetPreviewSourceFingerprint.read(at: source))
        let key = AssetPreviewDecodeKey(kind: .image, url: source, maxPixel: 80)
        AssetPreviewImageCache.shared.insert(decoded.image, for: key, fingerprint: fingerprint)
    }

    private func writeImage(width: Int, height: Int) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try bytes.write(to: source, options: .atomic)
    }
}

private actor CacheLookupCompletion {
    private var result: Bool?

    func finish(found: Bool) {
        result = found
    }

    func waitForResult() async -> Bool? {
        for _ in 0 ..< 200 {
            if let result { return result }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return nil
    }
}

private actor RevisionDecodeProbe {
    private var invocations = 0
    private var first: CheckedContinuation<Void, Never>?

    func decode(
        at source: URL, maxPixel: CGFloat, kind _: AssetPreviewDecodeKey.Kind
    ) async -> AssetImageLoader.Decoded? {
        invocations += 1
        let decoded = AssetImageLoader.downsampledImage(at: source, maxPixel: maxPixel)
        if invocations == 1 {
            await withCheckedContinuation { first = $0 }
        }
        return decoded
    }

    func waitForInvocations(_ count: Int) async -> Bool {
        for _ in 0 ..< 200 {
            if invocations >= count { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    func releaseFirst() {
        first?.resume()
        first = nil
    }
}
