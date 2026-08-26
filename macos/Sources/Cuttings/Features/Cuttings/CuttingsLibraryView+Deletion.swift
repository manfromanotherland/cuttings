// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import SwiftUI

extension CuttingsLibraryView {
    var deleteDialogTitle: String {
        let count = appState.pendingDelete?.count ?? 0
        return count == 1 ? "Delete this item?" : "Delete \(count) items?"
    }

    func deleteButtonTitle(for rows: [ReadingRow]) -> String {
        rows.count == 1 ? "Delete item" : "Delete \(rows.count) items"
    }

    @ViewBuilder
    func deleteDialogMessage(for rows: [ReadingRow]) -> some View {
        if rows.count == 1, let row = rows.first {
            Text("“\(row.displayTitle)” and its local files will be permanently deleted.")
        } else {
            Text("The \(rows.count) selected items and their local files will be permanently deleted.")
        }
    }

    func delete(_ rows: [ReadingRow]) {
        appState.pendingDelete = nil
        if let presentedID = presentedReading?.id,
           rows.contains(where: { $0.id == presentedID })
        {
            closeOverlay()
        }
        boardFocused = true
        Task {
            await appState.delete(rows)
            guard boardFocused, presentedReading == nil, !appState.isEditingText else { return }
            if let id = appState.selectedId {
                boardPosition.scrollTo(id: id, anchor: .nearest)
            }
        }
    }
}
