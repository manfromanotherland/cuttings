// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Help-menu commands. Hosts the keyboard-shortcuts cheat sheet (⌘/).
struct HelpCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") {
                appState.showShortcuts = true
            }
            .keyboardShortcut(ShortcutCatalog.showShortcuts)
        }
    }
}
