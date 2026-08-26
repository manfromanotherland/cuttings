// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension CuttingsLibraryView {
    var searchQuery: Binding<String> {
        Binding(
            get: { appState.searchQuery },
            set: { appState.searchQuery = $0 }
        )
    }

    var scopeSelection: Binding<LibraryScope> {
        Binding(
            get: { appState.activeScope },
            set: { appState.selectScope($0) }
        )
    }

    var focusedBoardActions: BoardActions {
        BoardActions(
            canOpenSelection: presentedReading == nil && singleSelectedRow != nil,
            canFocusSearch: presentedReading == nil && !appState.isFocusMode,
            openSelection: openSelection,
            focusSearch: focusSearch
        )
    }

    var boardMagnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                let startingSize = pinchStartCardSize ?? cardSize
                pinchStartCardSize = startingSize
                cardSize = startingSize.zoomed(by: value.magnification)
            }
            .onEnded { _ in
                pinchStartCardSize = nil
            }
    }

    var singleSelectedRow: ReadingRow? {
        let rows = appState.selectedRows
        return rows.count == 1 ? rows.first : nil
    }

    func openSelection() {
        guard presentedReading == nil, let row = singleSelectedRow else { return }
        open(row)
    }

    func focusSearch() {
        guard presentedReading == nil, !appState.isFocusMode else { return }
        searchFocused = true
    }
}
