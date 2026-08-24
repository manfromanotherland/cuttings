// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Menu bar commands for navigating the main window.
struct NavigationCommands: Commands {
    var appState: AppState

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
        }
    }
}
