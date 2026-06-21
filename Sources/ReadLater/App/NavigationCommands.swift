// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

/// Menu bar commands for navigating the main window.
struct NavigationCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
    }
}
