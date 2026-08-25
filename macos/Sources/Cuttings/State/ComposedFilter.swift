// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Pure decision logic for the board's selected scope. Extracted from
/// `AppState` so it can be unit-tested without the core, filesystem, or AppKit.
enum ComposedFilter {
    /// Whether `row` belongs in the list under the selected scope.
    static func matches(_ row: ReadingRow, scope: LibraryScope) -> Bool {
        scope.contains(row)
    }

    /// The selection to land on when the row at `index` leaves the list (it fell
    /// out of the filter): the next row, else the previous, else nothing. Computed
    /// against the list *before* the removal.
    static func selectionAfterRemoving(at index: Int, from readings: [ReadingRow]) -> String? {
        if index + 1 < readings.count {
            return readings[index + 1].id
        }
        if index > 0 {
            return readings[index - 1].id
        }
        return nil
    }
}
