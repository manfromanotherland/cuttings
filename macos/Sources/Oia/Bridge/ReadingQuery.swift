// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A reading-list query in app language: the composed kind/scope/tag filter, an
/// optional full-text search, the sort, and result bounds. `CoreBridge` turns
/// it into the core's compatible `FfiListOptions` at the bridge boundary.
struct ReadingQuery {
    var kind: ReadingKind?
    var scope: LibraryScope
    var sort: ReadingSort
    var ascending: Bool
    var tag: String?
    var search: String?
    /// Core Spotlight's best-first semantic matches for `search`. The Rust
    /// core merges these candidates with its own text/label/colour results so
    /// filters and relevance ordering stay one coherent query.
    var semanticCandidateIDs: [String]
    var limit: UInt32
    var offset: UInt32
}

extension ReadingQuery {
    /// The board always composes its selected scope and optional search into
    /// one core query. Search changes ordering, never the active board scope.
    static func boardSnapshot(
        scope: LibraryScope,
        search: String?,
        semanticCandidateIDs: [String]
    ) -> Self {
        Self(
            kind: nil,
            scope: scope,
            sort: search == nil ? .savedAt : .relevance,
            ascending: false,
            tag: nil,
            search: search,
            semanticCandidateIDs: semanticCandidateIDs,
            limit: .max,
            offset: 0
        )
    }
}

/// Delivers one captured search generation. The native client supplies its
/// generation guard; the Rust query owns filtering and combined relevance.
enum ReadingSnapshotDelivery {
    @MainActor
    static func load<Rows>(
        textFirst: Bool = true,
        fetch: @MainActor ([String]) async throws -> Rows,
        semanticCandidates: (@MainActor () async throws -> [String])?,
        isCurrent: @MainActor () -> Bool,
        publish: @MainActor (Rows, Bool) -> Void
    ) async throws -> Bool {
        guard isCurrent() else { return false }
        // Reconciliation of an already displayed semantic query keeps its
        // membership stable until one complete replacement is available.
        if !textFirst, let semanticCandidates {
            guard let candidates = await optionalCandidates(semanticCandidates),
                  isCurrent() else { return false }
            let rows = try await fetch(candidates)
            guard isCurrent() else { return false }
            publish(rows, !candidates.isEmpty)
            return true
        }
        let rows = try await fetch([])
        guard isCurrent() else { return false }
        publish(rows, false)
        guard let semanticCandidates, isCurrent() else { return isCurrent() }

        guard let candidates = await optionalCandidates(semanticCandidates),
              isCurrent() else { return false }
        guard !candidates.isEmpty else { return true }

        let enriched = try await fetch(candidates)
        guard isCurrent() else { return false }
        publish(enriched, true)
        return true
    }

    @MainActor
    private static func optionalCandidates(
        _ load: @MainActor () async throws -> [String]
    ) async -> [String]? {
        do {
            return try await load()
        } catch is CancellationError {
            return nil
        } catch {
            // Spotlight is optional. Its failure must not hide local results.
            return []
        }
    }
}
