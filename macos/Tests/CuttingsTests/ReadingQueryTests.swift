// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class ReadingQueryTests: XCTestCase {
    func testSearchKeepsEverySelectedKindScope() {
        for scope in LibraryScope.allCases {
            let query = ReadingQuery.boardSnapshot(
                scope: scope,
                search: "texture",
                semanticCandidateIDs: ["first", "second"]
            )

            XCTAssertEqual(query.scope, scope)
            XCTAssertEqual(query.search, "texture")
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
            semanticCandidateIDs: []
        )

        XCTAssertEqual(query.scope, .media)
        XCTAssertNil(query.search)
        XCTAssertFalse(query.ascending)
        guard case .savedAt = query.sort else {
            return XCTFail("browsing should use saved-date ordering")
        }
    }
}
