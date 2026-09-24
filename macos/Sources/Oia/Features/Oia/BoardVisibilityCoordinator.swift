// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import Observation
import SwiftUI

/// A cell observes only its own visibility transitions, never raw scroll offsets.
@MainActor
@Observable
final class BoardCardVisibility {
    fileprivate(set) var isVisible = false
    fileprivate(set) var isNearViewport = false
}

private struct BoardCardVisibilityKey: EnvironmentKey {
    static var defaultValue: BoardCardVisibility? { nil }
}

extension EnvironmentValues {
    var boardCardVisibility: BoardCardVisibility? {
        get { self[BoardCardVisibilityKey.self] }
        set { self[BoardCardVisibilityKey.self] = newValue }
    }
}

/// Reuses the board's solved frames instead of installing a geometry observer
/// in every image, favicon, social post, and video card. Cell trackers are weakly
/// held so scrolling through a large library does not retain discarded cells.
@MainActor
final class BoardVisibilityCoordinator<ID: Hashable & Sendable> {
    private final class WeakTracker {
        weak var value: BoardCardVisibility?

        init(_ value: BoardCardVisibility) {
            self.value = value
        }
    }

    private var snapshot: LayoutSnapshot<ID>?
    private var viewport: LayoutRect?
    private var visibleIDs: Set<ID> = []
    private var nearbyIDs: Set<ID> = []
    private var trackers: [ID: WeakTracker] = [:]

    func tracker(for id: ID) -> BoardCardVisibility {
        if let tracker = trackers[id]?.value { return tracker }
        if trackers.count > 256 {
            trackers = trackers.filter { $0.value.value != nil }
        }
        let tracker = BoardCardVisibility()
        tracker.isVisible = visibleIDs.contains(id)
        tracker.isNearViewport = nearbyIDs.contains(id)
        trackers[id] = WeakTracker(tracker)
        return tracker
    }

    func update(snapshot: LayoutSnapshot<ID>) {
        self.snapshot = snapshot
        if let viewport { update(viewport: viewport) }
    }

    func update(viewport next: LayoutRect) {
        guard let snapshot else { return }
        let movingDown = next.y >= (viewport?.y ?? next.y)
        viewport = next
        let leadingMargin = next.height * (movingDown ? 0.125 : 0.5)
        let nearby = LayoutRect(
            x: next.x,
            y: next.y - leadingMargin,
            width: next.width,
            height: next.height * 1.625
        )
        let nextVisible = ids(in: next, snapshot: snapshot)
        let nextNearby = ids(in: nearby, snapshot: snapshot)
        for id in visibleIDs.symmetricDifference(nextVisible) {
            trackers[id]?.value?.isVisible = nextVisible.contains(id)
        }
        for id in nearbyIDs.symmetricDifference(nextNearby) {
            trackers[id]?.value?.isNearViewport = nextNearby.contains(id)
        }
        visibleIDs = nextVisible
        nearbyIDs = nextNearby
    }

    private func ids(in viewport: LayoutRect, snapshot: LayoutSnapshot<ID>) -> Set<ID> {
        guard viewport.width > 0, viewport.height > 0 else { return [] }
        return Set(snapshot.visibleItems(in: viewport).compactMap { position in
            let frame = snapshot.frames[position]
            guard frame.maxX > viewport.minX, frame.minX < viewport.maxX else { return nil }
            return snapshot.ids[position]
        })
    }
}
