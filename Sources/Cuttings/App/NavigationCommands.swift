// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Menu bar commands for navigating the main window.
struct NavigationCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                )
            }
            .keyboardShortcut(ShortcutCatalog.toggleSidebar)

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
