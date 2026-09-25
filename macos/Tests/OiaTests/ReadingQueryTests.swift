// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class ReadingQueryTests: XCTestCase {
    private enum SearchFailure: Error { case unavailable }

    @MainActor
    func testRefreshKeepsSemanticMembershipUntilTheCombinedResultIsReady() async throws {
        var queries: [[String]] = []
        var publications: [[String]] = []
        let completed = try await ReadingSnapshotDelivery.load(
            textFirst: false,
            fetch: { candidates in
                queries.append(candidates)
                return ["text"] + candidates
            },
            semanticCandidates: {
                XCTAssertTrue(publications.isEmpty)
                return ["semantic"]
            },
            isCurrent: { true },
            publish: { rows, _ in publications.append(rows) }
        )
        XCTAssertTrue(completed)
        XCTAssertEqual(queries, [["semantic"]])
        XCTAssertEqual(publications, [["text", "semantic"]])
    }

    @MainActor
    func testSemanticFailureKeepsPublishedTextResults() async throws {
        var publications: [[String]] = []
        var queryCount = 0
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { _ in queryCount += 1; return ["text"] },
            semanticCandidates: { throw SearchFailure.unavailable },
            isCurrent: { true },
            publish: { rows, _ in publications.append(rows) }
        )
        XCTAssertTrue(completed)
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(publications, [["text"]])
    }

    @MainActor
    func testEmptySemanticCandidatesDoNotRepeatTheCoreQuery() async throws {
        var queryCount = 0
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { _ in queryCount += 1; return ["text"] },
            semanticCandidates: { [] },
            isCurrent: { true },
            publish: { _, _ in }
        )
        XCTAssertTrue(completed)
        XCTAssertEqual(queryCount, 1)
    }

    @MainActor
    func testSupersededSemanticResultCannotReplaceTheNewerQuery() async throws {
        var current = true
        var publications: [[String]] = []
        var queryCount = 0
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { _ in queryCount += 1; return ["text"] },
            semanticCandidates: {
                current = false
                return ["stale semantic"]
            },
            isCurrent: { current },
            publish: { rows, _ in publications.append(rows) }
        )
        XCTAssertFalse(completed)
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(publications, [["text"]])
    }

    @MainActor
    func testSupersededTextQueryCannotPublishOrStartSemanticWork() async throws {
        var current = true
        var publications: [[String]] = []
        var semanticStarted = false
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { _ in current = false; return ["stale text"] },
            semanticCandidates: { semanticStarted = true; return [] },
            isCurrent: { current },
            publish: { rows, _ in publications.append(rows) }
        )
        XCTAssertFalse(completed)
        XCTAssertFalse(semanticStarted)
        XCTAssertTrue(publications.isEmpty)
    }

    @MainActor
    func testSemanticCancellationPreservesTextButDoesNotCompleteTheGeneration() async throws {
        var publications: [[String]] = []
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { _ in ["text"] },
            semanticCandidates: { throw CancellationError() },
            isCurrent: { true },
            publish: { rows, _ in publications.append(rows) }
        )
        XCTAssertFalse(completed)
        XCTAssertEqual(publications, [["text"]])
    }

    @MainActor
    func testTextResultsPublishBeforeSemanticSearchStarts() async throws {
        var publications: [[String]] = []
        var queries: [[String]] = []
        let completed = try await ReadingSnapshotDelivery.load(
            fetch: { candidates in
                queries.append(candidates)
                return candidates.isEmpty ? ["text"] : ["text", "semantic"]
            },
            semanticCandidates: {
                XCTAssertEqual(publications, [["text"]])
                return ["semantic"]
            },
            isCurrent: { true },
            publish: { rows, _ in publications.append(rows) }
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(queries, [[], ["semantic"]])
        XCTAssertEqual(publications, [["text"], ["text", "semantic"]])
    }

    func testSearchKeepsEverySelectedBoardScope() {
        for scope in LibraryScope.allCases {
            let query = ReadingQuery.boardSnapshot(
                scope: scope,
                search: "texture",
                tagTerms: ["interiors"],
                visualTerms: ["blue", "furniture"],
                semanticCandidateIDs: ["first", "second"]
            )

            XCTAssertEqual(query.scope, scope)
            XCTAssertEqual(query.search, "texture")
            XCTAssertEqual(query.tagTerms, ["interiors"])
            XCTAssertEqual(query.visualTerms, ["blue", "furniture"])
            XCTAssertEqual(query.semanticCandidateIDs, ["first", "second"])
            XCTAssertEqual(query.limit, .max)
            XCTAssertEqual(query.offset, 0)
            XCTAssertFalse(query.ascending)
            XCTAssertNil(query.kind)
            XCTAssertNil(query.tag)
            guard case .relevance = query.sort else {
                return XCTFail("search should use relevance ordering")
            }
        }
    }

    func testBrowsingUsesNewestFirstOrdering() {
        let query = ReadingQuery.boardSnapshot(
            scope: .media,
            search: nil,
            tagTerms: [],
            visualTerms: [],
            semanticCandidateIDs: []
        )

        XCTAssertEqual(query.scope, .media)
        XCTAssertNil(query.search)
        XCTAssertFalse(query.ascending)
        guard case .savedAt = query.sort else {
            return XCTFail("browsing should use saved-date ordering")
        }
    }

    func testStructuredTermsUseSearchOrderingWithoutFreeText() {
        let query = ReadingQuery.boardSnapshot(
            scope: .all,
            search: nil,
            tagTerms: ["chairs"],
            visualTerms: ["blue", "furniture"],
            semanticCandidateIDs: []
        )

        XCTAssertEqual(query.tagTerms, ["chairs"])
        XCTAssertEqual(query.visualTerms, ["blue", "furniture"])
        guard case .relevance = query.sort else {
            return XCTFail("structured search should use relevance ordering")
        }
    }
}
