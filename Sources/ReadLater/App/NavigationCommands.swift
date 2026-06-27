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
            .keyboardShortcut("s", modifiers: [.control, .command])

            Button("Focus Search") {
                appState.focusSearchField()
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}
