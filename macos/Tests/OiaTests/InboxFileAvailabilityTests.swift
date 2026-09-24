// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class InboxFileAvailabilityTests: XCTestCase {
    func testWatcherPreservesPrecisePathsAndEscalatesDroppedEvents() {
        let first = FolderWatcher.Change.events(
            paths: ["/library/articles/ab/abc/article.md"],
            flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)]
        )
        XCTAssertEqual(first.paths, ["/library/articles/ab/abc/article.md"])
        XCTAssertFalse(first.requiresFullScan)
        let dropped = FolderWatcher.Change.events(
            paths: ["/library/articles"],
            flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)]
        )
        var combined = first
        combined.merge(dropped)
        XCTAssertTrue(combined.requiresFullScan)
        XCTAssertEqual(combined.paths.count, 2)
        XCTAssertTrue(FolderWatcher.Change.events(paths: ["/library/articles"], flags: []).requiresFullScan)
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inboxavailability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testOnlyUnavailableFilesAreDeferredAndRequested() throws {
        try makeFile("ready.txt")
        try makeFile("waiting.heic")
        var requested: [String] = []
        let deferred = try InboxFileAvailability.deferredNames(in: root) { url in
            url.lastPathComponent == "waiting.heic" ? .needsDownload : .available
        } requestDownload: { requested.append($0.lastPathComponent) }

        XCTAssertEqual(deferred, ["waiting.heic"])
        XCTAssertEqual(requested, ["waiting.heic"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("waiting.heic").path))
    }

    func testOfflineDownloadFailureKeepsTheItemDeferred() throws {
        try makeFile("waiting.mov")
        let deferred = try InboxFileAvailability.deferredNames(in: root) { _ in
            .needsDownload
        } requestDownload: { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }

        XCTAssertEqual(deferred, ["waiting.mov"])
    }

    func testUnavailableMetadataDefersOnlyThatItem() throws {
        try makeFile("ready.txt")
        try makeFile("unavailable.png")
        let deferred = try InboxFileAvailability.deferredNames(in: root) { url in
            if url.lastPathComponent == "unavailable.png" {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return .available
        } requestDownload: { _ in XCTFail("Metadata failure must not start a guessed download") }

        XCTAssertEqual(deferred, ["unavailable.png"])
    }

    func testLocalFilesAreAvailableAndSymlinksIgnored() throws {
        try makeFile("ready.txt")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: root.appendingPathComponent("ready.txt")
        )
        XCTAssertEqual(try InboxFileAvailability.inspect(root.appendingPathComponent("ready.txt")), .available)
        XCTAssertEqual(try InboxFileAvailability.inspect(link), .ignored)
    }

    func testDirectoryContentsAreNotVisited() throws {
        let nested = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: nested.appendingPathComponent("nested.txt"))
        var inspected: [String] = []
        let deferred = try InboxFileAvailability.deferredNames(in: root) { url in
            inspected.append(url.lastPathComponent)
            return .ignored
        } requestDownload: { _ in XCTFail("Directories must not be downloaded recursively") }

        XCTAssertEqual(inspected, ["folder"])
        XCTAssertEqual(deferred, [])
    }

    func testInboxSymlinkIsRejectedWithoutInspectingItsTarget() throws {
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try InboxFileAvailability.deferredNames(in: link) { _ in
            XCTFail("Must not inspect entries through a symlink")
            return .available
        })
    }

    func testPendingRetryDelayIsBounded() {
        XCTAssertEqual(InboxRetrySchedule.delay(attempt: 0), .seconds(2))
        XCTAssertEqual(InboxRetrySchedule.delay(attempt: 1), .seconds(5))
        XCTAssertEqual(InboxRetrySchedule.delay(attempt: 2), .seconds(10))
        XCTAssertEqual(InboxRetrySchedule.delay(attempt: 3), .seconds(30))
        XCTAssertEqual(InboxRetrySchedule.delay(attempt: 100), .seconds(30))
    }

    func testWatcherIncludesArticlesAndInbox() {
        XCTAssertEqual(FolderWatcher.watchPaths(libraryPath: root.path), [
            root.appendingPathComponent("articles").path,
            root.appendingPathComponent("inbox").path
        ])
    }

    private func makeFile(_ name: String) throws {
        try Data("keep".utf8).write(to: root.appendingPathComponent(name))
    }
}
