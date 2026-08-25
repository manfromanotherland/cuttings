// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct DetailNavigationActions {
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let showsInspector: Bool
    let movePrevious: () -> Void
    let moveNext: () -> Void
    let toggleInspector: () -> Void
}

private struct DetailNavigationActionsKey: FocusedValueKey {
    typealias Value = DetailNavigationActions
}

extension FocusedValues {
    var detailNavigationActions: DetailNavigationActions? {
        get { self[DetailNavigationActionsKey.self] }
        set { self[DetailNavigationActionsKey.self] = newValue }
    }
}

/// Menu bar commands for navigating the main window.
struct NavigationCommands: Commands {
    var appState: AppState
    @FocusedValue(\.detailNavigationActions) private var detailNavigationActions

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("Focus Search") {
                appState.focusSearchField()
            }
            .keyboardShortcut(ShortcutCatalog.focusSearch)

            Button(appState.isFocusMode ? "Exit Focus Mode" : "Focus Mode") {
                appState.isFocusMode.toggle()
            }
            .keyboardShortcut(ShortcutCatalog.toggleFocusMode)

            if let detailNavigationActions {
                Divider()

                Button("Previous Item", action: detailNavigationActions.movePrevious)
                    .keyboardShortcut(ShortcutCatalog.previousItem)
                    .disabled(!detailNavigationActions.canMovePrevious || appState.isEditingText)

                Button("Next Item", action: detailNavigationActions.moveNext)
                    .keyboardShortcut(ShortcutCatalog.nextItem)
                    .disabled(!detailNavigationActions.canMoveNext || appState.isEditingText)

                Divider()

                Button(
                    detailNavigationActions.showsInspector ? "Hide Inspector" : "Show Inspector",
                    action: detailNavigationActions.toggleInspector
                )
            }
        }
    }
}
