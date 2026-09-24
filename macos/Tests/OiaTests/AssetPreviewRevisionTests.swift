// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

final class AssetPreviewRevisionTests: XCTestCase {
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
