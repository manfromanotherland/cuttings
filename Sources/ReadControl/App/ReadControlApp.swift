// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@main
struct ReadControlApp: App {
    @State private var appState = AppState()
    @AppStorage("appearanceMode", store: AppDefaults.store) private var appearanceMode: AppearanceMode = .system

    init() {
        // Single-window app: disable macOS automatic window tabbing so the
        // "New Tab", "Show Tab Bar", and "Move Tab to New Window" items never appear.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onChange(of: appearanceMode, initial: true) { _, mode in
                    NSApplication.shared.appearance = mode.nsAppearance
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            ArticleCommands(appState: appState)
            TypographyCommands()
            AppearanceCommands(appearanceMode: $appearanceMode)
            NavigationCommands(appState: appState)
            HelpCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
