// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

final class SpotlightThumbnailManifestTests: XCTestCase {
    func testThumbnailNameIsStableAndDoesNotExposeLibraryIdentity() {
        let first = SpotlightThumbnailNaming.filename(
            readingID: "private-reading-name",
            assetHash: "asset-hash"
        )
        let second = SpotlightThumbnailNaming.filename(
            readingID: "private-reading-name",
            assetHash: "asset-hash"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 68)
        XCTAssertTrue(first.hasSuffix(".png"))
        XCTAssertFalse(first.contains("private-reading-name"))
        XCTAssertNotEqual(
            first,
            SpotlightThumbnailNaming.filename(
                readingID: "private-reading-name",
                assetHash: "new-hash"
            )
        )
    }

    func testBootRepairRedonatesButIncrementalPassReusesUnchangedThumbnail() throws {
        let asset = makeAsset(id: "one", hash: "hash", title: "One")
        let filename = SpotlightThumbnailNaming.filename(
            readingID: asset.readingID,
            assetHash: asset.assetHash
        )
        let existing = SpotlightThumbnailManifest(entries: [
            asset.readingID: SpotlightThumbnailManifestEntry(
                assetHash: asset.assetHash,
                displayTitle: asset.displayTitle,
                thumbnailFilename: filename
            )
        ])

        let bootRepair = try SpotlightReconciliationPlan.make(
            existing: existing,
            desired: [asset],
            availableThumbnailFilenames: [filename],
            includeUnchangedDonations: true
        )
        XCTAssertEqual(bootRepair.upserts.count, 1)
        XCTAssertFalse(try XCTUnwrap(bootRepair.upserts.first).needsThumbnail)
        XCTAssertEqual(bootRepair.unchangedCount, 1)

        let incremental = try SpotlightReconciliationPlan.make(
            existing: existing,
            desired: [asset],
            availableThumbnailFilenames: [filename],
            includeUnchangedDonations: false
        )
        XCTAssertTrue(incremental.upserts.isEmpty)
        XCTAssertEqual(incremental.unchangedCount, 1)
    }

    func testIncrementalPassDonatesTitleHashAndMissingThumbnailChanges() throws {
        let fixture = existingAssetFixture()
        try assertTitleChangeUsesExistingThumbnail(fixture)
        try assertHashChangeRegeneratesThumbnail(fixture)
        try assertMissingThumbnailIsRegenerated(fixture)
    }

    private func assertTitleChangeUsesExistingThumbnail(
        _ fixture: ExistingAssetFixture
    ) throws {
        let renamed = makeAsset(id: "one", hash: "old", title: "New")
        let titlePlan = try SpotlightReconciliationPlan.make(
            existing: fixture.manifest,
            desired: [renamed],
            availableThumbnailFilenames: [fixture.filename],
            includeUnchangedDonations: false
        )
        XCTAssertEqual(titlePlan.upserts.count, 1)
        XCTAssertFalse(try XCTUnwrap(titlePlan.upserts.first).needsThumbnail)
    }

    private func assertHashChangeRegeneratesThumbnail(
        _ fixture: ExistingAssetFixture
    ) throws {
        let changed = makeAsset(id: "one", hash: "new", title: "New")
        let hashPlan = try SpotlightReconciliationPlan.make(
            existing: fixture.manifest,
            desired: [changed],
            availableThumbnailFilenames: [fixture.filename],
            includeUnchangedDonations: false
        )
        XCTAssertTrue(try XCTUnwrap(hashPlan.upserts.first).needsThumbnail)
        XCTAssertEqual(hashPlan.obsoleteThumbnailFilenames, [fixture.filename])
    }

    private func assertMissingThumbnailIsRegenerated(
        _ fixture: ExistingAssetFixture
    ) throws {
        let missingPlan = try SpotlightReconciliationPlan.make(
            existing: fixture.manifest,
            desired: [fixture.asset],
            availableThumbnailFilenames: [],
            includeUnchangedDonations: false
        )
        XCTAssertTrue(try XCTUnwrap(missingPlan.upserts.first).needsThumbnail)
    }

    func testFailedThumbnailIsOmittedAndScheduledForRetryWithoutDroppingValidItem() throws {
        let valid = makeAsset(id: "valid", hash: "valid-hash", title: "Valid")
        let corrupt = makeAsset(id: "corrupt", hash: "corrupt-hash", title: "Corrupt")
        let plan = try SpotlightReconciliationPlan.make(
            existing: .empty,
            desired: [valid, corrupt],
            availableThumbnailFilenames: [],
            includeUnchangedDonations: false
        )

        let commit = plan.committing(excludingReadingIDs: [corrupt.readingID])

        XCTAssertEqual(commit.upserts.map(\.asset.readingID), [valid.readingID])
        XCTAssertEqual(commit.deletedReadingIDs, [corrupt.readingID])
        XCTAssertNotNil(commit.manifest.entries[valid.readingID])
        XCTAssertNil(commit.manifest.entries[corrupt.readingID])
        XCTAssertTrue(commit.obsoleteThumbnailFilenames.contains(
            SpotlightThumbnailNaming.filename(
                readingID: corrupt.readingID,
                assetHash: corrupt.assetHash
            )
        ))
    }

    func testRemovedReadingsAndOrphanThumbnailsAreDeleted() throws {
        let retained = makeAsset(id: "retained", hash: "hash", title: nil)
        let retainedFilename = SpotlightThumbnailNaming.filename(
            readingID: retained.readingID,
            assetHash: retained.assetHash
        )
        let removedFilename = "removed.png"
        let existing = SpotlightThumbnailManifest(entries: [
            retained.readingID: SpotlightThumbnailManifestEntry(
                assetHash: retained.assetHash,
                displayTitle: nil,
                thumbnailFilename: retainedFilename
            ),
            "removed": SpotlightThumbnailManifestEntry(
                assetHash: "gone",
                displayTitle: nil,
                thumbnailFilename: removedFilename
            )
        ])

        let plan = try SpotlightReconciliationPlan.make(
            existing: existing,
            desired: [retained],
            availableThumbnailFilenames: [retainedFilename, removedFilename, "orphan.png"],
            includeUnchangedDonations: false
        )

        XCTAssertEqual(plan.deletedReadingIDs, ["removed"])
        XCTAssertEqual(plan.obsoleteThumbnailFilenames, ["orphan.png", removedFilename])
    }

    func testDuplicateReadingIDIsRejected() {
        let first = makeAsset(id: "same", hash: "one", title: nil)
        let second = makeAsset(id: "same", hash: "two", title: nil)

        XCTAssertThrowsError(try SpotlightReconciliationPlan.make(
            existing: .empty,
            desired: [first, second],
            availableThumbnailFilenames: [],
            includeUnchangedDonations: false
        )) { error in
            guard case SpotlightVisualIndexError.duplicateReadingID("same") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManifestStoreRoundTripsOnlyDerivedState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cuttings-spotlight-manifest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpotlightThumbnailManifestStore(rootURL: root)
        let manifest = SpotlightThumbnailManifest(entries: [
            "one": SpotlightThumbnailManifestEntry(
                assetHash: "hash",
                displayTitle: "One",
                thumbnailFilename: "thumbnail.png"
            )
        ])

        try store.save(manifest)
        XCTAssertEqual(try store.load(), .present(manifest))
    }

    private func makeAsset(
        id: String,
        hash: String,
        title: String?
    ) -> SpotlightVisualAsset {
        SpotlightVisualAsset(
            readingID: id,
            assetHash: hash,
            assetURL: URL(fileURLWithPath: "/library/\(id).png"),
            displayTitle: title
        )
    }

    private func existingAssetFixture() -> ExistingAssetFixture {
        let asset = makeAsset(id: "one", hash: "old", title: "Old")
        let filename = SpotlightThumbnailNaming.filename(
            readingID: asset.readingID,
            assetHash: asset.assetHash
        )
        let manifest = SpotlightThumbnailManifest(entries: [
            asset.readingID: SpotlightThumbnailManifestEntry(
                assetHash: asset.assetHash,
                displayTitle: asset.displayTitle,
                thumbnailFilename: filename
            )
        ])
        return ExistingAssetFixture(asset: asset, filename: filename, manifest: manifest)
    }
}

private struct ExistingAssetFixture {
    let asset: SpotlightVisualAsset
    let filename: String
    let manifest: SpotlightThumbnailManifest
}
