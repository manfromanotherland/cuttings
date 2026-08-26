// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import SwiftUI

extension CuttingsLibraryView {
    func select(_ row: ReadingRow, extending: Bool) {
        guard presentedReading == nil else { return }
        appState.selectReading(id: row.id, extending: extending)
        boardFocused = true
    }

    func moveSelection(_ press: KeyPress) -> KeyPress.Result {
        guard !appState.isEditingText, presentedReading == nil else { return .ignored }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .ignored
        }
        guard let direction = navigationDirection(for: press.key) else { return .ignored }

        guard let currentID = appState.selectedId,
              appState.readings.contains(where: { $0.id == currentID })
        else {
            guard let firstID = appState.readings.first?.id else { return .handled }
            appState.selectReading(id: firstID, extending: false)
            boardPosition.scrollTo(id: firstID, anchor: .nearest)
            return .handled
        }

        guard let targetID = boardNavigation.neighbor(of: currentID, toward: direction),
              appState.readings.contains(where: { $0.id == targetID })
        else {
            return .handled
        }
        appState.selectReading(
            id: targetID,
            extending: press.modifiers.contains(.shift)
        )
        boardPosition.scrollTo(id: targetID, anchor: .nearest)
        return .handled
    }

    func performBoardShortcut(_ press: KeyPress) -> KeyPress.Result {
        guard !appState.isEditingText, presentedReading == nil else { return .ignored }

        if ShortcutCatalog.open.matches(key: press.key, modifiers: press.modifiers) {
            guard appState.selectedRows.count == 1 else { return .ignored }
            openSelection()
            return .handled
        }

        if ShortcutCatalog.focusSearch.matches(key: press.key, modifiers: press.modifiers),
           !appState.isFocusMode
        {
            // The menu command and this board-local `/` path share SwiftUI's
            // native `.searchFocused` binding.
            focusSearch()
            return .handled
        }

        return .ignored
    }

    private func navigationDirection(for key: KeyEquivalent) -> BoardNavigationDirection? {
        switch key {
        case .upArrow:
            .upward
        case .downArrow:
            .downward
        case .leftArrow:
            .leftward
        case .rightArrow:
            .rightward
        default:
            nil
        }
    }
}
