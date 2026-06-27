// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

/// Menu bar commands for navigating the main window.
struct NavigationCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
            .keyboardShortcut(ShortcutCatalog.toggleSidebar)

            Button("Focus Search") {
                appState.focusSearchField()
            }
            .keyboardShortcut(ShortcutCatalog.focusSearch)
        }
    }
}
